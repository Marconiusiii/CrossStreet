//
//  OrientSvc.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import CoreLocation
import Foundation

enum OrientError: LocalizedError {
	case noIntersections
	case headingUnavailable
	case locationUnavailable

	var errorDescription: String? {
		switch self {
		case .noIntersections:
			"No nearby mapped intersections were found."
		case .headingUnavailable:
			"Direction is not available yet."
		case .locationUnavailable:
			"Location is not available yet. Try again."
		}
	}
}

protocol LocationProviding {
	func currentContext() async throws -> DeviceContext
	func currentContext(requiresFreshHeading: Bool) async throws -> DeviceContext
	func prewarmContext(timeout: TimeInterval) async -> Bool
}

extension LocationProviding {
	func currentContext(requiresFreshHeading: Bool) async throws -> DeviceContext {
		try await currentContext()
	}

	func prewarmContext(timeout: TimeInterval) async -> Bool {
		false
	}
}

protocol MapDataFetching {
	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate]
	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet
	func freshMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet
	func immediateMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet
	func roadMapData(
		near coordinate: CLLocationCoordinate2D,
		roadName: String,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet
}

extension MapDataFetching {
	func freshMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		)
	}

	func immediateMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		)
	}

	func roadMapData(
		near coordinate: CLLocationCoordinate2D,
		roadName: String,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		)
	}
}

protocol NeighborhoodProviding {
	func neighborhoods(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) async throws -> [NeighborhoodCandidate]
}

struct OrientSvc {
	var locationProvider: LocationProviding
	var mapDataClient: MapDataFetching
	var neighborhoodProvider: NeighborhoodProviding
	var finder = IntersectionFinder()
	var neighborhoodResolver = NeighborhoodResolver()
	private var upcomingCache = UpcomingReportCache()
	private static let spokenExpansionTimeout: Duration = .seconds(8)

	init(
		locationProvider: LocationProviding,
		mapDataClient: MapDataFetching,
		neighborhoodProvider: NeighborhoodProviding,
		finder: IntersectionFinder = IntersectionFinder(),
		neighborhoodResolver: NeighborhoodResolver = NeighborhoodResolver()
	) {
		self.locationProvider = locationProvider
		self.mapDataClient = mapDataClient
		self.neighborhoodProvider = neighborhoodProvider
		self.finder = finder
		self.neighborhoodResolver = neighborhoodResolver
	}

	static let shared = OrientSvc(
		locationProvider: LocationProvider(),
		mapDataClient: MapDataClient(),
		neighborhoodProvider: NeighborhoodProvider()
	)

	func prewarmLocation(timeout: TimeInterval = 4) async -> Bool {
		await locationProvider.prewarmContext(timeout: timeout)
	}

	func prewarmInitialNearestMapData(prefs: AppPrefs = AppPrefs()) async -> Bool {
		do {
			var prewarmPrefs = prefs
			prewarmPrefs.mapDetails = MapDetailOptions()
			let context = try await locationProvider.currentContext(requiresFreshHeading: false)
			let mapData = try await mapData(
				for: .nearest,
				from: context,
				minimumCandidateCount: 1,
				prefs: prewarmPrefs
			)
			return hasEnoughCandidates(
				for: .nearest,
				from: context,
				minimumCandidateCount: 1,
				mapData: mapData,
				prefs: prewarmPrefs
			)
		} catch {
			return false
		}
	}

	func prewarmInitialReportMapData(prefs: AppPrefs = AppPrefs()) async -> Bool {
		do {
			let context = try await locationProvider.currentContext(requiresFreshHeading: false)
			let nearestPrefs = await prefsForFirstLookup(kind: .nearest, rank: 1, prefs: prefs)
			_ = try await mapData(
				for: .nearest,
				from: context,
				minimumCandidateCount: 1,
				prefs: nearestPrefs
			)

			let upcomingPrefs = await prefsForFirstLookup(kind: .upcoming, rank: 1, prefs: prefs)
			let upcomingData = try await initialUpcomingMapData(from: context, prefs: upcomingPrefs)
			if upcomingData.intersections.isEmpty {
				_ = try await mapData(
					for: .upcoming,
					from: context,
					minimumCandidateCount: 1,
					prefs: upcomingPrefs
				)
			}
			return true
		} catch {
			return false
		}
	}

	func report(
		_ kind: ReportKind,
		rank: Int = 1,
		prefs: AppPrefs = AppPrefs()
	) async throws -> OrientReport {
		var context = try await locationProvider.currentContext(requiresFreshHeading: kind == .upcoming || kind == .scan)
		let requiresRankedRoadLookup = kind == .upcoming && rank > 1
		let lookupPrefs = await prefsForFirstLookup(kind: kind, rank: rank, prefs: prefs)
		var mapData = if kind == .upcoming, rank == 1 {
			try await initialUpcomingMapData(from: context, prefs: lookupPrefs)
		} else {
			try await mapData(
				for: kind,
				from: context,
				minimumCandidateCount: rank,
				prefs: lookupPrefs,
				allowsRankedExpansion: requiresRankedRoadLookup
			)
		}
		if kind == .upcoming {
			var reports = await upcomingReports(
				from: context,
				mapData: mapData,
				prefs: prefs,
				maxCount: rank == 1 ? 1 : 3
			)
			if reports.isEmpty,
			   let retryContext = try? await locationProvider.currentContext(requiresFreshHeading: true) {
				let retryReports = await upcomingReports(
					from: retryContext,
					mapData: mapData,
					prefs: prefs,
					maxCount: rank == 1 ? 1 : 3
				)
				context = retryContext
				reports = retryReports
			}
			if reports.isEmpty, rank == 1 {
				mapData = try await self.mapData(
					for: kind,
					from: context,
					minimumCandidateCount: 1,
					prefs: lookupPrefs
				)
				reports = await upcomingReports(
					from: context,
					mapData: mapData,
					prefs: prefs,
					maxCount: 1
				)
			}
			await upcomingCache.store(
				reports: reports,
				prefsKey: upcomingPrefsKey(for: prefs),
				context: context
			)
			guard reports.indices.contains(rank - 1) else {
				throw OrientError.noIntersections
			}
			return reports[rank - 1]
		}
		return try await makeReport(
			kind,
			rank: rank,
			context: context,
			mapData: mapData,
			prefs: prefs
		)
	}

	func spokenText(
		_ kind: ReportKind,
		prefs: AppPrefs = AppPrefs()
	) async throws -> String {
		guard prefs.spokenIntersectionCount != .one else {
			return try await report(kind, prefs: prefs).text(with: prefs)
		}

		var context = try await locationProvider.currentContext(requiresFreshHeading: kind == .upcoming || kind == .scan)
		let requestedCount = prefs.spokenIntersectionCount.rawValue
		let resultCount = requestedCount
		let firstLookupPrefs = await prefsForFirstLookup(kind: kind, rank: 1, prefs: prefs)
		var firstMapData = if kind == .upcoming {
			try await initialUpcomingMapData(from: context, prefs: firstLookupPrefs)
		} else {
			try await mapData(
				for: kind,
				from: context,
				minimumCandidateCount: 1,
				prefs: firstLookupPrefs
			)
		}
		var reports = await spokenReports(
			for: kind,
			from: context,
			mapData: firstMapData,
			prefs: prefs,
			maxCount: resultCount
		)
		if kind == .upcoming, reports.isEmpty,
		   let retryContext = try? await locationProvider.currentContext(requiresFreshHeading: true) {
			let retryReports = await spokenReports(
				for: kind,
				from: retryContext,
				mapData: firstMapData,
				prefs: prefs,
				maxCount: resultCount
			)
			context = retryContext
			reports = retryReports
		}
		if kind == .upcoming, reports.isEmpty {
			firstMapData = try await mapData(
				for: kind,
				from: context,
				minimumCandidateCount: 1,
				prefs: firstLookupPrefs
			)
			reports = await spokenReports(
				for: kind,
				from: context,
				mapData: firstMapData,
				prefs: prefs,
				maxCount: resultCount
			)
		}
		guard !reports.isEmpty else {
			throw OrientError.noIntersections
		}
		if reports.count < resultCount {
			do {
				let expandedMapData = try await mapDataForSpokenExpansion(
					for: kind,
					from: context,
					minimumCandidateCount: resultCount,
					prefs: prefs
				)
				let expandedReports = await spokenReports(
					for: kind,
					from: context,
					mapData: expandedMapData,
					prefs: prefs,
					maxCount: resultCount
				)
				if expandedReports.count > reports.count {
					reports = expandedReports
				}
			} catch {}
		}
		if kind == .upcoming {
			await upcomingCache.store(
				reports: reports,
				prefsKey: upcomingPrefsKey(for: prefs),
				context: context
			)
		}
		return IntersectionReportList(reports: reports).text(with: prefs)
	}

	private func upcomingPrefsKey(for prefs: AppPrefs) -> String {
		[
			prefs.areaMode.rawValue,
			prefs.measurementUnit.rawValue,
			prefs.directionStyle.rawValue,
			prefs.intersectionWording.rawValue,
			String(prefs.announcementOptions.includeDistance),
			String(prefs.announcementOptions.includeDirection),
			String(prefs.announcementOptions.includeNeighborhood),
			String(prefs.announcementOptions.includeIntersectionDetails),
			String(prefs.mapDetails.includeCrossings),
			String(prefs.mapDetails.includeWalkingPaths),
			String(prefs.manhattanSnobMode)
		].joined(separator: "|")
	}

	private func prefsForFirstLookup(
		kind: ReportKind,
		rank: Int,
		prefs: AppPrefs
	) async -> AppPrefs {
		guard rank == 1 else {
			return prefs
		}
		switch kind {
		case .nearest:
			var lookupPrefs = prefs
			lookupPrefs.mapDetails.includeWalkingPaths = false
			return lookupPrefs
		case .upcoming, .scan:
			return prefs
		}
	}

	private func initialUpcomingMapData(
		from context: DeviceContext,
		prefs: AppPrefs
	) async throws -> MapDataSet {
		try await mapData(
			for: .upcoming,
			from: context,
			radius: 225,
			minimumCandidateCount: 1,
			prefs: prefs,
			previousData: MapDataSet(intersections: [], roads: []),
			bypassesCache: false
		)
	}

	private func mapDataForSpokenExpansion(
		for kind: ReportKind,
		from context: DeviceContext,
		minimumCandidateCount: Int,
		prefs: AppPrefs
	) async throws -> MapDataSet {
		try await withThrowingTaskGroup(of: MapDataSet.self) { group in
			group.addTask {
				try await mapData(
					for: kind,
					from: context,
					minimumCandidateCount: minimumCandidateCount,
					prefs: prefs,
					allowsRankedExpansion: kind == .upcoming && minimumCandidateCount > 1
				)
			}
			group.addTask {
				try await Task.sleep(for: Self.spokenExpansionTimeout)
				throw URLError(.timedOut)
			}

			defer {
				group.cancelAll()
			}
			guard let data = try await group.next() else {
				throw OrientError.noIntersections
			}
			return data
		}
	}

	private func spokenReports(
		for kind: ReportKind,
		from context: DeviceContext,
		mapData: MapDataSet,
		prefs: AppPrefs,
		maxCount: Int
	) async -> [OrientReport] {
		let ranked: [IntersectionCandidate]
		switch kind {
		case .nearest:
			ranked = finder.rankedNearest(from: context.coordinate, in: mapData.intersections)
		case .upcoming:
			ranked = finder.upcomingSequence(
				from: context,
				in: mapData
			)
		case .scan:
			ranked = finder.scanMatch(from: context, in: mapData.intersections).map { [$0.candidate] } ?? []
		}
		let neighborhoodContext = await neighborhoodContext(for: prefs, from: context)
		var reports: [OrientReport] = []
		for match in ranked {
			let report = makeReport(
				kind,
				match: match,
				context: context,
				mapData: mapData,
				prefs: prefs,
				neighborhoodContext: neighborhoodContext
			)
			if !reports.containsSpokenIntersection(matching: report) {
				reports.append(report)
			}
			if reports.count == maxCount {
				break
			}
		}
		return reports
	}

	private func upcomingReports(
		from context: DeviceContext,
		mapData: MapDataSet,
		prefs: AppPrefs,
		maxCount: Int
	) async -> [OrientReport] {
		let ranked: [IntersectionCandidate]
		ranked = finder.upcomingSequence(
			from: context,
			in: mapData
		)
		let neighborhoodContext = await neighborhoodContext(for: prefs, from: context)
		var reports: [OrientReport] = []
		for match in ranked {
			let report = makeReport(
				.upcoming,
				match: match,
				context: context,
				mapData: mapData,
				prefs: prefs,
				neighborhoodContext: neighborhoodContext
			)
			if !reports.containsSpokenIntersection(matching: report) {
				reports.append(report)
			}
			if reports.count == maxCount {
				break
			}
		}
		return reports
	}

	private func makeReport(
		_ kind: ReportKind,
		rank: Int,
		context: DeviceContext,
		mapData: MapDataSet,
		prefs: AppPrefs
	) async throws -> OrientReport {
		let match = if kind == .nearest {
			finder.nearest(
				rank: rank,
				from: context.coordinate,
				in: mapData.intersections
			)
		} else if kind == .scan {
			finder.scanMatch(from: context, in: mapData.intersections)?.candidate
		} else if rank > 1 {
			finder.upcoming(
				rank: rank,
				from: context,
				in: mapData
			)
		} else {
			finder.bestMatch(for: kind, from: context, in: mapData.intersections)
		}
		guard let match else {
			throw OrientError.noIntersections
		}
		let neighborhoodContext = await neighborhoodContext(for: prefs, from: context)
		return makeReport(
			kind,
			match: match,
			context: context,
			mapData: mapData,
			prefs: prefs,
			neighborhoodContext: neighborhoodContext
		)
	}

	private func makeReport(
		_ kind: ReportKind,
		match: IntersectionCandidate,
		context: DeviceContext,
		mapData: MapDataSet,
		prefs: AppPrefs,
		neighborhoodContext: NeighborhoodContext
	) -> OrientReport {
		let distance = Geo.distanceMeters(from: context.coordinate, to: match.coordinate)
		let bearing = Geo.bearingDegrees(from: context.coordinate, to: match.coordinate)
		let relDegrees = relativeDegrees(
			bearing: bearing,
			heading: context.headingDegrees
		)
		let relDir = relativeDirection(
			bearing: bearing,
			heading: context.headingDegrees,
			kind: kind
		)
		let currentStreet = mapData.nearestRoadName(
			to: context.coordinate,
			matching: match.roadNames
		)
		let crossStreet: String? = currentStreet.flatMap { roadName in
			let otherNames = mapData.crossStreetNames(
				for: match,
				on: roadName,
				heading: context.dependableTravelDirection
			)
			return otherNames.isEmpty ? nil : otherNames.joined(separator: " and ")
		}
		let cross = currentStreet.flatMap { roadName in
			crossStreet.map { "\(roadName) and \($0)" }
		} ?? match.title

		return OrientReport(
			kind: kind,
			cross: cross,
			dist: Geo.spokenDistance(distance, unit: prefs.measurementUnit),
			relDir: relDir,
			relDegrees: relDegrees,
			street: currentStreet,
			crossStreet: crossStreet,
			head: Geo.compassDirection(bearing),
			area: neighborhoodContext.area,
			toward: neighborhoodContext.toward,
			conf: confidence(for: kind, heading: context.headingDegrees),
			intersectionDetails: match.intersectionDetails
		)
	}

	private func mapData(
		for kind: ReportKind,
		from context: DeviceContext,
		minimumCandidateCount: Int,
		prefs: AppPrefs,
		allowsRankedExpansion: Bool = false,
		bypassesCache: Bool = false
	) async throws -> MapDataSet {
		if kind == .upcoming, minimumCandidateCount > 1, allowsRankedExpansion {
			let initialData = try await mapData(
				for: kind,
				from: context,
				radius: 225,
				minimumCandidateCount: minimumCandidateCount,
				prefs: prefs,
				previousData: MapDataSet(intersections: [], roads: []),
				bypassesCache: false
			)
			if hasEnoughCandidates(
				for: kind,
				from: context,
				minimumCandidateCount: minimumCandidateCount,
				mapData: initialData,
				prefs: prefs
			) {
				return initialData
			}
			guard let roadName = initialData.currentRoadName(from: context) else {
				return initialData
			}
			do {
				let focusedData = try await mapDataClient.roadMapData(
					near: context.coordinate,
					roadName: roadName,
					radiusMeters: minimumCandidateCount >= 3 ? 1_200 : 750,
					options: prefs.mapDetails
				)
				return initialData.merging(focusedData)
			} catch {
				guard prefs.mapDetails.includeCrossings else {
					return initialData
				}
				var fallbackOptions = prefs.mapDetails
				fallbackOptions.includeCrossings = false
				do {
					let focusedData = try await mapDataClient.roadMapData(
						near: context.coordinate,
						roadName: roadName,
						radiusMeters: minimumCandidateCount >= 3 ? 1_200 : 750,
						options: fallbackOptions
					)
					return initialData.merging(focusedData)
				} catch {
					return initialData
				}
			}
		}

		let radii = lookupRadii()
		var latestData = MapDataSet(intersections: [], roads: [])

		for radius in radii {
			do {
				latestData = try await mapData(
					for: kind,
					from: context,
					radius: radius,
					minimumCandidateCount: minimumCandidateCount,
					prefs: prefs,
					previousData: latestData,
					bypassesCache: bypassesCache
				)
			} catch {
				guard !latestData.intersections.isEmpty else {
					throw error
				}
				continue
			}

			if hasEnoughCandidates(
				for: kind,
				from: context,
				minimumCandidateCount: minimumCandidateCount,
				mapData: latestData,
				prefs: prefs
			) {
				return latestData
			}
		}

		return latestData
	}

	private func lookupRadii() -> [CLLocationDistance] {
		[225, 375, 750, 1_200]
	}

	private func mapData(
		for kind: ReportKind,
		from context: DeviceContext,
		radius: CLLocationDistance,
		minimumCandidateCount: Int,
		prefs: AppPrefs,
		previousData: MapDataSet,
		bypassesCache: Bool
	) async throws -> MapDataSet {
		if minimumCandidateCount == 1, kind != .scan {
			if kind == .upcoming, prefs.mapDetails.includeWalkingPaths {
				return try await mapDataClient.mapData(
					near: context.coordinate,
					radiusMeters: radius,
					options: prefs.mapDetails
				)
			}
			return try await mapDataClient.immediateMapData(
				near: context.coordinate,
				radiusMeters: radius,
				options: prefs.mapDetails
			)
		}

		do {
			if bypassesCache {
				return try await mapDataClient.freshMapData(
					near: context.coordinate,
					radiusMeters: radius,
					options: prefs.mapDetails
				)
			}
			return try await mapDataClient.mapData(
				near: context.coordinate,
				radiusMeters: radius,
				options: prefs.mapDetails
			)
		} catch {
			guard shouldRetryRankedUpcomingWithoutCrossings(
				kind: kind,
				minimumCandidateCount: minimumCandidateCount,
				prefs: prefs
			) else {
				throw error
			}
			var fallbackOptions = prefs.mapDetails
			fallbackOptions.includeCrossings = false
			let fallbackData = if bypassesCache {
				try await mapDataClient.freshMapData(
					near: context.coordinate,
					radiusMeters: radius,
					options: fallbackOptions
				)
			} else {
				try await mapDataClient.mapData(
					near: context.coordinate,
					radiusMeters: radius,
					options: fallbackOptions
				)
			}
			return previousData.merging(fallbackData)
		}
	}

	private func shouldRetryRankedUpcomingWithoutCrossings(
		kind: ReportKind,
		minimumCandidateCount: Int,
		prefs: AppPrefs
	) -> Bool {
		kind == .upcoming &&
			minimumCandidateCount > 1 &&
			prefs.mapDetails.includeCrossings
	}

	private func hasEnoughCandidates(
		for kind: ReportKind,
		from context: DeviceContext,
		minimumCandidateCount: Int,
		mapData: MapDataSet,
		prefs: AppPrefs
	) -> Bool {
		if kind == .nearest {
			return finder.rankedNearest(
				from: context.coordinate,
				in: mapData.intersections
			).count >= minimumCandidateCount
		}
		if kind == .scan {
			return finder.scanMatch(from: context, in: mapData.intersections) != nil
		}
		let ranked = finder.upcomingSequence(from: context, in: mapData)
		let neighborhoodContext = NeighborhoodContext(area: nil, toward: nil)
		var reports: [OrientReport] = []
		for match in ranked {
			let report = makeReport(
				.upcoming,
				match: match,
				context: context,
				mapData: mapData,
				prefs: prefs,
				neighborhoodContext: neighborhoodContext
			)
			if !reports.containsSpokenIntersection(matching: report) {
				reports.append(report)
			}
			if reports.count >= minimumCandidateCount {
				return true
			}
		}
		return false
	}

	private func neighborhoodContext(
		for prefs: AppPrefs,
		from context: DeviceContext
	) async -> NeighborhoodContext {
		guard prefs.announcementOptions.includeNeighborhood, prefs.areaMode != .off else {
			return NeighborhoodContext(area: nil, toward: nil)
		}

		do {
			let neighborhoods = try await neighborhoodProvider.neighborhoods(
				near: context.coordinate,
				radiusMeters: 1_500
			)
			return neighborhoodResolver.context(
				from: neighborhoods,
				origin: context.coordinate,
				heading: context.headingDegrees,
				mode: prefs.areaMode
			)
		} catch {
			return NeighborhoodContext(area: nil, toward: nil)
		}
	}

	private func relativeDirection(
		bearing: CLLocationDirection,
		heading: CLLocationDirection?,
		kind: ReportKind
	) -> String? {
		guard let heading else {
			return kind == .nearest ? Geo.compassDirection(bearing) : nil
		}
		let degrees = Geo.normalizedDegrees(bearing - heading)

		switch degrees {
		case 337.5...360, 0..<22.5:
			return "ahead"
		case 22.5..<67.5:
			return "ahead and right"
		case 67.5..<112.5:
			return "right"
		case 112.5..<157.5:
			return "behind and right"
		case 157.5..<202.5:
			return "behind"
		case 202.5..<247.5:
			return "behind and left"
		case 247.5..<292.5:
			return "left"
		default:
			return "ahead and left"
		}
	}

	private func relativeDegrees(
		bearing: CLLocationDirection,
		heading: CLLocationDirection?
	) -> CLLocationDirection? {
		guard let heading else {
			return nil
		}
		return Geo.normalizedDegrees(bearing - heading)
	}

	private func confidence(for kind: ReportKind, heading: CLLocationDirection?) -> ConfLev {
		switch (kind, heading) {
		case (.nearest, _):
			.high
		case (_, .some):
			.medium
		case (_, .none):
			.low
		}
	}
}

private extension Array where Element == OrientReport {
	func containsSpokenIntersection(matching report: OrientReport) -> Bool {
		contains { existing in
			if
				let existingStreet = existing.street,
				let existingCrossStreet = existing.crossStreet,
				let reportStreet = report.street,
				let reportCrossStreet = report.crossStreet
			{
				return existingStreet == reportStreet && existingCrossStreet == reportCrossStreet
			}
			return existing.cross == report.cross
		}
	}
}

actor UpcomingReportCache {
	private var entry: Entry?
	private let timeToLive: TimeInterval = 60

	func store(reports: [OrientReport], prefsKey: String, context: DeviceContext, now: Date = .now) {
		guard !reports.isEmpty else {
			return
		}
		entry = Entry(
			reports: reports,
			prefsKey: prefsKey,
			coordinate: context.coordinate,
			headingDegrees: context.headingDegrees,
			storedAt: now
		)
	}

	func report(rank: Int, prefsKey: String, context: DeviceContext, now: Date = .now) -> OrientReport? {
		guard
			rank > 1,
			let entry,
			now.timeIntervalSince(entry.storedAt) <= timeToLive,
			entry.prefsKey == prefsKey,
			entry.reports.indices.contains(rank - 1),
			matches(entry, context: context)
		else {
			return nil
		}
		return entry.reports[rank - 1]
	}

	private func matches(_ entry: Entry, context: DeviceContext) -> Bool {
		guard
			Self.distanceMeters(from: entry.coordinate, to: context.coordinate) <= 25,
			let cachedHeading = entry.headingDegrees,
			let currentHeading = context.headingDegrees
		else {
			return false
		}
		return Self.angleDelta(from: cachedHeading, to: currentHeading) <= 20
	}

	private static func distanceMeters(
		from start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> CLLocationDistance {
		CLLocation(latitude: start.latitude, longitude: start.longitude)
			.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
	}

	private static func angleDelta(
		from heading: CLLocationDirection,
		to bearing: CLLocationDirection
	) -> CLLocationDirection {
		let rawDelta = abs(bearing - heading).truncatingRemainder(dividingBy: 360)
		return min(rawDelta, 360 - rawDelta)
	}

	private struct Entry {
		var reports: [OrientReport]
		var prefsKey: String
		var coordinate: CLLocationCoordinate2D
		var headingDegrees: CLLocationDirection?
		var storedAt: Date
	}
}

enum Geo {
	static func distanceMeters(
		from start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> CLLocationDistance {
		CLLocation(latitude: start.latitude, longitude: start.longitude)
			.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
	}

	static func bearingDegrees(
		from start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> CLLocationDirection {
		let lat1 = start.latitude * .pi / 180
		let lat2 = end.latitude * .pi / 180
		let lonDelta = (end.longitude - start.longitude) * .pi / 180
		let y = sin(lonDelta) * cos(lat2)
		let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lonDelta)
		return normalizedDegrees(atan2(y, x) * 180 / .pi)
	}

	static func normalizedDegrees(_ degrees: CLLocationDirection) -> CLLocationDirection {
		let value = degrees.truncatingRemainder(dividingBy: 360)
		return value >= 0 ? value : value + 360
	}

	static func compassDirection(_ degrees: CLLocationDirection) -> String {
		let names = [
			"north", "northeast", "east", "southeast",
			"south", "southwest", "west", "northwest"
		]
		let index = Int((normalizedDegrees(degrees) + 22.5) / 45) % names.count
		return names[index]
	}

	static func localizedDirection(_ degrees: CLLocationDirection, prefs: AppPrefs) -> String {
		let direction = compassDirection(degrees)
		guard prefs.manhattanSnobMode else {
			return direction
		}
		return manhattanDirection(for: direction)
	}

	static func manhattanDirection(for direction: String) -> String {
		switch direction {
		case "north", "northeast":
			"Uptown"
		case "east", "southeast":
			"East Side"
		case "south", "southwest":
			"Downtown"
		case "west", "northwest":
			"West Side"
		default:
			direction
		}
	}

	static func spokenDistance(_ meters: CLLocationDistance, unit: MeasurementUnit = .feet) -> String {
		switch unit {
		case .feet:
			spokenFeetDistance(meters)
		case .meters:
			spokenMeterDistance(meters)
		}
	}

	private static func spokenFeetDistance(_ meters: CLLocationDistance) -> String {
		let feet = meters * 3.28084
		if feet < 500 {
			let rounded = (feet / 10).rounded() * 10
			return "\(Int(rounded)) feet"
		}
		let miles = feet / 5280
		return String(format: "%.1f miles", miles)
	}

	private static func spokenMeterDistance(_ meters: CLLocationDistance) -> String {
		if meters < 1_000 {
			let rounded = (meters / 5).rounded() * 5
			return "\(Int(rounded)) meters"
		}
		let kilometers = meters / 1_000
		return String(format: "%.1f kilometers", kilometers)
	}
}
