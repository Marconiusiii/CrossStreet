//
//  OrientationReport.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import Foundation
import CoreLocation

struct OrientReport: Equatable {
	var kind: ReportKind
	var cross: String
	var dist: String
	var relDir: String?
	var relDegrees: CLLocationDirection?
	var street: String?
	var crossStreet: String? = nil
	var head: String?
	var area: String?
	var toward: String?
	var conf: ConfLev
	var intersectionDetails: IntersectionDetails? = nil

	func text(with prefs: AppPrefs) -> String {
		text(with: prefs, includeLead: true)
	}

	func text(with prefs: AppPrefs, rank: Int) -> String {
		guard rank > 1 else {
			return text(with: prefs)
		}

		return text(with: prefs, includeLead: true, rank: rank)
	}

	func text(with prefs: AppPrefs, includeLead: Bool) -> String {
		text(with: prefs, includeLead: includeLead, rank: nil)
	}

	func neighborhoodText(with prefs: AppPrefs) -> String? {
		areaText(prefs)
	}

	func text(
		with prefs: AppPrefs,
		includeLead: Bool,
		includeNeighborhood: Bool
	) -> String {
		text(
			with: prefs,
			includeLead: includeLead,
			rank: nil,
			includeNeighborhood: includeNeighborhood
		)
	}

	private func text(with prefs: AppPrefs, includeLead: Bool, rank: Int?) -> String {
		text(
			with: prefs,
			includeLead: includeLead,
			rank: rank,
			includeNeighborhood: true
		)
	}

	private func text(
		with prefs: AppPrefs,
		includeLead: Bool,
		rank: Int?,
		includeNeighborhood: Bool
	) -> String {
		var text: String
		if prefs.announcementOptions.speaksIntersectionNamesOnly {
			text = nameOnlyText()
		} else if
			prefs.intersectionWording == .streetContext,
			let street,
			let crossStreet
		{
			text = streetContextText(street: street, crossStreet: crossStreet, prefs: prefs)
		} else {
			text = directText(with: prefs)
		}
		if includeLead {
			text = "\(leadText(rank: rank)): \(text)"
		}
		if includeNeighborhood, let area = areaText(prefs) {
			text += " \(area)"
		}
		text += "."
		return text
	}

	private func nameOnlyText() -> String {
		guard let street, let crossStreet else {
			return cross
		}
		return "\(street) and \(crossStreet)"
	}

	private func leadText(rank: Int? = nil) -> String {
		if let rank, rank > 1 {
			return "\(Self.ordinal(rank)) \(baseLeadText)"
		}
		return baseLeadText
	}

	private var baseLeadText: String {
		switch kind {
		case .nearest:
			"Nearest"
		case .upcoming:
			"Upcoming"
		case .scan:
			"Pointed"
		}
	}

	private static func ordinal(_ value: Int) -> String {
		switch value {
		case 2:
			"2nd"
		case 3:
			"3rd"
		default:
			"\(value)th"
		}
	}

	private func directText(with prefs: AppPrefs) -> String {
		var text = cross
		let details = reportDetails(with: prefs)
		if !details.isEmpty {
			text += ", \(details.joined(separator: ", "))"
		}
		return text
	}

	private func streetContextText(
		street: String,
		crossStreet: String,
		prefs: AppPrefs
	) -> String {
		let details = reportDetails(with: prefs)
		guard !details.isEmpty else {
			return "On \(street) at \(crossStreet)"
		}
		return "On \(street) at \(crossStreet), \(details.joined(separator: ", "))"
	}

	private func reportDetails(with prefs: AppPrefs) -> [String] {
		var details: [String] = []
		var travelDetails: [String] = []
		if prefs.announcementOptions.includeDistance {
			travelDetails.append("about \(dist)")
		}
		if
			prefs.announcementOptions.includeDirection,
			let direction = directionText(with: prefs)
		{
			travelDetails.append(direction)
		}
		if !travelDetails.isEmpty {
			details.append(travelDetails.joined(separator: " "))
		}
		if prefs.announcementOptions.includeIntersectionDetails, let intersectionDetails {
			details.append(contentsOf: intersectionDetails.spokenPhrases)
		}
		return details
	}

	private func areaText(_ prefs: AppPrefs) -> String? {
		guard prefs.announcementOptions.includeNeighborhood else {
			return nil
		}

		return switch prefs.areaMode {
		case .off:
			nil
		case .near:
			area.map { "in \($0)" }
		case .toward:
			if let toward {
				"toward \(toward)"
			} else {
				area.map { "in \($0)" }
			}
		}
	}

	private func directionText(with prefs: AppPrefs) -> String? {
		switch prefs.directionStyle {
		case .words:
			return relDir
		case .cardinal:
			guard let head else {
				return nil
			}
			if prefs.manhattanSnobMode {
				return "toward \(Geo.manhattanDirection(for: head))"
			}
			return head
		case .clockFace:
			return relDegrees.map { Self.clockFaceDirection(from: $0) }
		}
	}

	private static func clockFaceDirection(from degrees: CLLocationDirection) -> String {
		let hour = Int((Geo.normalizedDegrees(degrees) + 15) / 30) % 12
		return "at \(hour == 0 ? 12 : hour) o'clock"
	}
}

struct IntersectionReportList: Equatable {
	var reports: [OrientReport]

	func text(with prefs: AppPrefs) -> String {
		guard let first = reports.first else {
			return ""
		}
		if prefs.announcementOptions.speaksIntersectionNamesOnly {
			let sharedStreet = first.street.flatMap { streetName in
				reports.allSatisfy { $0.street == streetName && $0.crossStreet != nil }
					? streetName
					: nil
			}
			let labels: [String]
			if let sharedStreet {
				labels = reports.enumerated().map { index, report in
					guard let crossStreet = report.crossStreet else {
						return report.cross
					}
					return index == 0 ? "\(sharedStreet) and \(crossStreet)" : crossStreet
				}
			} else {
				labels = reports.map(\.cross)
			}
			return labels.joined(separator: ", ") + "."
		}

		let sharedNeighborhood = sharedNeighborhoodText(with: prefs)
		let text = reports.enumerated().map { index, report in
			report.text(
				with: prefs,
				includeLead: index == 0,
				includeNeighborhood: sharedNeighborhood == nil
			)
		}.joined(separator: " ")
		guard let sharedNeighborhood else {
			return text
		}
		return text.dropTrailingPeriod() + " \(sharedNeighborhood)."
	}

	private func sharedNeighborhoodText(with prefs: AppPrefs) -> String? {
		guard reports.count > 1, prefs.announcementOptions.includeNeighborhood else {
			return nil
		}
		let neighborhoodTexts = reports.map { $0.neighborhoodText(with: prefs) }
		guard
			let first = neighborhoodTexts.first,
			let shared = first,
			neighborhoodTexts.allSatisfy({ $0 == shared })
		else {
			return nil
		}
		return shared
	}
}

private extension String {
	func dropTrailingPeriod() -> String {
		hasSuffix(".") ? String(dropLast()) : self
	}
}

private extension AnnouncementOptions {
	var speaksIntersectionNamesOnly: Bool {
		!includeDistance && !includeDirection && !includeNeighborhood && !includeIntersectionDetails
	}
}

enum ReportKind {
	case nearest
	case upcoming
	case scan

	var intentLabel: String {
		switch self {
		case .nearest:
			"nearest intersection"
		case .upcoming:
			"upcoming intersection"
		case .scan:
			"pointed intersection"
		}
	}
}

enum ConfLev {
	case high
	case medium
	case low
}

struct DeviceContext: Equatable {
	var coordinate: CLLocationCoordinate2D
	var headingDegrees: CLLocationDirection?
	var courseDegrees: CLLocationDirection? = nil
	var courseAccuracy: CLLocationDirection? = nil
	var speedMetersPerSecond: CLLocationSpeed? = nil
	var horizontalAccuracy: CLLocationAccuracy? = nil

	var dependableTravelDirection: CLLocationDirection? {
		if
			let courseDegrees,
			let courseAccuracy,
			let speedMetersPerSecond,
			courseDegrees >= 0,
			courseAccuracy >= 0,
			courseAccuracy <= 45,
			speedMetersPerSecond >= 0.7
		{
			return courseDegrees
		}
		return headingDegrees
	}
}

struct IntersectionCandidate: Equatable, Identifiable {
	var id: String
	var names: [String]
	var coordinate: CLLocationCoordinate2D
	var associatedRoadNames: [String] = []
	var intersectionDetails: IntersectionDetails?

	var title: String {
		names.prefix(2).joined(separator: " and ")
	}

	var roadNames: [String] {
		associatedRoadNames.isEmpty ? names : associatedRoadNames
	}

	func contextLabel(on streetName: String, minimal: Bool) -> String {
		if id.hasPrefix("crossing-") {
			return minimal ? "mapped crossing" : "a mapped crossing"
		}
		let otherNames = names.filter { $0 != streetName }
		return otherNames.isEmpty ? title : otherNames.joined(separator: " and ")
	}
}

struct IntersectionDetails: Equatable, Hashable, Sendable {
	var isSignalized = false
	var hasPedestrianIsland = false

	var spokenPhrases: [String] {
		var phrases: [String] = []
		if isSignalized {
			phrases.append("signalized crossing")
		}
		if hasPedestrianIsland {
			phrases.append("pedestrian island")
		}
		return phrases
	}

	var isEmpty: Bool {
		spokenPhrases.isEmpty
	}
}

struct StreetPositionContext: Equatable {
	var streetName: String
	var boundaries: [IntersectionCandidate]
	var following: IntersectionCandidate?
	var isOnStreet: Bool

	func text(with prefs: AppPrefs) -> String {
		if prefs.announcementOptions.speaksIntersectionNamesOnly {
			let candidates = boundaries + [following].compactMap { $0 }
			let allShareStreet = candidates.allSatisfy { $0.names.contains(streetName) }
			let labels: [String]
			if allShareStreet, let first = candidates.first {
				labels = [first.title] + candidates.dropFirst().map {
					$0.contextLabel(on: streetName, minimal: true)
				}
			} else {
				labels = candidates.map(\.title)
			}
			return labels.joined(separator: ", ") + "."
		}

		guard boundaries.count == 2 else {
			return ""
		}
		let prefix = isOnStreet ? "On" : "Along"
		let first = boundaries[0].contextLabel(on: streetName, minimal: false)
		let second = boundaries[1].contextLabel(on: streetName, minimal: false)
		var text = "\(prefix) \(streetName) between \(first) and \(second)"
		if let following {
			text += ", toward \(following.contextLabel(on: streetName, minimal: false))"
		}
		return text + "."
	}
}

struct MapRoad: Equatable, Identifiable {
	var id: String
	var name: String
	var nodeIDs: [Int64]
	var coordinates: [CLLocationCoordinate2D]
}

private struct RoadGraphEdge {
	var nodeID: Int64
	var distance: CLLocationDistance
}

private struct RoadStartSegment {
	var startNodeID: Int64
	var endNodeID: Int64
	var length: CLLocationDistance
	var projection: Double
	var distance: CLLocationDistance
	var tangentX: Double
	var tangentY: Double
}

struct MapDataSet: Equatable {
	var intersections: [IntersectionCandidate]
	var roads: [MapRoad]

	func merging(_ other: MapDataSet) -> MapDataSet {
		var mergedIntersections = intersections
		let existingIntersectionIDs = Set(mergedIntersections.map(\.id))
		mergedIntersections.append(contentsOf: other.intersections.filter { !existingIntersectionIDs.contains($0.id) })

		var mergedRoads = roads
		let existingRoadIDs = Set(mergedRoads.map(\.id))
		mergedRoads.append(contentsOf: other.roads.filter { !existingRoadIDs.contains($0.id) })

		return MapDataSet(intersections: mergedIntersections, roads: mergedRoads)
	}

	func currentStreetIntersections(from coordinate: CLLocationCoordinate2D) -> [IntersectionCandidate] {
		currentStreetScanTargets(from: coordinate, includeCrossings: false)
	}

	func currentRoadName(from context: DeviceContext) -> String? {
		currentRoad(from: context)?.name
	}

	func currentStreetScanTargets(
		from coordinate: CLLocationCoordinate2D,
		includeCrossings: Bool
	) -> [IntersectionCandidate] {
		guard let road = nearestRoad(to: coordinate) else {
			return []
		}
		return intersections
			.filter {
				if $0.id.hasPrefix("crossing-") {
					return includeCrossings && $0.roadNames.contains(road.name)
				}
				return $0.roadNames.contains(road.name)
			}
			.sorted {
				Geo.distanceMeters(from: coordinate, to: $0.coordinate)
					< Geo.distanceMeters(from: coordinate, to: $1.coordinate)
			}
	}

	func upcomingRoadSequence(from context: DeviceContext) -> [IntersectionCandidate]? {
		guard
			let heading = context.headingDegrees,
			let road = currentRoad(from: context)
		else {
			return nil
		}

		let matchingRoads = roads.filter { $0.name == road.name }
		let graph = roadGraph(from: matchingRoads)
		guard
			let start = nearestRoadSegment(to: context.coordinate, in: matchingRoads),
			start.distance <= currentRoadDistanceThreshold(for: context)
		else {
			return nil
		}

		let radians = heading * Double.pi / 180
		let headingX = sin(radians)
		let headingY = cos(radians)
		let alignment = headingX * start.tangentX + headingY * start.tangentY
		guard abs(alignment) >= 0.35 else {
			return nil
		}

		let forwardNodeID = alignment >= 0 ? start.endNodeID : start.startNodeID
		let backwardNodeID = alignment >= 0 ? start.startNodeID : start.endNodeID
		let distanceToForwardNode = alignment >= 0
			? start.length * (1 - start.projection)
			: start.length * start.projection
		let routeDistances = roadDistances(
			from: forwardNodeID,
			initialDistance: distanceToForwardNode,
			blockedFirstNode: backwardNodeID,
			adjacency: graph.adjacency,
			coordinates: graph.coordinates
		)

		let positioned = intersections
			.filter { $0.roadNames.contains(road.name) }
			.compactMap { candidate -> (candidate: IntersectionCandidate, progress: CLLocationDistance)? in
				guard
					let progress = routeProgress(
						to: candidate.coordinate,
						start: start,
						alignment: alignment,
						coordinates: graph.coordinates,
						adjacency: graph.adjacency,
						distances: routeDistances
					),
					progress > 3
				else {
					return nil
				}
				return (candidate, progress)
			}
			.sorted { lhs, rhs in
				if abs(lhs.progress - rhs.progress) > 1 {
					return lhs.progress < rhs.progress
				}
				return Geo.distanceMeters(from: context.coordinate, to: lhs.candidate.coordinate)
					< Geo.distanceMeters(from: context.coordinate, to: rhs.candidate.coordinate)
			}

		return positioned.isEmpty ? nil : positioned.map(\.candidate)
	}

	func streetPosition(
		from context: DeviceContext,
		count: SpokenIntersectionCount
	) -> StreetPositionContext? {
		guard count != .one, let road = nearestRoad(to: context.coordinate) else {
			return nil
		}
		let candidates = IntersectionFinder().rankedNearest(
			from: context.coordinate,
			in: intersections.filter { $0.roadNames.contains(road.name) }
		)
		let positioned = candidates.compactMap { candidate -> (IntersectionCandidate, Double)? in
			guard let distance = road.signedDistanceAlongRoad(
				from: context.coordinate,
				to: candidate.coordinate
			) else {
				return nil
			}
			return (candidate, distance)
		}
		let negative = positioned.filter { $0.1 < -3 }.sorted { abs($0.1) < abs($1.1) }
		let positive = positioned.filter { $0.1 > 3 }.sorted { abs($0.1) < abs($1.1) }
		guard let negativeBoundary = negative.first, let positiveBoundary = positive.first else {
			return nil
		}

		var following: IntersectionCandidate?
		if
			count == .three,
			let direction = context.dependableTravelDirection,
			let directionSign = road.directionSign(for: direction, at: context.coordinate)
		{
			let forward = directionSign >= 0 ? positive : negative
			following = forward.dropFirst().first?.0
		}

		let roadDistance = road.minimumDistance(to: context.coordinate)
		let accuracy = context.horizontalAccuracy ?? 25
		let onStreetThreshold = max(20, min(accuracy, 50))
		return StreetPositionContext(
			streetName: road.name,
			boundaries: [negativeBoundary.0, positiveBoundary.0],
			following: following,
			isOnStreet: roadDistance <= onStreetThreshold
		)
	}

	func nearestRoadName(
		to coordinate: CLLocationCoordinate2D,
		matching roadNames: [String]
	) -> String? {
		let allowedNames = Set(roadNames)
		return roads
			.filter { allowedNames.contains($0.name) }
			.min {
				$0.minimumDistance(to: coordinate) < $1.minimumDistance(to: coordinate)
			}?
			.name
	}

	func crossStreetNames(
		for match: IntersectionCandidate,
		on roadName: String,
		heading: CLLocationDirection?
	) -> [String] {
		guard !match.id.hasPrefix("crossing-") else {
			return []
		}
		let candidates = splitIntersectionCandidates(for: match, on: roadName)
		let orderedCandidates = orderedSplitCandidates(
			candidates,
			roadName: roadName,
			heading: heading
		)
		return orderedCandidates.reduce(into: []) { names, candidate in
			for name in candidate.names where name != roadName && !names.contains(name) {
				names.append(name)
			}
		}
	}

	private func nearestRoad(to coordinate: CLLocationCoordinate2D) -> MapRoad? {
		roads.min {
			$0.minimumDistance(to: coordinate) < $1.minimumDistance(to: coordinate)
		}
	}

	private func currentRoad(from context: DeviceContext) -> MapRoad? {
		guard let heading = context.headingDegrees else {
			return nil
		}
		let threshold = currentRoadDistanceThreshold(for: context)
		return roads
			.compactMap { road -> (road: MapRoad, score: Double)? in
				let distance = road.minimumDistance(to: context.coordinate)
				guard
					distance <= threshold,
					let directionSign = road.directionSign(for: heading, at: context.coordinate),
					abs(directionSign) >= 0.35
				else {
					return nil
				}
				let alignmentPenalty = (1 - abs(directionSign)) * 40
				return (road, distance + alignmentPenalty)
			}
			.min { $0.score < $1.score }?
			.road
	}

	private func currentRoadDistanceThreshold(for context: DeviceContext) -> CLLocationDistance {
		let accuracy = context.horizontalAccuracy ?? 25
		return max(25, min(accuracy + 10, 60))
	}

	private func roadGraph(
		from roads: [MapRoad]
	) -> (adjacency: [Int64: [RoadGraphEdge]], coordinates: [Int64: CLLocationCoordinate2D]) {
		var adjacency: [Int64: [RoadGraphEdge]] = [:]
		var coordinates: [Int64: CLLocationCoordinate2D] = [:]
		for road in roads where road.nodeIDs.count == road.coordinates.count && road.nodeIDs.count > 1 {
			for (nodeID, coordinate) in zip(road.nodeIDs, road.coordinates) {
				coordinates[nodeID] = coordinate
			}
			for index in 0..<(road.nodeIDs.count - 1) {
				let startNodeID = road.nodeIDs[index]
				let endNodeID = road.nodeIDs[index + 1]
				let distance = Geo.distanceMeters(
					from: road.coordinates[index],
					to: road.coordinates[index + 1]
				)
				guard distance > 0 else {
					continue
				}
				adjacency[startNodeID, default: []].append(
					RoadGraphEdge(nodeID: endNodeID, distance: distance)
				)
				adjacency[endNodeID, default: []].append(
					RoadGraphEdge(nodeID: startNodeID, distance: distance)
				)
			}
		}
		return (adjacency, coordinates)
	}

	private func nearestRoadSegment(
		to coordinate: CLLocationCoordinate2D,
		in roads: [MapRoad]
	) -> RoadStartSegment? {
		roads
			.filter { $0.nodeIDs.count == $0.coordinates.count && $0.nodeIDs.count > 1 }
			.flatMap { road in
				(0..<(road.nodeIDs.count - 1)).compactMap { index in
					roadSegment(
						from: coordinate,
						startNodeID: road.nodeIDs[index],
						start: road.coordinates[index],
						endNodeID: road.nodeIDs[index + 1],
						end: road.coordinates[index + 1]
					)
				}
			}
			.min { $0.distance < $1.distance }
	}

	private func roadSegment(
		from origin: CLLocationCoordinate2D,
		startNodeID: Int64,
		start: CLLocationCoordinate2D,
		endNodeID: Int64,
		end: CLLocationCoordinate2D
	) -> RoadStartSegment? {
		let earthRadius = 6_371_000.0
		let latitudeScale = Double.pi / 180
		let longitudeScale = latitudeScale * cos(origin.latitude * latitudeScale)
		let startX = (start.longitude - origin.longitude) * longitudeScale * earthRadius
		let startY = (start.latitude - origin.latitude) * latitudeScale * earthRadius
		let endX = (end.longitude - origin.longitude) * longitudeScale * earthRadius
		let endY = (end.latitude - origin.latitude) * latitudeScale * earthRadius
		let segmentX = endX - startX
		let segmentY = endY - startY
		let length = hypot(segmentX, segmentY)
		guard length > 0 else {
			return nil
		}
		let projection = min(1, max(0, -(startX * segmentX + startY * segmentY) / (length * length)))
		let closestX = startX + projection * segmentX
		let closestY = startY + projection * segmentY
		return RoadStartSegment(
			startNodeID: startNodeID,
			endNodeID: endNodeID,
			length: length,
			projection: projection,
			distance: hypot(closestX, closestY),
			tangentX: segmentX / length,
			tangentY: segmentY / length
		)
	}

	private func roadDistances(
		from startNodeID: Int64,
		initialDistance: CLLocationDistance,
		blockedFirstNode: Int64,
		adjacency: [Int64: [RoadGraphEdge]],
		coordinates: [Int64: CLLocationCoordinate2D]
	) -> [Int64: CLLocationDistance] {
		var distances = [startNodeID: initialDistance]
		var visited: Set<Int64> = [blockedFirstNode, startNodeID]
		var previousNodeID = blockedFirstNode
		var currentNodeID = startNodeID
		var currentDistance = initialDistance

		while
			let previousCoordinate = coordinates[previousNodeID],
			let currentCoordinate = coordinates[currentNodeID]
		{
			let nextEdge = adjacency[currentNodeID, default: []]
				.filter { !visited.contains($0.nodeID) && coordinates[$0.nodeID] != nil }
				.max { lhs, rhs in
					let lhsAlignment = continuationAlignment(
						previous: previousCoordinate,
						current: currentCoordinate,
						next: coordinates[lhs.nodeID]!
					)
					let rhsAlignment = continuationAlignment(
						previous: previousCoordinate,
						current: currentCoordinate,
						next: coordinates[rhs.nodeID]!
					)
					if abs(lhsAlignment - rhsAlignment) > 0.001 {
						return lhsAlignment < rhsAlignment
					}
					return lhs.nodeID > rhs.nodeID
				}
			guard let nextEdge else {
				break
			}

			currentDistance += nextEdge.distance
			distances[nextEdge.nodeID] = currentDistance
			previousNodeID = currentNodeID
			currentNodeID = nextEdge.nodeID
			visited.insert(currentNodeID)
		}
		return distances
	}

	private func continuationAlignment(
		previous: CLLocationCoordinate2D,
		current: CLLocationCoordinate2D,
		next: CLLocationCoordinate2D
	) -> Double {
		let latitudeScale = Double.pi / 180
		let longitudeScale = latitudeScale * cos(current.latitude * latitudeScale)
		let incomingX = (current.longitude - previous.longitude) * longitudeScale
		let incomingY = (current.latitude - previous.latitude) * latitudeScale
		let outgoingX = (next.longitude - current.longitude) * longitudeScale
		let outgoingY = (next.latitude - current.latitude) * latitudeScale
		let incomingLength = hypot(incomingX, incomingY)
		let outgoingLength = hypot(outgoingX, outgoingY)
		guard incomingLength > 0, outgoingLength > 0 else {
			return -1
		}
		return (incomingX * outgoingX + incomingY * outgoingY) / (incomingLength * outgoingLength)
	}

	private func routeProgress(
		to coordinate: CLLocationCoordinate2D,
		start: RoadStartSegment,
		alignment: Double,
		coordinates: [Int64: CLLocationCoordinate2D],
		adjacency: [Int64: [RoadGraphEdge]],
		distances: [Int64: CLLocationDistance]
	) -> CLLocationDistance? {
		if
			let startCoordinate = coordinates[start.startNodeID],
			let endCoordinate = coordinates[start.endNodeID],
			let candidateSegment = roadSegment(
				from: coordinate,
				startNodeID: start.startNodeID,
				start: startCoordinate,
				endNodeID: start.endNodeID,
				end: endCoordinate
			),
			candidateSegment.distance <= 15
		{
			let progress = alignment >= 0
				? (candidateSegment.projection - start.projection) * start.length
				: (start.projection - candidateSegment.projection) * start.length
			return progress > 0 ? progress : nil
		}

		var best: CLLocationDistance?
		for (startNodeID, edges) in adjacency {
			guard let startCoordinate = coordinates[startNodeID] else {
				continue
			}
			for edge in edges where startNodeID < edge.nodeID {
				guard
					let endCoordinate = coordinates[edge.nodeID],
					let projection = roadSegment(
						from: coordinate,
						startNodeID: startNodeID,
						start: startCoordinate,
						endNodeID: edge.nodeID,
						end: endCoordinate
					),
					projection.distance <= 15
				else {
					continue
				}
				guard
					let startDistance = distances[startNodeID],
					let endDistance = distances[edge.nodeID],
					abs(abs(endDistance - startDistance) - projection.length) <= max(1, projection.length * 0.01)
				else {
					continue
				}
				let value = startDistance < endDistance
					? startDistance + projection.projection * projection.length
					: endDistance + (1 - projection.projection) * projection.length
				if value > 0, best == nil || value < best! {
					best = value
				}
			}
		}
		return best
	}

	private func splitIntersectionCandidates(
		for match: IntersectionCandidate,
		on roadName: String
	) -> [IntersectionCandidate] {
		let sameStreetCandidates = intersections.filter {
			!$0.id.hasPrefix("crossing-") && $0.roadNames.contains(roadName)
		}
		let nearbyCandidates = sameStreetCandidates.filter { candidate in
			candidate.id == match.id || isSameSplitIntersection(candidate, as: match, on: roadName)
		}
		return nearbyCandidates.isEmpty ? [match] : nearbyCandidates
	}

	private func isSameSplitIntersection(
		_ candidate: IntersectionCandidate,
		as match: IntersectionCandidate,
		on roadName: String
	) -> Bool {
		guard candidate.id != match.id else {
			return true
		}
		let straightLineDistance = Geo.distanceMeters(from: candidate.coordinate, to: match.coordinate)
		guard straightLineDistance <= 45 else {
			return false
		}
		guard
			let road = roads.first(where: { $0.name == roadName }),
			let candidatePosition = road.signedDistanceAlongRoad(
				from: match.coordinate,
				to: candidate.coordinate
			)
		else {
			return straightLineDistance <= 30
		}
		return abs(candidatePosition) <= 30
	}

	private func orderedSplitCandidates(
		_ candidates: [IntersectionCandidate],
		roadName: String,
		heading: CLLocationDirection?
	) -> [IntersectionCandidate] {
		guard let heading else {
			return candidates.sorted {
				Geo.distanceMeters(from: candidates[0].coordinate, to: $0.coordinate)
					< Geo.distanceMeters(from: candidates[0].coordinate, to: $1.coordinate)
			}
		}
		return candidates.enumerated().sorted { lhs, rhs in
			let lhsSide = sideScore(for: lhs.element, roadName: roadName, heading: heading)
			let rhsSide = sideScore(for: rhs.element, roadName: roadName, heading: heading)
			if lhsSide != rhsSide {
				return lhsSide > rhsSide
			}
			return lhs.offset < rhs.offset
		}.map(\.element)
	}

	private func sideScore(
		for candidate: IntersectionCandidate,
		roadName: String,
		heading: CLLocationDirection
	) -> Double {
		let vectors = candidate.names
			.filter { $0 != roadName }
			.compactMap { crossStreetVector(for: $0, from: candidate.coordinate) }
		guard let vector = vectors.first else {
			return 0
		}
		let radians = heading * Double.pi / 180
		let headingX = sin(radians)
		let headingY = cos(radians)
		return headingX * vector.y - headingY * vector.x
	}

	private func crossStreetVector(
		for roadName: String,
		from coordinate: CLLocationCoordinate2D
	) -> (x: Double, y: Double)? {
		roads
			.filter { $0.name == roadName }
			.compactMap { road -> (distance: CLLocationDistance, vector: (x: Double, y: Double))? in
				guard let vector = road.vectorAway(from: coordinate) else {
					return nil
				}
				return (road.minimumDistance(to: coordinate), vector)
			}
			.min { $0.distance < $1.distance }?
			.vector
	}
}

extension MapRoad {
	func minimumDistance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
		guard coordinates.count > 1 else {
			return coordinates.first.map {
				Geo.distanceMeters(from: coordinate, to: $0)
			} ?? .greatestFiniteMagnitude
		}

		return zip(coordinates, coordinates.dropFirst())
			.map { start, end in
				Self.distance(
					from: coordinate,
					toSegmentFrom: start,
					to: end
				)
			}
			.min() ?? .greatestFiniteMagnitude
	}

	func signedDistanceAlongRoad(
		from origin: CLLocationCoordinate2D,
		to target: CLLocationCoordinate2D
	) -> CLLocationDistance? {
		guard let reference = nearestSegmentReference(to: origin) else {
			return nil
		}
		let targetVector = Self.localVector(from: origin, to: target)
		return targetVector.x * reference.tangentX + targetVector.y * reference.tangentY
	}

	func directionSign(
		for heading: CLLocationDirection,
		at coordinate: CLLocationCoordinate2D
	) -> Double? {
		guard let reference = nearestSegmentReference(to: coordinate) else {
			return nil
		}
		let radians = heading * Double.pi / 180
		let headingX = sin(radians)
		let headingY = cos(radians)
		return headingX * reference.tangentX + headingY * reference.tangentY
	}

	private func nearestSegmentReference(to coordinate: CLLocationCoordinate2D) -> SegmentReference? {
		zip(coordinates, coordinates.dropFirst())
			.compactMap { start, end in
				Self.segmentReference(from: coordinate, start: start, end: end)
			}
			.min { $0.distance < $1.distance }
	}

	private struct SegmentReference {
		var distance: CLLocationDistance
		var tangentX: Double
		var tangentY: Double
	}

	private static func segmentReference(
		from coordinate: CLLocationCoordinate2D,
		start: CLLocationCoordinate2D,
		end: CLLocationCoordinate2D
	) -> SegmentReference? {
		let startVector = localVector(from: coordinate, to: start)
		let endVector = localVector(from: coordinate, to: end)
		let segmentX = endVector.x - startVector.x
		let segmentY = endVector.y - startVector.y
		let segmentLength = hypot(segmentX, segmentY)
		guard segmentLength > 0 else {
			return nil
		}
		let segmentLengthSquared = segmentLength * segmentLength
		let projection = -(startVector.x * segmentX + startVector.y * segmentY) / segmentLengthSquared
		let clampedProjection = min(1, max(0, projection))
		let closestX = startVector.x + clampedProjection * segmentX
		let closestY = startVector.y + clampedProjection * segmentY
		return SegmentReference(
			distance: hypot(closestX, closestY),
			tangentX: segmentX / segmentLength,
			tangentY: segmentY / segmentLength
		)
	}

	private static func localVector(
		from origin: CLLocationCoordinate2D,
		to target: CLLocationCoordinate2D
	) -> (x: Double, y: Double) {
		let earthRadius = 6_371_000.0
		let latitudeScale = Double.pi / 180
		let longitudeScale = latitudeScale * cos(origin.latitude * latitudeScale)
		return (
			(target.longitude - origin.longitude) * longitudeScale * earthRadius,
			(target.latitude - origin.latitude) * latitudeScale * earthRadius
		)
	}

	func vectorAway(from coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double)? {
		coordinates
			.map { Self.localVector(from: coordinate, to: $0) }
			.filter { hypot($0.x, $0.y) > 1 }
			.min { hypot($0.x, $0.y) < hypot($1.x, $1.y) }
	}

	private static func distance(
		from coordinate: CLLocationCoordinate2D,
		toSegmentFrom start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> CLLocationDistance {
		let earthRadius = 6_371_000.0
		let latitudeScale = Double.pi / 180
		let longitudeScale = latitudeScale * cos(coordinate.latitude * latitudeScale)
		let startX = (start.longitude - coordinate.longitude) * longitudeScale * earthRadius
		let startY = (start.latitude - coordinate.latitude) * latitudeScale * earthRadius
		let endX = (end.longitude - coordinate.longitude) * longitudeScale * earthRadius
		let endY = (end.latitude - coordinate.latitude) * latitudeScale * earthRadius
		let segmentX = endX - startX
		let segmentY = endY - startY
		let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY

		guard segmentLengthSquared > 0 else {
			return hypot(startX, startY)
		}

		let projection = -(startX * segmentX + startY * segmentY) / segmentLengthSquared
		let clampedProjection = min(1, max(0, projection))
		let closestX = startX + clampedProjection * segmentX
		let closestY = startY + clampedProjection * segmentY
		return hypot(closestX, closestY)
	}
}

extension CLLocationCoordinate2D: @retroactive Equatable {
	public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
		lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
	}
}
