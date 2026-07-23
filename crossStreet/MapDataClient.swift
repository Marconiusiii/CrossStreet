//
//  MapDataClient.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import CoreLocation
import Foundation

struct MapDataClient: MapDataFetching {
	var endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
	var fallbackEndpoints = [
		URL(string: "https://overpass.private.coffee/api/interpreter")!,
		URL(string: "https://maps.mail.ru/osm/tools/overpass/api/interpreter")!
	]
	var session: URLSession = .shared
	var requestHandler: (@Sendable (URLRequest) async throws -> MapHTTPResponse)?
	private static let cache = MapDataCache()
	private static let endpointHealth = MapEndpointHealth()
	private let endpointStaggerMilliseconds = 750
	private let overallRequestTimeoutMilliseconds = 12_000

	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions = MapDetailOptions()
	) async throws -> [IntersectionCandidate] {
		try await mapData(near: coordinate, radiusMeters: radiusMeters, options: options).intersections
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions = MapDetailOptions()
	) async throws -> MapDataSet {
		try await Self.cache.data(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		) {
			try await fetchMapData(near: coordinate, radiusMeters: radiusMeters, options: options)
			}
	}

	func freshMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions = MapDetailOptions()
	) async throws -> MapDataSet {
		try await fetchMapData(near: coordinate, radiusMeters: radiusMeters, options: options)
	}

	func immediateMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions = MapDetailOptions()
	) async throws -> MapDataSet {
		var coreOptions = options
		coreOptions.includeWalkingPaths = false
		let immediateCoreOptions = coreOptions

		return try await Self.cache.data(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: immediateCoreOptions
		) {
			try await fetchMapData(near: coordinate, radiusMeters: radiusMeters, options: immediateCoreOptions)
		}
	}

	func roadMapData(
		near coordinate: CLLocationCoordinate2D,
		roadName: String,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions = MapDetailOptions()
	) async throws -> MapDataSet {
		try await fetchMapData(
			near: coordinate,
			options: options,
			query: focusedRoadQuery(
				near: coordinate,
				roadName: roadName,
				radiusMeters: radiusMeters,
				options: options
			)
		)
	}

	private func fetchMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		try await fetchMapData(
			near: coordinate,
			options: options,
			query: roadQuery(
				near: coordinate,
				radiusMeters: radiusMeters,
				options: options
			)
		)
	}

	private func fetchMapData(
		near coordinate: CLLocationCoordinate2D,
		options: MapDetailOptions,
		query: String
	) async throws -> MapDataSet {
		let endpoints = await Self.endpointHealth.orderedEndpoints(
			primary: endpoint,
			fallbacks: fallbackEndpoints
		)
		let outcome = await withTaskGroup(of: MapEndpointAttempt.self) { group in
			for (index, endpoint) in endpoints.enumerated() {
				group.addTask {
					do {
						if index > 0 {
							try await Task.sleep(for: .milliseconds(index * endpointStaggerMilliseconds))
						}
						try Task.checkCancellation()
						let data = try await fetchMapData(
							from: endpoint,
							options: options,
							query: query
						)
						return MapEndpointAttempt(endpoint: endpoint, result: .success(data))
					} catch {
						return MapEndpointAttempt(endpoint: endpoint, result: .failure(error))
					}
				}
			}
			group.addTask {
				do {
					try await Task.sleep(for: .milliseconds(overallRequestTimeoutMilliseconds))
					return MapEndpointAttempt(endpoint: nil, result: .failure(URLError(.timedOut)))
				} catch {
					return MapEndpointAttempt(endpoint: nil, result: .failure(error))
				}
			}

			var lastError: Error = MapDataError.invalidResponse
			var remainingEndpoints = endpoints.count
			while let attempt = await group.next() {
				switch attempt.result {
				case .success(let data):
					if let endpoint = attempt.endpoint {
						await Self.endpointHealth.markSuccess(endpoint)
					}
					group.cancelAll()
					return Result<MapDataSet, Error>.success(data)
				case .failure(let error):
					if attempt.endpoint == nil {
						group.cancelAll()
						return Result<MapDataSet, Error>.failure(error)
					}
					remainingEndpoints -= 1
					lastError = error
					if let endpoint = attempt.endpoint, isTemporary(error) {
						await Self.endpointHealth.markTemporaryFailure(endpoint)
					}
					if remainingEndpoints == 0 {
						group.cancelAll()
						return Result<MapDataSet, Error>.failure(lastError)
					}
				}
			}
			return Result<MapDataSet, Error>.failure(lastError)
		}

		return try outcome.get()
	}

	private func fetchMapData(
		from endpoint: URL,
		options: MapDetailOptions,
		query: String
	) async throws -> MapDataSet {
		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.timeoutInterval = 12
		request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		request.httpBody = query.data(using: .utf8)

		let httpResult: MapHTTPResponse
		if let requestHandler {
			httpResult = try await requestHandler(request)
		} else {
			let (data, urlResponse) = try await session.data(for: request)
			httpResult = MapHTTPResponse(data: data, response: urlResponse)
		}
		let data = httpResult.data
		let urlResponse = httpResult.response
		guard let httpResponse = urlResponse as? HTTPURLResponse else {
			throw MapDataError.invalidResponse
		}
		guard (200..<300).contains(httpResponse.statusCode) else {
			throw MapDataError.serverError(httpResponse.statusCode)
		}
		let response: OverpassResponse
		do {
			response = try JSONDecoder().decode(OverpassResponse.self, from: data)
		} catch {
			throw MapDataError.invalidMapData
		}
		return IntersectionBuilder().mapData(from: response, options: options)
	}

	private func isTemporary(_ error: Error) -> Bool {
		if let mapError = error as? MapDataError {
			switch mapError {
			case .serverError(let statusCode):
				return [429, 500, 502, 503, 504].contains(statusCode)
			case .invalidResponse, .invalidMapData:
				return false
			}
		}

		if let urlError = error as? URLError {
			switch urlError.code {
			case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
				return true
			default:
				return false
			}
		}

		return false
	}

	private func roadQuery(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) -> String {
		let radius = Int(radiusMeters.rounded())
		var highwayTypes = [
			"primary",
			"primary_link",
			"secondary",
			"secondary_link",
			"tertiary",
			"tertiary_link",
			"unclassified",
			"residential",
			"living_street",
			"pedestrian",
			"road"
		]
		if options.includeWalkingPaths {
			highwayTypes += [
				"footway",
				"path",
				"steps",
				"bridleway"
			]
		}
		let highwayPattern = highwayTypes.joined(separator: "|")
		let crossingRadius = Int(min(radiusMeters, 225).rounded())
		let crossingSetup = options.includeCrossings ? """
		(
		  node(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["highway"="crossing"];
		  node(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["crossing"];
		)->.crossingNodes;
		way(bn.crossingNodes)["highway"="service"]->.crossingServiceWays;
		""" : ""
		let crossingResults = options.includeCrossings
			? ".crossingNodes;.crossingServiceWays;"
			: ""
		let body = """
		[out:json][timeout:10];
		\(crossingSetup)
		(
		  way(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["highway"~"^(\(highwayPattern))$"]["name"];
		  \(crossingResults)
		);
		(._;>;);
		out body;
		"""
		return encodedBody(body)
	}

	private func focusedRoadQuery(
		near coordinate: CLLocationCoordinate2D,
		roadName: String,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) -> String {
		let radius = Int(radiusMeters.rounded())
		let escapedRoadName = roadName
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		var highwayTypes = [
			"primary", "primary_link", "secondary", "secondary_link", "tertiary",
			"tertiary_link", "unclassified", "residential", "living_street", "pedestrian", "road"
		]
		if options.includeWalkingPaths {
			highwayTypes += ["footway", "path", "steps", "bridleway"]
		}
		let highwayPattern = highwayTypes.joined(separator: "|")
		let body = """
		[out:json][timeout:10];
		way(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["highway"~"^(\(highwayPattern))$"]["name"="\(escapedRoadName)"]->.currentRoad;
		node(w.currentRoad)->.currentRoadNodes;
		way(bn.currentRoadNodes)["highway"~"^(\(highwayPattern))$"]["name"]->.connectedRoads;
		(.currentRoad;.connectedRoads;);
		(._;>;);
		out body;
		"""
		return encodedBody(body)
	}

	private var userAgent: String {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
		return "Intersector/\(version) (com.marconius.crossStreet; marco@marconius.com)"
	}

	private func encodedBody(_ body: String) -> String {
		let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
		let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
		return "data=\(encoded)"
	}
}

struct MapHTTPResponse: @unchecked Sendable {
	var data: Data
	var response: URLResponse
}

private struct MapEndpointAttempt: @unchecked Sendable {
	var endpoint: URL?
	var result: Result<MapDataSet, Error>
}

actor MapEndpointHealth {
	private var preferredEndpoint: URL?
	private var unhealthyUntil: [URL: Date] = [:]
	private let cooldown: TimeInterval = 60

	func orderedEndpoints(primary: URL, fallbacks: [URL]) -> [URL] {
		let endpoints = ([primary] + fallbacks).removingDuplicates()
		let now = Date()
		let healthyEndpoints = endpoints.filter { endpoint in
			guard let retryAfter = unhealthyUntil[endpoint] else {
				return true
			}
			return retryAfter <= now
		}
		let availableEndpoints = healthyEndpoints.isEmpty ? endpoints : healthyEndpoints

		guard let preferredEndpoint, availableEndpoints.contains(preferredEndpoint) else {
			return availableEndpoints
		}
		return [preferredEndpoint] + availableEndpoints.filter { $0 != preferredEndpoint }
	}

	func markSuccess(_ endpoint: URL) {
		preferredEndpoint = endpoint
		unhealthyUntil[endpoint] = nil
	}

	func markTemporaryFailure(_ endpoint: URL) {
		unhealthyUntil[endpoint] = Date().addingTimeInterval(cooldown)
		if preferredEndpoint == endpoint {
			preferredEndpoint = nil
		}
	}
}

private extension Array where Element: Hashable {
	nonisolated func removingDuplicates() -> [Element] {
		var seen = Set<Element>()
		return filter { seen.insert($0).inserted }
	}
}

enum MapDataError: LocalizedError {
	case invalidResponse
	case serverError(Int)
	case invalidMapData

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			"The map server returned an unreadable response."
		case .serverError(let statusCode):
			Self.serverErrorDescription(for: statusCode)
		case .invalidMapData:
			"The map server returned data Intersector could not read."
		}
	}

	private static func serverErrorDescription(for statusCode: Int) -> String {
		switch statusCode {
		case 429:
			"The map server returned error 429, which usually means too many requests."
		case 502, 503:
			"The map server returned error \(statusCode), which usually means it is temporarily unavailable."
		case 504:
			"The map server returned error 504, which usually means the request timed out."
		default:
			"The map server returned error \(statusCode)."
		}
	}
}

actor MapDataCache {
	private struct Entry {
		var center: CLLocationCoordinate2D
		var radiusMeters: CLLocationDistance
		var options: MapDetailOptions
		var storedAt: Date
		var data: MapDataSet
	}

	private struct InFlightRequest {
		var center: CLLocationCoordinate2D
		var radiusMeters: CLLocationDistance
		var options: MapDetailOptions
		var task: Task<MapDataSet, Error>
	}

	private let reuseDistanceMeters: CLLocationDistance = 150
	private let timeToLive: TimeInterval = 300
	private let staleTimeToLive: TimeInterval = 900
	private let maxEntries = 4
	private var entries: [Entry] = []
	private var inFlightRequest: InFlightRequest?

	func data(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions = MapDetailOptions(),
		fetch: @escaping @Sendable () async throws -> MapDataSet
	) async throws -> MapDataSet {
		if let entry = entries.first(where: { canReuse($0, for: coordinate, radiusMeters: radiusMeters, options: options) }) {
			return entry.data
		}

		if let inFlightRequest,
		   canReuse(inFlightRequest, for: coordinate, radiusMeters: radiusMeters, options: options) {
			return try await inFlightRequest.task.value
		}

		if let entry = entries.first(where: { canReuseStale($0, for: coordinate, radiusMeters: radiusMeters, options: options) }) {
			return entry.data
		}

		let task = Task {
			try await fetch()
		}
		inFlightRequest = InFlightRequest(
			center: coordinate,
			radiusMeters: radiusMeters,
			options: options,
			task: task
		)

		do {
			let data = try await task.value
			store(
				Entry(
					center: coordinate,
					radiusMeters: radiusMeters,
					options: options,
					storedAt: Date(),
					data: data
				)
			)
			inFlightRequest = nil
			return data
		} catch {
			inFlightRequest = nil
			if let entry = entries.first(where: { canReuseStale($0, for: coordinate, radiusMeters: radiusMeters, options: options) }) {
				return entry.data
			}
			throw error
		}
	}

	private func store(_ entry: Entry) {
		entries.removeAll {
			$0.options == entry.options && sameArea(
				center: $0.center,
				radiusMeters: $0.radiusMeters,
				as: entry.center,
				requestedRadius: entry.radiusMeters
			)
		}
		entries.insert(entry, at: 0)
		if entries.count > maxEntries {
			entries.removeLast(entries.count - maxEntries)
		}
	}

	private func canReuse(
		_ entry: Entry,
		for coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) -> Bool {
		guard entry.options == options else {
			return false
		}
		guard Date().timeIntervalSince(entry.storedAt) <= timeToLive else {
			return false
		}
		return sameArea(
			center: entry.center,
			radiusMeters: entry.radiusMeters,
			as: coordinate,
			requestedRadius: radiusMeters
		)
	}

	private func canReuseStale(
		_ entry: Entry,
		for coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) -> Bool {
		guard entry.options == options else {
			return false
		}
		guard Date().timeIntervalSince(entry.storedAt) <= staleTimeToLive else {
			return false
		}
		return sameArea(
			center: entry.center,
			radiusMeters: max(entry.radiusMeters, radiusMeters),
			as: coordinate,
			requestedRadius: radiusMeters
		)
	}

	private func canReuse(
		_ request: InFlightRequest,
		for coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) -> Bool {
		guard request.options == options else {
			return false
		}
		return sameArea(
			center: request.center,
			radiusMeters: request.radiusMeters,
			as: coordinate,
			requestedRadius: radiusMeters
		)
	}

	private func sameArea(
		center: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		as coordinate: CLLocationCoordinate2D,
		requestedRadius: CLLocationDistance
	) -> Bool {
		let distanceFromCenter = distanceMeters(from: center, to: coordinate)
		let requestedAreaIsCovered = distanceFromCenter + requestedRadius <= radiusMeters
		let centersAreClose = distanceFromCenter <= reuseDistanceMeters
		return requestedAreaIsCovered || (abs(radiusMeters - requestedRadius) < 1 && centersAreClose)
	}

	private func distanceMeters(
		from start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> CLLocationDistance {
		CLLocation(latitude: start.latitude, longitude: start.longitude)
			.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
	}
}

struct OverpassResponse: Decodable {
	var elements: [OverpassElement]
}

struct OverpassElement: Decodable {
	var type: String
	var id: Int64
	var lat: Double?
	var lon: Double?
	var nodes: [Int64]?
	var tags: [String: String]?

	enum CodingKeys: String, CodingKey {
		case type
		case id
		case lat
		case lon
		case nodes
		case tags
	}

	init(
		type: String,
		id: Int64,
		lat: Double?,
		lon: Double?,
		nodes: [Int64]?,
		tags: [String: String]?
	) {
		self.type = type
		self.id = id
		self.lat = lat
		self.lon = lon
		self.nodes = nodes
		self.tags = tags
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		type = try container.decode(String.self, forKey: .type)
		id = try container.decode(Int64.self, forKey: .id)
		lat = try container.decodeIfPresent(Double.self, forKey: .lat)
		lon = try container.decodeIfPresent(Double.self, forKey: .lon)
		nodes = try container.decodeIfPresent([Int64].self, forKey: .nodes)
		tags = try container.decodeIfPresent([String: FlexibleString].self, forKey: .tags)?
			.mapValues(\.value)
	}
}

private struct FlexibleString: Decodable {
	var value: String

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let string = try? container.decode(String.self) {
			value = string
		} else if let int = try? container.decode(Int.self) {
			value = String(int)
		} else if let double = try? container.decode(Double.self) {
			value = String(double)
		} else if let bool = try? container.decode(Bool.self) {
			value = String(bool)
		} else {
			value = ""
		}
	}
}

private extension OverpassElement {
	var coordinate: CLLocationCoordinate2D? {
		guard let lat, let lon else {
			return nil
		}
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}
}

private extension MapRoad {
	func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
		minimumDistance(to: coordinate) <= 12
	}
}

struct IntersectionBuilder {
	func candidates(
		from response: OverpassResponse,
		options: MapDetailOptions = MapDetailOptions()
	) -> [IntersectionCandidate] {
		mapData(from: response, options: options).intersections
	}

	func mapData(
		from response: OverpassResponse,
		options: MapDetailOptions = MapDetailOptions()
	) -> MapDataSet {
		let nodes = Dictionary(
			uniqueKeysWithValues: response.elements.compactMap { element -> (Int64, CLLocationCoordinate2D)? in
				guard element.type == "node", let lat = element.lat, let lon = element.lon else {
					return nil
				}
				return (element.id, CLLocationCoordinate2D(latitude: lat, longitude: lon))
			}
		)
		let serviceRoadNodeIDs = serviceRoadNodeIDs(in: response)

		var namesByNode: [Int64: Set<String>] = [:]
		var roads = [MapRoad]()
		for way in response.elements where way.type == "way" {
			guard
				let name = way.tags?["name"],
				let wayNodes = way.nodes,
				isAllowedWay(way.tags, options: options)
			else {
				continue
			}
			for nodeID in wayNodes {
				namesByNode[nodeID, default: []].insert(name)
			}
			roads.append(
				MapRoad(
					id: String(way.id),
					name: name,
					nodeIDs: wayNodes,
					coordinates: wayNodes.compactMap { nodes[$0] }
				)
			)
		}

		var intersections = namesByNode.compactMap { entry -> IntersectionCandidate? in
			let (nodeID, names) = entry
			guard names.count >= 2, let coordinate = nodes[nodeID] else {
				return nil
			}
			return IntersectionCandidate(
				id: String(nodeID),
				names: names.sorted(),
				coordinate: coordinate
			)
		}

		if options.includeCrossings {
			let streetIntersections = intersections
			let crossingCandidates = response.elements.compactMap { element -> IntersectionCandidate? in
				guard
					element.type == "node",
					isCrossing(element.tags),
					!serviceRoadNodeIDs.contains(element.id),
					!isRoadJunctionCrossing(element.id, namesByNode: namesByNode),
					let coordinate = nodes[element.id],
					let road = crossingRoad(
						for: element.id,
						at: coordinate,
						namesByNode: namesByNode,
						roads: roads
					)
				else {
					return nil
				}

				guard isConfidentMidBlockCrossing(
					nodeID: element.id,
					at: coordinate,
					on: road,
					between: streetIntersections,
					roads: roads
				) else {
					return nil
				}
				let anchor = nearestIntersection(
					to: coordinate,
					on: road.name,
					in: streetIntersections
				)
				let title = crossingTitle(on: road.name, near: anchor)
				let candidate = IntersectionCandidate(
					id: "crossing-\(element.id)",
					names: [title],
					coordinate: coordinate,
					associatedRoadNames: [road.name],
					intersectionDetails: intersectionDetails(from: element.tags)
				)
				return candidate
			}
			intersections.append(contentsOf: crossingCandidates)
		}

		return MapDataSet(intersections: intersections, roads: roads)
	}

	func mapData(
		from crossingResponse: OverpassResponse,
		options: MapDetailOptions,
		coreData: MapDataSet
	) -> MapDataSet {
		guard options.includeCrossings else {
			return coreData
		}

		var intersections = coreData.intersections
		let streetIntersections = intersections.filter { !$0.id.hasPrefix("crossing-") }
		let serviceRoadNodeIDs = serviceRoadNodeIDs(in: crossingResponse)
		let crossingCandidates = crossingResponse.elements.compactMap { element -> IntersectionCandidate? in
			guard
				element.type == "node",
				isCrossing(element.tags),
				!serviceRoadNodeIDs.contains(element.id),
				let coordinate = element.coordinate,
				let road = coreData.roads.first(where: { $0.contains(coordinate) })
			else {
				return nil
			}

			guard isConfidentMidBlockCrossing(
				nodeID: element.id,
				at: coordinate,
				on: road,
				between: streetIntersections,
				roads: coreData.roads
			) else {
				return nil
			}
			let anchor = nearestIntersection(
				to: coordinate,
				on: road.name,
				in: streetIntersections
			)
			let title = crossingTitle(on: road.name, near: anchor)
			return IntersectionCandidate(
				id: "crossing-\(element.id)",
				names: [title],
				coordinate: coordinate,
				associatedRoadNames: [road.name],
				intersectionDetails: intersectionDetails(from: element.tags)
			)
		}

		let existingIDs = Set(intersections.map(\.id))
		intersections.append(contentsOf: crossingCandidates.filter { !existingIDs.contains($0.id) })
		return MapDataSet(intersections: intersections, roads: coreData.roads)
	}

	private func isRoadJunctionCrossing(
		_ nodeID: Int64,
		namesByNode: [Int64: Set<String>]
	) -> Bool {
		(namesByNode[nodeID]?.count ?? 0) >= 2
	}

	private func crossingRoad(
		for nodeID: Int64,
		at coordinate: CLLocationCoordinate2D,
		namesByNode: [Int64: Set<String>],
		roads: [MapRoad]
	) -> MapRoad? {
		if
			let roadNames = namesByNode[nodeID]?.sorted(),
			roadNames.count == 1,
			let roadName = roadNames.first,
			let road = roads.first(where: {
				$0.name == roadName && $0.nodeIDs.contains(nodeID)
			})
		{
			return road
		}
		return roads
			.filter { $0.contains(coordinate) }
			.min { $0.minimumDistance(to: coordinate) < $1.minimumDistance(to: coordinate) }
	}

	private func crossingTitle(
		on roadName: String,
		near anchor: IntersectionCandidate?
	) -> String {
		guard let anchor else {
			return "Crossing on \(roadName)"
		}
		return "Crossing on \(roadName) near \(anchor.contextLabel(on: roadName, minimal: true))"
	}

	private func isConfidentMidBlockCrossing(
		nodeID: Int64,
		at coordinate: CLLocationCoordinate2D,
		on road: MapRoad,
		between intersections: [IntersectionCandidate],
		roads: [MapRoad]
	) -> Bool {
		let minimumJunctionSeparation: CLLocationDistance = 35
		guard !intersections.contains(where: {
			Geo.distanceMeters(from: coordinate, to: $0.coordinate) < minimumJunctionSeparation
		}) else {
			return false
		}
		// Corners in real data are often fragmented: an avenue split into several
		// segments, or a street whose name changes across the junction, so a clean
		// shared junction node is not always detected. Treat the crossing as a
		// corner (not mid-block) if any other named street's roadway passes within
		// the junction-separation distance of it.
		guard !roads.contains(where: {
			$0.name != road.name &&
			$0.minimumDistance(to: coordinate) < minimumJunctionSeparation
		}) else {
			return false
		}
		let positions = intersections
			.filter { $0.roadNames.contains(road.name) }
			.compactMap {
				road.signedDistanceAlongRoad(from: coordinate, to: $0.coordinate)
			}
		guard !positions.contains(where: { abs($0) < minimumJunctionSeparation }) else {
			return false
		}
		if road.nodeIDs.contains(nodeID) {
			return true
		}
		return positions.contains(where: { $0 <= -minimumJunctionSeparation }) &&
			positions.contains(where: { $0 >= minimumJunctionSeparation })
	}

	private func serviceRoadNodeIDs(in response: OverpassResponse) -> Set<Int64> {
		Set(
			response.elements
				.filter { $0.type == "way" && $0.tags?["highway"] == "service" }
				.flatMap { $0.nodes ?? [] }
		)
	}

	private func nearestIntersection(
		to coordinate: CLLocationCoordinate2D,
		on roadName: String,
		in intersections: [IntersectionCandidate]
	) -> IntersectionCandidate? {
		intersections
			.filter { $0.roadNames.contains(roadName) }
			.compactMap { intersection -> (intersection: IntersectionCandidate, distance: CLLocationDistance)? in
				let distance = Geo.distanceMeters(from: coordinate, to: intersection.coordinate)
				guard distance <= 100 else {
					return nil
				}
				return (intersection, distance)
			}
			.min { $0.distance < $1.distance }?
			.intersection
	}

	private func isAllowedWay(_ tags: [String: String]?, options: MapDetailOptions) -> Bool {
		guard let highway = tags?["highway"] else {
			return false
		}
		let streetHighways = [
			"primary",
			"primary_link",
			"secondary",
			"secondary_link",
			"tertiary",
			"tertiary_link",
			"unclassified",
			"residential",
			"living_street",
			"pedestrian",
			"road"
		]
		if streetHighways.contains(highway) {
			return true
		}

		guard options.includeWalkingPaths else {
			return false
		}

		return [
			"footway",
			"path",
			"steps",
			"bridleway"
		].contains(highway)
	}

	private func isCrossing(_ tags: [String: String]?) -> Bool {
		tags?["highway"] == "crossing" || tags?["crossing"] != nil || tags?["crossing_ref"] != nil
	}

	private func intersectionDetails(from tags: [String: String]?) -> IntersectionDetails? {
		guard let tags else {
			return nil
		}
		let crossing = tags["crossing"]?.lowercased()
		let details = IntersectionDetails(
			isSignalized: crossing == "traffic_signals" || isPositive(tags["crossing:signals"]),
			hasPedestrianIsland: crossing == "island" || isPositive(tags["crossing:island"])
		)
		return details.isEmpty ? nil : details
	}

	private func isPositive(_ value: String?) -> Bool {
		guard let value = value?.lowercased() else {
			return false
		}
		return ["yes", "true", "1"].contains(value)
	}
}
