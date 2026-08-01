//
//  WatchOrientationService.swift
//  Intersector Watch App
//
//  Created by Marco Salsiccia on 6/17/26.
//

import CoreLocation
import Foundation

enum WatchReportKind {
	case nearest
	case upcoming

	var leadText: String {
		switch self {
		case .nearest:
			"Nearest"
		case .upcoming:
			"Upcoming"
		}
	}

	var intentLabel: String {
		switch self {
		case .nearest:
			"nearest intersection"
		case .upcoming:
			"upcoming intersection"
		}
	}
}

enum WatchReportError: LocalizedError {
	case noIntersections
	case headingUnavailable
	case locationUnavailable
	case invalidMapData
	case invalidResponse
	case serverError(Int)

	var errorDescription: String? {
		switch self {
		case .noIntersections:
			"No nearby mapped intersections were found."
		case .headingUnavailable:
			"Direction is not available yet."
		case .locationUnavailable:
			"Location is not available yet. Try again."
		case .invalidMapData:
			"The map server returned data Intersector could not read."
		case .invalidResponse:
			"The map server returned an unreadable response."
		case .serverError(let statusCode):
			"The map server returned error \(statusCode)."
		}
	}
}

struct WatchAppPrefs: Equatable, Hashable {
	var areaMode = WatchAreaMode.near
	var measurementUnit = WatchMeasurementUnit.feet
	var directionStyle = WatchDirectionStyle.words
	var intersectionWording = WatchIntersectionWording.direct
	var spokenIntersectionCount = WatchSpokenIntersectionCount.one
	var announcementOptions = WatchAnnouncementOptions()
	var mapDetails = WatchMapDetailOptions()
	var manhattanSnobMode = false

	nonisolated static func saved(from defaults: UserDefaults = .standard) -> WatchAppPrefs {
		let announcementOptions = WatchAnnouncementOptions.saved(from: defaults)
		let savedAreaMode = WatchAreaMode(rawValue: defaults.string(forKey: "areaMode") ?? "") ?? .near
		return WatchAppPrefs(
			areaMode: savedAreaMode == .off ? .near : savedAreaMode,
			measurementUnit: WatchMeasurementUnit(rawValue: defaults.string(forKey: "measurementUnit") ?? "") ?? .feet,
			directionStyle: WatchDirectionStyle(rawValue: defaults.string(forKey: "directionStyle") ?? "") ?? .words,
			intersectionWording: .direct,
			spokenIntersectionCount: WatchSpokenIntersectionCount(
				rawValue: defaults.integer(forKey: "spokenIntersectionCount")
			) ?? .one,
			announcementOptions: announcementOptions,
			mapDetails: WatchMapDetailOptions(
				includeCrossings: defaults.object(forKey: "includeCrossings") as? Bool ?? false,
				includeWalkingPaths: defaults.object(forKey: "includeWalkingPaths") as? Bool ?? false
			),
			manhattanSnobMode: defaults.object(forKey: "manhattanSnobMode") as? Bool ?? false
		)
	}
}

struct WatchAnnouncementOptions: Equatable, Hashable {
	var includeDistance = true
	var includeDirection = true
	var includeNeighborhood = true
	var includeIntersectionDetails = false

	nonisolated init(
		includeDistance: Bool = true,
		includeDirection: Bool = true,
		includeNeighborhood: Bool = true,
		includeIntersectionDetails: Bool = false
	) {
		self.includeDistance = includeDistance
		self.includeDirection = includeDirection
		self.includeNeighborhood = includeNeighborhood
		self.includeIntersectionDetails = includeIntersectionDetails
	}

	nonisolated static func saved(from defaults: UserDefaults) -> WatchAnnouncementOptions {
		let savedAreaMode = WatchAreaMode(rawValue: defaults.string(forKey: "areaMode") ?? "")
		let neighborhoodFallback = savedAreaMode.map { $0 != .off } ?? false
		let hasExplicitOptions =
			defaults.object(forKey: "includeAnnouncementDistance") != nil ||
			defaults.object(forKey: "includeAnnouncementDirection") != nil ||
			defaults.object(forKey: "includeAnnouncementNeighborhood") != nil ||
			defaults.object(forKey: "includeIntersectionDetails") != nil
		guard hasExplicitOptions else {
			return WatchAnnouncementOptions(includeNeighborhood: neighborhoodFallback)
		}
		return WatchAnnouncementOptions(
			includeDistance: defaults.object(forKey: "includeAnnouncementDistance") as? Bool ?? true,
			includeDirection: defaults.object(forKey: "includeAnnouncementDirection") as? Bool ?? true,
			includeNeighborhood: defaults.object(forKey: "includeAnnouncementNeighborhood") as? Bool ?? neighborhoodFallback,
			includeIntersectionDetails: defaults.object(forKey: "includeIntersectionDetails") as? Bool ?? false
		)
	}

	var speaksIntersectionNamesOnly: Bool {
		!includeDistance && !includeDirection && !includeNeighborhood && !includeIntersectionDetails
	}
}

struct WatchMapDetailOptions: Equatable, Hashable, Sendable {
	var includeCrossings = false
	var includeWalkingPaths = false

	nonisolated init(
		includeCrossings: Bool = false,
		includeWalkingPaths: Bool = false
	) {
		self.includeCrossings = includeCrossings
		self.includeWalkingPaths = includeWalkingPaths
	}

	nonisolated static func == (lhs: WatchMapDetailOptions, rhs: WatchMapDetailOptions) -> Bool {
		lhs.includeCrossings == rhs.includeCrossings &&
			lhs.includeWalkingPaths == rhs.includeWalkingPaths
	}

	nonisolated func hash(into hasher: inout Hasher) {
		hasher.combine(includeCrossings)
		hasher.combine(includeWalkingPaths)
	}
}

enum WatchAreaMode: String, CaseIterable, Identifiable {
	case off
	case near
	case toward

	var id: String { rawValue }

	var label: String {
		switch self {
		case .off:
			"Off"
		case .near:
			"Nearby only"
		case .toward:
			"Nearby and toward"
		}
	}
}

enum WatchMeasurementUnit: String, CaseIterable, Identifiable {
	case feet
	case meters

	var id: String { rawValue }

	var label: String {
		switch self {
		case .feet:
			"Feet"
		case .meters:
			"Meters"
		}
	}
}

enum WatchDirectionStyle: String, CaseIterable, Identifiable {
	case words
	case cardinal
	case clockFace

	var id: String { rawValue }

	var label: String {
		switch self {
		case .words:
			"Relative"
		case .cardinal:
			"Cardinal"
		case .clockFace:
			"Clock Face"
		}
	}
}

enum WatchIntersectionWording: String, CaseIterable, Identifiable {
	case direct
	case streetContext

	var id: String { rawValue }
}

enum WatchSpokenIntersectionCount: Int, CaseIterable, Identifiable {
	case one = 1
	case two = 2
	case three = 3

	var id: Int { rawValue }
	var label: String { String(rawValue) }
}

enum IntersectorWatchReporter {
	@MainActor
	static func reportText(for kind: WatchReportKind, prefs: WatchAppPrefs = WatchAppPrefs.saved()) async -> String {
		do {
			return try await WatchOrientationService().spokenText(kind, prefs: prefs)
		} catch {
			return "I couldn't find your \(kind.intentLabel.lowercased()). Please try again."
		}
	}

	@MainActor
	static func directionText(prefs: WatchAppPrefs = WatchAppPrefs.saved()) async -> String {
		do {
			let heading = try await WatchLocationProvider().currentHeading(allowCached: false)
			return "Facing \(WatchGeo.localizedDirection(heading, prefs: prefs))."
		} catch {
			return "I couldn't get your direction. Please try again."
		}
	}
}

struct WatchOrientationService {
	private let locationProvider = WatchLocationProvider()
	private let mapClient = WatchMapDataClient()
	private let neighborhoodProvider = WatchNeighborhoodProvider()
	private let finder = WatchIntersectionFinder()
	private let neighborhoodResolver = WatchNeighborhoodResolver()
	private static let spokenExpansionTimeout: Duration = .seconds(8)

	@MainActor
	func spokenText(_ kind: WatchReportKind, prefs: WatchAppPrefs) async throws -> String {
		guard prefs.spokenIntersectionCount != .one else {
			return try await report(kind, prefs: prefs).text(with: prefs)
		}

		var context = try await locationProvider.currentContext(requiresFreshHeading: kind == .upcoming)
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
			throw WatchReportError.noIntersections
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
		return WatchIntersectionReportList(reports: reports).text(with: prefs)
	}

	@MainActor
	private func mapDataForSpokenExpansion(
		for kind: WatchReportKind,
		from context: WatchDeviceContext,
		minimumCandidateCount: Int,
		prefs: WatchAppPrefs
	) async throws -> WatchMapDataSet {
		try await withThrowingTaskGroup(of: WatchMapDataSet.self) { group in
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
				throw WatchReportError.noIntersections
			}
			return data
		}
	}

	@MainActor
	private func spokenReports(
		for kind: WatchReportKind,
		from context: WatchDeviceContext,
		mapData: WatchMapDataSet,
		prefs: WatchAppPrefs,
		maxCount: Int
	) async -> [WatchOrientationReport] {
		let ranked: [WatchIntersectionCandidate]
		switch kind {
		case .nearest:
			ranked = finder.rankedNearest(from: context.coordinate, in: mapData.intersections)
		case .upcoming:
			ranked = finder.upcomingSequence(
				from: context,
				in: mapData
			)
		}
		let neighborhoodContext = await neighborhoodContext(for: prefs.areaMode, from: context)
		var reports: [WatchOrientationReport] = []
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

	@MainActor
	func report(_ kind: WatchReportKind, rank: Int = 1, prefs: WatchAppPrefs) async throws -> WatchOrientationReport {
		var context = try await locationProvider.currentContext(requiresFreshHeading: kind == .upcoming)
		let lookupPrefs = await prefsForFirstLookup(kind: kind, rank: rank, prefs: prefs)
		var mapData = if kind == .upcoming, rank == 1 {
			try await initialUpcomingMapData(from: context, prefs: lookupPrefs)
		} else {
			try await mapData(
				for: kind,
				from: context,
				minimumCandidateCount: rank,
				prefs: lookupPrefs,
				allowsRankedExpansion: rank > 1
			)
		}
		var match = if kind == .nearest {
			finder.nearest(rank: rank, from: context.coordinate, in: mapData.intersections)
		} else {
			finder.upcoming(
				rank: rank,
				from: context,
				in: mapData
			)
		}
		if kind == .upcoming, match == nil,
		   let retryContext = try? await locationProvider.currentContext(requiresFreshHeading: true) {
			let retryMatch = finder.upcoming(rank: rank, from: retryContext, in: mapData)
			context = retryContext
			match = retryMatch
		}
		if kind == .upcoming, match == nil, rank == 1 {
			mapData = try await self.mapData(
				for: kind,
				from: context,
				minimumCandidateCount: 1,
				prefs: lookupPrefs
			)
			match = finder.upcoming(rank: 1, from: context, in: mapData)
		}
		guard let match else {
			throw WatchReportError.noIntersections
		}
		let neighborhoodContext = await neighborhoodContext(for: prefs.areaMode, from: context)
		return makeReport(
			kind,
			match: match,
			context: context,
			mapData: mapData,
			prefs: prefs,
			neighborhoodContext: neighborhoodContext
		)
	}

	private func prefsForFirstLookup(
		kind: WatchReportKind,
		rank: Int,
		prefs: WatchAppPrefs
	) async -> WatchAppPrefs {
		guard rank == 1 else {
			return prefs
		}
		guard kind == .nearest else {
			return prefs
		}
		var lookupPrefs = prefs
		lookupPrefs.mapDetails.includeWalkingPaths = false
		return lookupPrefs
	}

	private func initialUpcomingMapData(
		from context: WatchDeviceContext,
		prefs: WatchAppPrefs
	) async throws -> WatchMapDataSet {
		try await mapData(
			for: .upcoming,
			from: context,
			radius: 225,
			minimumCandidateCount: 1,
			prefs: prefs,
			previousData: WatchMapDataSet(intersections: [], roads: [])
		)
	}

	private func makeReport(
		_ kind: WatchReportKind,
		match: WatchIntersectionCandidate,
		context: WatchDeviceContext,
		mapData: WatchMapDataSet,
		prefs: WatchAppPrefs,
		neighborhoodContext: WatchNeighborhoodContext
	) -> WatchOrientationReport {
		let distance = WatchGeo.distanceMeters(from: context.coordinate, to: match.coordinate)
		let bearing = WatchGeo.bearingDegrees(from: context.coordinate, to: match.coordinate)
		let relDegrees = relativeDegrees(bearing: bearing, heading: context.headingDegrees)
		let relDir = relativeDirection(bearing: bearing, heading: context.headingDegrees, kind: kind)
		let currentStreet = mapData.nearestRoadName(to: context.coordinate, matching: match.roadNames)
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

		return WatchOrientationReport(
			kind: kind,
			cross: cross,
			dist: WatchGeo.spokenDistance(distance, unit: prefs.measurementUnit),
			relDir: relDir,
			relDegrees: relDegrees,
			street: currentStreet,
			crossStreet: crossStreet,
			head: WatchGeo.compassDirection(bearing),
			area: neighborhoodContext.area,
			toward: neighborhoodContext.toward,
			intersectionDetails: match.intersectionDetails
		)
	}

	private func mapData(
		for kind: WatchReportKind,
		from context: WatchDeviceContext,
		minimumCandidateCount: Int,
		prefs: WatchAppPrefs,
		allowsRankedExpansion: Bool = false
	) async throws -> WatchMapDataSet {
		if kind == .upcoming, minimumCandidateCount > 1, allowsRankedExpansion {
			let initialData = try await mapData(
				for: kind,
				from: context,
				radius: 225,
				minimumCandidateCount: minimumCandidateCount,
				prefs: prefs,
				previousData: WatchMapDataSet(intersections: [], roads: [])
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
				let focusedData = try await mapClient.roadMapData(
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
					let focusedData = try await mapClient.roadMapData(
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
		var latestData = WatchMapDataSet(intersections: [], roads: [])
		for radius in radii {
			do {
				latestData = try await mapData(
					for: kind,
					from: context,
					radius: radius,
					minimumCandidateCount: minimumCandidateCount,
					prefs: prefs,
					previousData: latestData
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
		for kind: WatchReportKind,
		from context: WatchDeviceContext,
		radius: CLLocationDistance,
		minimumCandidateCount: Int,
		prefs: WatchAppPrefs,
		previousData: WatchMapDataSet
	) async throws -> WatchMapDataSet {
		if minimumCandidateCount == 1 {
			if kind == .upcoming, prefs.mapDetails.includeWalkingPaths {
				return try await mapClient.mapData(
					near: context.coordinate,
					radiusMeters: radius,
					options: prefs.mapDetails
				)
			}
			return try await mapClient.immediateMapData(
				near: context.coordinate,
				radiusMeters: radius,
				options: prefs.mapDetails
			)
		}

		do {
			return try await mapClient.mapData(
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
			let fallbackData = try await mapClient.mapData(
				near: context.coordinate,
				radiusMeters: radius,
				options: fallbackOptions
			)
			return previousData.merging(fallbackData)
		}
	}

	private func shouldRetryRankedUpcomingWithoutCrossings(
		kind: WatchReportKind,
		minimumCandidateCount: Int,
		prefs: WatchAppPrefs
	) -> Bool {
		kind == .upcoming &&
			minimumCandidateCount > 1 &&
			prefs.mapDetails.includeCrossings
	}

	private func hasEnoughCandidates(
		for kind: WatchReportKind,
		from context: WatchDeviceContext,
		minimumCandidateCount: Int,
		mapData: WatchMapDataSet,
		prefs: WatchAppPrefs
	) -> Bool {
		if kind == .nearest {
			return finder.rankedNearest(from: context.coordinate, in: mapData.intersections).count >= minimumCandidateCount
		}
		guard context.headingDegrees != nil else {
			return false
		}
		let ranked = finder.upcomingSequence(from: context, in: mapData)
		let neighborhoodContext = WatchNeighborhoodContext(area: nil, toward: nil)
		var reports: [WatchOrientationReport] = []
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
		for mode: WatchAreaMode,
		from context: WatchDeviceContext
	) async -> WatchNeighborhoodContext {
		guard mode != .off else {
			return WatchNeighborhoodContext(area: nil, toward: nil)
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
				mode: mode
			)
		} catch {
			return WatchNeighborhoodContext(area: nil, toward: nil)
		}
	}

	private func relativeDirection(
		bearing: CLLocationDirection,
		heading: CLLocationDirection?,
		kind: WatchReportKind
	) -> String? {
		guard let heading else {
			return kind == .nearest ? WatchGeo.compassDirection(bearing) : nil
		}
		let degrees = WatchGeo.normalizedDegrees(bearing - heading)
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
		return WatchGeo.normalizedDegrees(bearing - heading)
	}
}

struct WatchOrientationReport: Equatable {
	var kind: WatchReportKind
	var cross: String
	var dist: String
	var relDir: String?
	var relDegrees: CLLocationDirection?
	var street: String?
	var crossStreet: String?
	var head: String?
	var area: String?
	var toward: String?
	var intersectionDetails: WatchIntersectionDetails? = nil

	func text(with prefs: WatchAppPrefs) -> String {
		text(with: prefs, includeLead: true, rank: nil, includeNeighborhood: true)
	}

	func text(with prefs: WatchAppPrefs, rank: Int) -> String {
		text(with: prefs, includeLead: true, rank: rank, includeNeighborhood: true)
	}

	func text(with prefs: WatchAppPrefs, includeLead: Bool, includeNeighborhood: Bool) -> String {
		text(with: prefs, includeLead: includeLead, rank: nil, includeNeighborhood: includeNeighborhood)
	}

	func neighborhoodText(with prefs: WatchAppPrefs) -> String? {
		areaText(prefs)
	}

	private func text(
		with prefs: WatchAppPrefs,
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
		let shouldIncludeLead = includeLead &&
			(!prefs.announcementOptions.speaksIntersectionNamesOnly || rank != nil)
		if shouldIncludeLead {
			text = "\(leadText(rank: rank)): \(text)"
		}
		if includeNeighborhood, let area = areaText(prefs) {
			text += " \(area)"
		}
		return text + "."
	}

	private func nameOnlyText() -> String {
		guard let street, let crossStreet else {
			return cross
		}
		return "\(street) and \(crossStreet)"
	}

	private func leadText(rank: Int? = nil) -> String {
		if let rank, rank > 1 {
			return "\(Self.ordinal(rank)) \(kind.leadText)"
		}
		return kind.leadText
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

	private func directText(with prefs: WatchAppPrefs) -> String {
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
		prefs: WatchAppPrefs
	) -> String {
		let details = reportDetails(with: prefs)
		guard !details.isEmpty else {
			return "On \(street) at \(crossStreet)"
		}
		return "On \(street) at \(crossStreet), \(details.joined(separator: ", "))"
	}

	private func reportDetails(with prefs: WatchAppPrefs) -> [String] {
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

	private func areaText(_ prefs: WatchAppPrefs) -> String? {
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

	private func directionText(with prefs: WatchAppPrefs) -> String? {
		switch prefs.directionStyle {
		case .words:
			return relDir
		case .cardinal:
			guard let head else {
				return nil
			}
			if prefs.manhattanSnobMode {
				return "toward \(WatchGeo.manhattanDirection(for: head))"
			}
			return head
		case .clockFace:
			return relDegrees.map { Self.clockFaceDirection(from: $0) }
		}
	}

	private static func clockFaceDirection(from degrees: CLLocationDirection) -> String {
		let hour = Int((WatchGeo.normalizedDegrees(degrees) + 15) / 30) % 12
		return "at \(hour == 0 ? 12 : hour) o'clock"
	}
}

struct WatchIntersectionReportList: Equatable {
	var reports: [WatchOrientationReport]

	func text(with prefs: WatchAppPrefs) -> String {
		guard let first = reports.first else {
			return ""
		}
		if prefs.announcementOptions.speaksIntersectionNamesOnly {
			let sharedStreet = first.street.flatMap { streetName in
				reports.allSatisfy { $0.street == streetName && $0.crossStreet != nil } ? streetName : nil
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

	private func sharedNeighborhoodText(with prefs: WatchAppPrefs) -> String? {
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

private extension Array where Element == WatchOrientationReport {
	func containsSpokenIntersection(matching report: WatchOrientationReport) -> Bool {
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

struct WatchDeviceContext {
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

struct WatchIntersectionCandidate: Identifiable, Equatable {
	var id: String
	var names: [String]
	var coordinate: CLLocationCoordinate2D
	var associatedRoadNames: [String] = []
	var intersectionDetails: WatchIntersectionDetails?

	var title: String {
		names.prefix(2).joined(separator: " and ")
	}

	var roadNames: [String] {
		associatedRoadNames.isEmpty ? names : associatedRoadNames
	}

	func contextLabel(on streetName: String) -> String {
		let otherNames = names.filter { $0 != streetName }
		return otherNames.isEmpty ? title : otherNames.joined(separator: " and ")
	}
}

struct WatchIntersectionDetails: Equatable, Hashable {
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

struct WatchMapRoad: Identifiable, Equatable {
	var id: String
	var name: String
	var nodeIDs: [Int64]
	var coordinates: [CLLocationCoordinate2D]
	var highway: String = "road"
}

private struct WatchRoadGraphEdge {
	var nodeID: Int64
	var distance: CLLocationDistance
}

private struct WatchRoadStartSegment {
	var startNodeID: Int64
	var endNodeID: Int64
	var length: CLLocationDistance
	var projection: Double
	var distance: CLLocationDistance
	var tangentX: Double
	var tangentY: Double
}

struct WatchMapDataSet: Equatable {
	var intersections: [WatchIntersectionCandidate]
	var roads: [WatchMapRoad]

	func merging(_ other: WatchMapDataSet) -> WatchMapDataSet {
		var mergedIntersections = intersections
		let existingIntersectionIDs = Set(mergedIntersections.map(\.id))
		mergedIntersections.append(contentsOf: other.intersections.filter { !existingIntersectionIDs.contains($0.id) })

		var mergedRoads = roads
		let existingRoadIDs = Set(mergedRoads.map(\.id))
		mergedRoads.append(contentsOf: other.roads.filter { !existingRoadIDs.contains($0.id) })

		return WatchMapDataSet(intersections: mergedIntersections, roads: mergedRoads)
	}

	func currentRoadName(from context: WatchDeviceContext) -> String? {
		currentRoad(from: context)?.name
	}

	func upcomingRoadSequence(from context: WatchDeviceContext) -> [WatchIntersectionCandidate]? {
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
		let alignment = sin(radians) * start.tangentX + cos(radians) * start.tangentY
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
			.compactMap { candidate -> (candidate: WatchIntersectionCandidate, progress: CLLocationDistance)? in
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
				return WatchGeo.distanceMeters(from: context.coordinate, to: lhs.candidate.coordinate)
					< WatchGeo.distanceMeters(from: context.coordinate, to: rhs.candidate.coordinate)
			}
		return positioned.isEmpty ? nil : positioned.map(\.candidate)
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

	private func nearestRoad(to coordinate: CLLocationCoordinate2D) -> WatchMapRoad? {
		roads.min {
			$0.minimumDistance(to: coordinate) < $1.minimumDistance(to: coordinate)
		}
	}

	private func currentRoad(from context: WatchDeviceContext) -> WatchMapRoad? {
		guard let heading = context.headingDegrees else {
			return nil
		}
		let threshold = currentRoadDistanceThreshold(for: context)
		return roads
			.compactMap { road -> (road: WatchMapRoad, score: Double)? in
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

	private func currentRoadDistanceThreshold(for context: WatchDeviceContext) -> CLLocationDistance {
		let accuracy = context.horizontalAccuracy ?? 25
		return max(25, min(accuracy + 10, 60))
	}

	private func roadGraph(
		from roads: [WatchMapRoad]
	) -> (adjacency: [Int64: [WatchRoadGraphEdge]], coordinates: [Int64: CLLocationCoordinate2D]) {
		var adjacency: [Int64: [WatchRoadGraphEdge]] = [:]
		var coordinates: [Int64: CLLocationCoordinate2D] = [:]
		for road in roads where road.nodeIDs.count == road.coordinates.count && road.nodeIDs.count > 1 {
			for (nodeID, coordinate) in zip(road.nodeIDs, road.coordinates) {
				coordinates[nodeID] = coordinate
			}
			for index in 0..<(road.nodeIDs.count - 1) {
				let startNodeID = road.nodeIDs[index]
				let endNodeID = road.nodeIDs[index + 1]
				let distance = WatchGeo.distanceMeters(
					from: road.coordinates[index],
					to: road.coordinates[index + 1]
				)
				guard distance > 0 else {
					continue
				}
				adjacency[startNodeID, default: []].append(
					WatchRoadGraphEdge(nodeID: endNodeID, distance: distance)
				)
				adjacency[endNodeID, default: []].append(
					WatchRoadGraphEdge(nodeID: startNodeID, distance: distance)
				)
			}
		}
		return (adjacency, coordinates)
	}

	private func nearestRoadSegment(
		to coordinate: CLLocationCoordinate2D,
		in roads: [WatchMapRoad]
	) -> WatchRoadStartSegment? {
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
	) -> WatchRoadStartSegment? {
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
		return WatchRoadStartSegment(
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
		adjacency: [Int64: [WatchRoadGraphEdge]],
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
		start: WatchRoadStartSegment,
		alignment: Double,
		coordinates: [Int64: CLLocationCoordinate2D],
		adjacency: [Int64: [WatchRoadGraphEdge]],
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

	func crossStreetNames(
		for match: WatchIntersectionCandidate,
		on roadName: String,
		heading: CLLocationDirection?
	) -> [String] {
		guard !match.id.hasPrefix("crossing-") else {
			return []
		}
		let candidates = splitIntersectionCandidates(for: match, on: roadName)
		let orderedCandidates = orderedSplitCandidates(candidates, roadName: roadName, heading: heading)
		return orderedCandidates.reduce(into: []) { names, candidate in
			for name in candidate.names where name != roadName && !names.contains(name) {
				names.append(name)
			}
		}
	}

	private func splitIntersectionCandidates(
		for match: WatchIntersectionCandidate,
		on roadName: String
	) -> [WatchIntersectionCandidate] {
		let sameStreetCandidates = intersections.filter {
			!$0.id.hasPrefix("crossing-") && $0.roadNames.contains(roadName)
		}
		let nearbyCandidates = sameStreetCandidates.filter { candidate in
			candidate.id == match.id || isSameSplitIntersection(candidate, as: match, on: roadName)
		}
		return nearbyCandidates.isEmpty ? [match] : nearbyCandidates
	}

	private func isSameSplitIntersection(
		_ candidate: WatchIntersectionCandidate,
		as match: WatchIntersectionCandidate,
		on roadName: String
	) -> Bool {
		guard candidate.id != match.id else {
			return true
		}
		let straightLineDistance = WatchGeo.distanceMeters(from: candidate.coordinate, to: match.coordinate)
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
		_ candidates: [WatchIntersectionCandidate],
		roadName: String,
		heading: CLLocationDirection?
	) -> [WatchIntersectionCandidate] {
		guard let heading else {
			return candidates.sorted {
				WatchGeo.distanceMeters(from: candidates[0].coordinate, to: $0.coordinate)
					< WatchGeo.distanceMeters(from: candidates[0].coordinate, to: $1.coordinate)
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
		for candidate: WatchIntersectionCandidate,
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

extension WatchMapRoad {
	func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
		minimumDistance(to: coordinate) <= 12
	}

	var isPublicStreet: Bool {
		WatchIntersectionBuilder.publicStreetHighways.contains(highway)
	}

	func minimumDistance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
		guard coordinates.count > 1 else {
			return coordinates.first.map {
				WatchGeo.distanceMeters(from: coordinate, to: $0)
			} ?? .greatestFiniteMagnitude
		}
		return zip(coordinates, coordinates.dropFirst())
			.map { start, end in
				Self.distance(from: coordinate, toSegmentFrom: start, to: end)
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

	func vectorAway(from coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double)? {
		coordinates
			.map { Self.localVector(from: coordinate, to: $0) }
			.filter { hypot($0.x, $0.y) > 1 }
			.min { hypot($0.x, $0.y) < hypot($1.x, $1.y) }
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

	private static func distance(
		from coordinate: CLLocationCoordinate2D,
		toSegmentFrom start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> CLLocationDistance {
		let startVector = localVector(from: coordinate, to: start)
		let endVector = localVector(from: coordinate, to: end)
		let segmentX = endVector.x - startVector.x
		let segmentY = endVector.y - startVector.y
		let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
		guard segmentLengthSquared > 0 else {
			return hypot(startVector.x, startVector.y)
		}
		let projection = -(startVector.x * segmentX + startVector.y * segmentY) / segmentLengthSquared
		let clampedProjection = min(1, max(0, projection))
		let closestX = startVector.x + clampedProjection * segmentX
		let closestY = startVector.y + clampedProjection * segmentY
		return hypot(closestX, closestY)
	}
}

@MainActor
final class WatchLocationProvider: NSObject, CLLocationManagerDelegate {
	private let manager = CLLocationManager()
	private var continuation: CheckedContinuation<WatchDeviceContext, Error>?
	private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
	private var headingContinuation: CheckedContinuation<CLLocationDirection, Error>?
	private var headingTimeoutTask: Task<Void, Never>?
	private var headingSettlingTask: Task<Void, Never>?
	private var latestHeading: CLLocationDirection?
	private var latestHeadingDate: Date?

	override init() {
		super.init()
		manager.delegate = self
		manager.desiredAccuracy = kCLLocationAccuracyBest
		manager.distanceFilter = kCLDistanceFilterNone
		manager.headingFilter = 5
	}

	func currentContext() async throws -> WatchDeviceContext {
		try await currentContext(requiresFreshHeading: false)
	}

	func currentContext(requiresFreshHeading: Bool) async throws -> WatchDeviceContext {
		switch manager.authorizationStatus {
		case .notDetermined:
			let status = await requestWhenInUseAuthorization()
			guard status == .authorizedAlways || status == .authorizedWhenInUse else {
				throw WatchReportError.locationUnavailable
			}
		case .authorizedAlways, .authorizedWhenInUse:
			break
		case .denied, .restricted:
			throw WatchReportError.locationUnavailable
		@unknown default:
			throw WatchReportError.locationUnavailable
		}

		if CLLocationManager.headingAvailable() {
			manager.startUpdatingHeading()
		}

		if requiresFreshHeading {
			do {
				_ = try await currentHeading(timeout: 1.2, allowCached: false)
			} catch {
				let hasRecentHeading = latestHeading != nil &&
					latestHeadingDate.map { Date().timeIntervalSince($0) <= 2 } == true
				if !hasRecentHeading {
					clearHeading()
				}
			}
		}

		return try await withCheckedThrowingContinuation { continuation in
			self.continuation = continuation
			manager.startUpdatingLocation()
		}
	}

	func currentHeading(timeout: TimeInterval = 1.5, allowCached: Bool = true) async throws -> CLLocationDirection {
		guard CLLocationManager.headingAvailable() else {
			throw WatchReportError.headingUnavailable
		}
		if allowCached,
		   let latestHeading,
		   let latestHeadingDate,
		   Date().timeIntervalSince(latestHeadingDate) < 2 {
			return latestHeading
		}
		manager.startUpdatingHeading()
		return try await withCheckedThrowingContinuation { continuation in
			headingContinuation = continuation
			headingSettlingTask?.cancel()
			headingSettlingTask = nil
			headingTimeoutTask?.cancel()
			headingTimeoutTask = Task { [weak self] in
				let nanoseconds = UInt64(timeout * 1_000_000_000)
				try? await Task.sleep(nanoseconds: nanoseconds)
				await MainActor.run {
					self?.finishHeading(with: .failure(WatchReportError.headingUnavailable))
				}
			}
		}
	}

	private func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
		switch manager.authorizationStatus {
		case .notDetermined:
			return await withCheckedContinuation { continuation in
				authorizationContinuation = continuation
				manager.requestWhenInUseAuthorization()
			}
		default:
			return manager.authorizationStatus
		}
	}

	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		if let authorizationContinuation {
			self.authorizationContinuation = nil
			authorizationContinuation.resume(returning: manager.authorizationStatus)
		}
	}

	func locationManager(
		_ manager: CLLocationManager,
		didUpdateLocations locations: [CLLocation]
	) {
		guard let location = locations.first(where: { $0.horizontalAccuracy >= 0 }) else {
			finish(.failure(WatchReportError.locationUnavailable))
			return
		}
		finish(
			.success(
					WatchDeviceContext(
						coordinate: location.coordinate,
						headingDegrees: latestHeading,
					courseDegrees: location.course >= 0 ? location.course : nil,
					courseAccuracy: location.courseAccuracy >= 0 ? location.courseAccuracy : nil,
					speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
					horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
				)
			)
		)
	}

	func locationManager(
		_ manager: CLLocationManager,
		didFailWithError error: Error
	) {
		finish(.failure(error))
	}

	func locationManager(
		_ manager: CLLocationManager,
		didUpdateHeading newHeading: CLHeading
	) {
		guard newHeading.headingAccuracy >= 0 else {
			return
		}
		let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
		guard heading >= 0 else {
			return
		}
		latestHeading = heading
		latestHeadingDate = Date()
		if headingContinuation != nil, headingSettlingTask == nil {
			headingSettlingTask = Task { [weak self] in
				try? await Task.sleep(for: .milliseconds(250))
				await MainActor.run {
					guard let self, let settledHeading = self.latestHeading else {
						return
					}
					self.finishHeading(with: .success(settledHeading))
				}
			}
		}
	}

	private func finish(_ result: Result<WatchDeviceContext, Error>) {
		guard let continuation else {
			return
		}
		self.continuation = nil
		manager.stopUpdatingLocation()
		stopHeadingIfIdle()
		switch result {
		case .success(let context):
			continuation.resume(returning: context)
		case .failure(let error):
			continuation.resume(throwing: error)
		}
	}

	private func finishHeading(with result: Result<CLLocationDirection, Error>) {
		guard let headingContinuation else {
			return
		}
		self.headingContinuation = nil
		headingTimeoutTask?.cancel()
		headingTimeoutTask = nil
		headingSettlingTask?.cancel()
		headingSettlingTask = nil
		stopHeadingIfIdle()
		switch result {
		case .success(let heading):
			headingContinuation.resume(returning: heading)
		case .failure(let error):
			headingContinuation.resume(throwing: error)
		}
	}

	private func stopHeadingIfIdle() {
		if headingContinuation == nil {
			manager.stopUpdatingHeading()
		}
	}

	private func clearHeading() {
		latestHeading = nil
		latestHeadingDate = nil
	}
}

struct WatchMapDataClient {
	private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
	private let fallbackEndpoints = [
		URL(string: "https://overpass.private.coffee/api/interpreter")!,
		URL(string: "https://maps.mail.ru/osm/tools/overpass/api/interpreter")!
	]
	private let session: URLSession = .shared
	private static let endpointHealth = WatchMapEndpointHealth()

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: WatchMapDetailOptions
	) async throws -> WatchMapDataSet {
		try await fetchMapData(near: coordinate, radiusMeters: radiusMeters, options: options)
	}

	func immediateMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: WatchMapDetailOptions
	) async throws -> WatchMapDataSet {
		var coreOptions = options
		coreOptions.includeWalkingPaths = false

		return try await fetchMapData(near: coordinate, radiusMeters: radiusMeters, options: coreOptions)
	}

	func roadMapData(
		near coordinate: CLLocationCoordinate2D,
		roadName: String,
		radiusMeters: CLLocationDistance,
		options: WatchMapDetailOptions
	) async throws -> WatchMapDataSet {
		try await fetchMapData(
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
		options: WatchMapDetailOptions
	) async throws -> WatchMapDataSet {
		try await fetchMapData(
			options: options,
			query: roadQuery(near: coordinate, radiusMeters: radiusMeters, options: options)
		)
	}

	private func fetchMapData(
		options: WatchMapDetailOptions,
		query: String
	) async throws -> WatchMapDataSet {
		let endpoints = await Self.endpointHealth.orderedEndpoints(
			primary: endpoint,
			fallbacks: fallbackEndpoints
		)
		for endpoint in endpoints {
			do {
				let data = try await mapData(from: endpoint, options: options, query: query)
				await Self.endpointHealth.markSuccess(endpoint)
				return data
			} catch {
				if isTemporary(error) {
					await Self.endpointHealth.markTemporaryFailure(endpoint)
				}
				guard isTemporary(error), endpoint != endpoints.last else {
					throw error
				}
			}
		}
		throw WatchReportError.invalidResponse
	}

	private func mapData(
		from endpoint: URL,
		options: WatchMapDetailOptions,
		query: String
	) async throws -> WatchMapDataSet {
		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.timeoutInterval = 12
		request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		request.httpBody = query.data(using: .utf8)

		let (data, urlResponse) = try await session.data(for: request)
		guard let httpResponse = urlResponse as? HTTPURLResponse else {
			throw WatchReportError.invalidResponse
		}
		guard (200..<300).contains(httpResponse.statusCode) else {
			throw WatchReportError.serverError(httpResponse.statusCode)
		}
		do {
			let response = try JSONDecoder().decode(WatchOverpassResponse.self, from: data)
			return WatchIntersectionBuilder().mapData(from: response, options: options)
		} catch {
			throw WatchReportError.invalidMapData
		}
	}

	private func isTemporary(_ error: Error) -> Bool {
		if let mapError = error as? WatchReportError {
			switch mapError {
			case .serverError(let statusCode):
				return [429, 500, 502, 503, 504].contains(statusCode)
			default:
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
		options: WatchMapDetailOptions
	) -> String {
		let radius = Int(radiusMeters.rounded())
		var highwayTypes = [
			"primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link",
			"unclassified", "residential", "living_street", "pedestrian", "road"
		]
		if options.includeWalkingPaths {
			highwayTypes += ["footway", "path", "steps", "bridleway"]
		}
		let highwayPattern = highwayTypes.joined(separator: "|")
		let crossingRadius = Int(min(radiusMeters, 225).rounded())
			let crossingQueries = options.includeCrossings ? """
			  (
			    node(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["highway"="crossing"];
			    node(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["crossing"];
			  )->.crossingNodes;
			  way(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["highway"="footway"]["footway"="crossing"]->.crossingWays;
			  way(bn.crossingNodes)["highway"]->.crossingParentWays;
			  .crossingNodes;
			  .crossingWays;
			  .crossingParentWays;
			""" : ""
		let body = """
		[out:json][timeout:10];
		(
		  way(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["highway"~"^(\(highwayPattern))$"]["name"];
		\(crossingQueries)
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
		options: WatchMapDetailOptions
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
			let crossingRadius = Int(min(radiusMeters, 450).rounded())
			let crossingQueries = options.includeCrossings ? """
			  (
			    node(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["highway"="crossing"];
			    node(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["crossing"];
			  )->.crossingNodes;
			  way(around:\(crossingRadius),\(coordinate.latitude),\(coordinate.longitude))["highway"="footway"]["footway"="crossing"]->.crossingWays;
			  way(bn.crossingNodes)["highway"]->.crossingParentWays;
			  .crossingNodes;
			  .crossingWays;
			  .crossingParentWays;
			""" : ""
			let body = """
			[out:json][timeout:10];
			way(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["highway"~"^(\(highwayPattern))$"]["name"="\(escapedRoadName)"]->.currentRoad;
			node(w.currentRoad)->.currentRoadNodes;
			way(bn.currentRoadNodes)["highway"~"^(\(highwayPattern))$"]["name"]->.connectedRoads;
			(.currentRoad;.connectedRoads;
			\(crossingQueries)
			);
			(._;>;);
			out body;
			"""
		return encodedBody(body)
	}

	private var userAgent: String {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
		return "Intersector/\(version) (com.marconius.crossStreet.watchkitapp; marco@marconius.com)"
	}

	private func encodedBody(_ body: String) -> String {
		let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
		let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
		return "data=\(encoded)"
	}
}

struct WatchOverpassResponse: Decodable {
	var elements: [WatchOverpassElement]
}

struct WatchOverpassElement: Decodable {
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

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		type = try container.decode(String.self, forKey: .type)
		id = try container.decode(Int64.self, forKey: .id)
		lat = try container.decodeIfPresent(Double.self, forKey: .lat)
		lon = try container.decodeIfPresent(Double.self, forKey: .lon)
		nodes = try container.decodeIfPresent([Int64].self, forKey: .nodes)
		tags = try container.decodeIfPresent([String: WatchFlexibleString].self, forKey: .tags)?
			.mapValues(\.value)
	}
}

private struct WatchFlexibleString: Decodable {
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

private extension WatchOverpassElement {
	var coordinate: CLLocationCoordinate2D? {
		guard let lat, let lon else {
			return nil
		}
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}
}

struct WatchIntersectionBuilder {
	private static let streetIntersectionDuplicateRadiusMeters: CLLocationDistance = 30
	private static let cornerCrosswalkAnchorRadiusMeters: CLLocationDistance = 75
	private static let cornerCrosswalkClusterRadiusMeters: CLLocationDistance = 45
	private static let cornerCrosswalkClusterCount = 2

	static let publicStreetHighways: Set<String> = [
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

	func mapData(
		from response: WatchOverpassResponse,
		options: WatchMapDetailOptions
	) -> WatchMapDataSet {
		let nodes = Dictionary(
			uniqueKeysWithValues: response.elements.compactMap { element -> (Int64, CLLocationCoordinate2D)? in
				guard element.type == "node", let lat = element.lat, let lon = element.lon else {
					return nil
				}
				return (element.id, CLLocationCoordinate2D(latitude: lat, longitude: lon))
			}
		)
		let crossingWayNodeIDs = Set(
			response.elements
				.filter { $0.type == "way" && isCrossingWay($0.tags) }
				.flatMap { $0.nodes ?? [] }
		)
		var namesByNode: [Int64: Set<String>] = [:]
		var publicRoadNamesByNode: [Int64: Set<String>] = [:]
		var roads = [WatchMapRoad]()
		for way in response.elements where way.type == "way" {
			guard
				let name = way.tags?["name"],
				let highway = way.tags?["highway"],
				let wayNodes = way.nodes,
				isAllowedWay(way.tags, options: options)
			else {
				continue
			}
			for nodeID in wayNodes {
				namesByNode[nodeID, default: []].insert(name)
				if Self.publicStreetHighways.contains(highway) {
					publicRoadNamesByNode[nodeID, default: []].insert(name)
				}
			}
			roads.append(
				WatchMapRoad(
					id: String(way.id),
					name: name,
					nodeIDs: wayNodes,
					coordinates: wayNodes.compactMap { nodes[$0] },
					highway: highway
				)
			)
		}

		var intersections = namesByNode.compactMap { entry -> WatchIntersectionCandidate? in
			let (nodeID, names) = entry
			guard names.count >= 2, let coordinate = nodes[nodeID] else {
				return nil
			}
			let nodeTags = response.elements.first(where: { $0.type == "node" && $0.id == nodeID })?.tags
			if (isCrossing(nodeTags) || crossingWayNodeIDs.contains(nodeID)),
			   (publicRoadNamesByNode[nodeID]?.count ?? 0) < 2 {
				return nil
			}
			return WatchIntersectionCandidate(
				id: String(nodeID),
				names: names.sorted(),
				coordinate: coordinate
			)
		}
		if options.includeCrossings {
			let streetIntersections = intersections
			let crossingNodeCoordinates = crossingNodeCoordinates(from: response.elements)
			let crossingCandidates = response.elements.compactMap { element -> WatchIntersectionCandidate? in
				guard
					element.type == "node",
					isCrossing(element.tags),
					!isRoadJunctionCrossing(element.id, namesByNode: publicRoadNamesByNode),
					!crossingNodeIsClaimedOnlyByNonPublicWay(element.id, in: response.elements),
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
				guard !shouldSuppressCrossing(
					at: coordinate,
					on: road,
					streetIntersections: streetIntersections,
					crossingNodeCoordinates: crossingNodeCoordinates
				) else {
					return nil
				}
				let anchor = nearestIntersection(
					to: coordinate,
					on: road.name,
					in: streetIntersections
				)
				let title = crossingTitle(on: road.name, near: anchor)
				let candidate = WatchIntersectionCandidate(
					id: "crossing-\(element.id)",
					names: [title],
					coordinate: coordinate,
					associatedRoadNames: [road.name],
					intersectionDetails: intersectionDetails(from: element.tags)
				)
				return candidate
			}
			intersections.append(contentsOf: crossingCandidates)
			let crossingWayCandidates = crossingWayCandidates(
				from: response,
				nodes: nodes,
				roads: roads,
				streetIntersections: streetIntersections
			)
			let existingIDs = Set(intersections.map(\.id))
			intersections.append(contentsOf: crossingWayCandidates.filter { !existingIDs.contains($0.id) })
		}
		return WatchMapDataSet(intersections: intersections, roads: roads)
	}

	func mapData(
		from crossingResponse: WatchOverpassResponse,
		options: WatchMapDetailOptions,
		coreData: WatchMapDataSet
	) -> WatchMapDataSet {
		guard options.includeCrossings else {
			return coreData
		}

		var intersections = coreData.intersections
		let streetIntersections = intersections.filter { !$0.id.hasPrefix("crossing-") }
		let crossingNodeCoordinates = crossingNodeCoordinates(from: crossingResponse.elements)
		let crossingCandidates = crossingResponse.elements.compactMap { element -> WatchIntersectionCandidate? in
			guard
				element.type == "node",
				isCrossing(element.tags),
				!crossingNodeIsClaimedOnlyByNonPublicWay(element.id, in: crossingResponse.elements),
				let coordinate = element.coordinate,
				let road = coreData.roads.first(where: { $0.isPublicStreet && $0.contains(coordinate) })
			else {
				return nil
			}
			guard !shouldSuppressCrossing(
				at: coordinate,
				on: road,
				streetIntersections: streetIntersections,
				crossingNodeCoordinates: crossingNodeCoordinates
			) else {
				return nil
			}
			let anchor = nearestIntersection(
				to: coordinate,
				on: road.name,
				in: streetIntersections
			)
			let title = crossingTitle(on: road.name, near: anchor)
			return WatchIntersectionCandidate(
				id: "crossing-\(element.id)",
				names: [title],
				coordinate: coordinate,
				associatedRoadNames: [road.name],
				intersectionDetails: intersectionDetails(from: element.tags)
			)
		}

		let existingIDs = Set(intersections.map(\.id))
		intersections.append(contentsOf: crossingCandidates.filter { !existingIDs.contains($0.id) })
		let crossingWayCandidates = crossingWayCandidates(
			from: crossingResponse,
			nodes: Dictionary(
				uniqueKeysWithValues: crossingResponse.elements.compactMap { element -> (Int64, CLLocationCoordinate2D)? in
					guard element.type == "node", let coordinate = element.coordinate else {
						return nil
					}
					return (element.id, coordinate)
				}
			),
			roads: coreData.roads,
			streetIntersections: streetIntersections
		)
		let updatedIDs = Set(intersections.map(\.id))
		intersections.append(contentsOf: crossingWayCandidates.filter { !updatedIDs.contains($0.id) })
		return WatchMapDataSet(intersections: intersections, roads: coreData.roads)
	}

	private func crossingNodeCoordinates(from elements: [WatchOverpassElement]) -> [CLLocationCoordinate2D] {
		elements.compactMap { element in
			guard element.type == "node", isCrossing(element.tags) else {
				return nil
			}
			return element.coordinate
		}
	}

	private func crossingNodeIsClaimedOnlyByNonPublicWay(
		_ nodeID: Int64,
		in elements: [WatchOverpassElement]
	) -> Bool {
		let containingHighways = elements.compactMap { element -> String? in
			guard
				element.type == "way",
				element.nodes?.contains(nodeID) == true,
				let highway = element.tags?["highway"]
			else {
				return nil
			}
			return highway
		}
		guard !containingHighways.isEmpty else {
			return false
		}
		return !containingHighways.contains { Self.publicStreetHighways.contains($0) }
	}

	private func shouldSuppressCrossing(
		at coordinate: CLLocationCoordinate2D,
		on road: WatchMapRoad,
		streetIntersections: [WatchIntersectionCandidate],
		crossingNodeCoordinates: [CLLocationCoordinate2D]
	) -> Bool {
		if streetIntersections.contains(where: {
			WatchGeo.distanceMeters(from: $0.coordinate, to: coordinate) < Self.streetIntersectionDuplicateRadiusMeters
		}) {
			return true
		}

		guard
			let anchor = nearestIntersection(to: coordinate, on: road.name, in: streetIntersections),
			anchor.roadNames.count >= 2,
			WatchGeo.distanceMeters(from: anchor.coordinate, to: coordinate) <= Self.cornerCrosswalkAnchorRadiusMeters
		else {
			return false
		}

		let nearbyCrossingCount = crossingNodeCoordinates.filter {
			WatchGeo.distanceMeters(from: $0, to: coordinate) <= Self.cornerCrosswalkClusterRadiusMeters
		}.count
		return nearbyCrossingCount >= Self.cornerCrosswalkClusterCount
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
		roads: [WatchMapRoad]
	) -> WatchMapRoad? {
		if
			let roadNames = namesByNode[nodeID]?.sorted(),
			roadNames.count == 1,
			let roadName = roadNames.first,
			let road = roads.first(where: { $0.name == roadName && $0.isPublicStreet })
		{
			return road
		}
		return roads
			.filter { $0.isPublicStreet && $0.contains(coordinate) }
			.min { $0.minimumDistance(to: coordinate) < $1.minimumDistance(to: coordinate) }
	}

	private func crossingWayCandidates(
		from response: WatchOverpassResponse,
		nodes: [Int64: CLLocationCoordinate2D],
		roads: [WatchMapRoad],
		streetIntersections: [WatchIntersectionCandidate]
	) -> [WatchIntersectionCandidate] {
		response.elements.compactMap { element -> WatchIntersectionCandidate? in
			guard
				element.type == "way",
				isCrossingWay(element.tags),
				hasStrongCrossingEvidence(element.tags),
				let wayNodes = element.nodes,
				!wayNodes.isEmpty
			else {
				return nil
			}
			let coordinates = wayNodes.compactMap { nodes[$0] }
			guard let coordinate = midpoint(of: coordinates) else {
				return nil
			}
			let matchingRoads = roads
				.filter { $0.isPublicStreet && crossingWay(wayNodes: wayNodes, coordinates: coordinates, crosses: $0) }
			guard let road = matchingRoads.min(by: {
				$0.minimumDistance(to: coordinate) < $1.minimumDistance(to: coordinate)
			}) else {
				return nil
			}
			let duplicatesStreetIntersection = streetIntersections.contains {
				WatchGeo.distanceMeters(from: $0.coordinate, to: coordinate) < Self.streetIntersectionDuplicateRadiusMeters
			}
			guard !duplicatesStreetIntersection else {
				return nil
			}
			let anchor = nearestIntersection(to: coordinate, on: road.name, in: streetIntersections)
			return WatchIntersectionCandidate(
				id: "crossing-way-\(element.id)",
				names: [crossingTitle(on: road.name, near: anchor)],
				coordinate: coordinate,
				associatedRoadNames: [road.name],
				intersectionDetails: intersectionDetails(from: element.tags)
			)
		}
	}

	private func crossingWay(
		wayNodes: [Int64],
		coordinates: [CLLocationCoordinate2D],
		crosses road: WatchMapRoad
	) -> Bool {
		if !Set(wayNodes).isDisjoint(with: road.nodeIDs) {
			return true
		}
		return coordinates.contains { road.contains($0) }
	}

	private func midpoint(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
		guard !coordinates.isEmpty else {
			return nil
		}
		let latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
		let longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
		return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	private func crossingTitle(
		on roadName: String,
		near anchor: WatchIntersectionCandidate?
	) -> String {
		guard let anchor else {
			return "Crossing on \(roadName)"
		}
		return "Crossing on \(roadName) near \(anchor.contextLabel(on: roadName))"
	}

	private func nearestIntersection(
		to coordinate: CLLocationCoordinate2D,
		on roadName: String,
		in intersections: [WatchIntersectionCandidate]
	) -> WatchIntersectionCandidate? {
		intersections
			.filter { $0.roadNames.contains(roadName) }
			.compactMap { intersection -> (intersection: WatchIntersectionCandidate, distance: CLLocationDistance)? in
				let distance = WatchGeo.distanceMeters(from: coordinate, to: intersection.coordinate)
				guard distance <= 100 else {
					return nil
				}
				return (intersection, distance)
			}
			.min { $0.distance < $1.distance }?
			.intersection
	}

	private func isAllowedWay(_ tags: [String: String]?, options: WatchMapDetailOptions) -> Bool {
		guard let highway = tags?["highway"] else {
			return false
		}
			let streetHighways = Self.publicStreetHighways
			if streetHighways.contains(highway) {
				return true
			}
		guard options.includeWalkingPaths else {
			return false
		}
		return ["footway", "path", "steps", "bridleway"].contains(highway)
	}

		private func isCrossing(_ tags: [String: String]?) -> Bool {
			tags?["highway"] == "crossing" || tags?["crossing"] != nil || tags?["crossing_ref"] != nil
		}

		private func isCrossingWay(_ tags: [String: String]?) -> Bool {
			tags?["highway"] == "footway" && tags?["footway"] == "crossing"
		}

		private func hasStrongCrossingEvidence(_ tags: [String: String]?) -> Bool {
			guard let tags else {
				return false
			}
			let crossing = tags["crossing"]?.lowercased()
			let markings = tags["crossing:markings"]?.lowercased()
			return crossing == "traffic_signals" ||
				crossing == "marked" ||
				isPositive(tags["crossing:signals"]) ||
				["zebra", "ladder", "yes"].contains(markings)
		}

	private func intersectionDetails(from tags: [String: String]?) -> WatchIntersectionDetails? {
		guard let tags else {
			return nil
		}
		let crossing = tags["crossing"]?.lowercased()
		let details = WatchIntersectionDetails(
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

struct WatchIntersectionFinder {
	func bestMatch(
		for kind: WatchReportKind,
		from context: WatchDeviceContext,
		in candidates: [WatchIntersectionCandidate]
	) -> WatchIntersectionCandidate? {
		switch kind {
		case .nearest:
			return rankedNearest(from: context.coordinate, in: candidates).first
		case .upcoming:
			return nil
		}
	}

	func nearest(
		rank: Int,
		from coordinate: CLLocationCoordinate2D,
		in candidates: [WatchIntersectionCandidate]
	) -> WatchIntersectionCandidate? {
		let ranked = rankedNearest(from: coordinate, in: candidates)
		guard rank > 0, ranked.indices.contains(rank - 1) else {
			return nil
		}
		return ranked[rank - 1]
	}

	func rankedNearest(
		from coordinate: CLLocationCoordinate2D,
		in candidates: [WatchIntersectionCandidate]
	) -> [WatchIntersectionCandidate] {
		let sorted = candidates.sorted {
			WatchGeo.distanceMeters(from: coordinate, to: $0.coordinate)
				< WatchGeo.distanceMeters(from: coordinate, to: $1.coordinate)
		}
		return sorted.reduce(into: []) { unique, candidate in
			let isDuplicate = unique.contains { existing in
				normalizedNames(existing.names) == normalizedNames(candidate.names) &&
					WatchGeo.distanceMeters(from: existing.coordinate, to: candidate.coordinate) < 30
			}
			if !isDuplicate {
				unique.append(candidate)
			}
		}
	}

	func rankedUpcoming(
			from context: WatchDeviceContext,
			in mapData: WatchMapDataSet
		) -> [WatchIntersectionCandidate] {
			upcomingSequence(from: context, in: mapData)
		}

	func upcomingSequence(
			from context: WatchDeviceContext,
			in mapData: WatchMapDataSet
		) -> [WatchIntersectionCandidate] {
		mapData.upcomingRoadSequence(from: context) ?? []
	}

	func upcoming(
		rank: Int,
		from context: WatchDeviceContext,
		in mapData: WatchMapDataSet
	) -> WatchIntersectionCandidate? {
		let ranked = upcomingSequence(from: context, in: mapData)
		guard rank > 0, ranked.indices.contains(rank - 1) else {
			return nil
		}
		return ranked[rank - 1]
	}

	func angleDelta(
		from heading: CLLocationDirection,
		to bearing: CLLocationDirection
	) -> CLLocationDirection {
		let delta = abs(WatchGeo.normalizedDegrees(bearing - heading))
		return min(delta, 360 - delta)
	}

	private func normalizedNames(_ names: [String]) -> Set<String> {
		Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
	}

}

struct WatchNeighborhoodProvider {
	private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
	private let fallbackEndpoints = [
		URL(string: "https://overpass.private.coffee/api/interpreter")!,
		URL(string: "https://maps.mail.ru/osm/tools/overpass/api/interpreter")!
	]
	private let session: URLSession = .shared

	func neighborhoods(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance
	) async throws -> [WatchNeighborhoodCandidate] {
		let endpoints = ([endpoint] + fallbackEndpoints).removingDuplicates()
		for endpoint in endpoints {
			do {
				return try await neighborhoods(from: endpoint, near: coordinate, radiusMeters: radiusMeters)
			} catch {
				guard endpoint != endpoints.last else {
					throw error
				}
			}
		}
		return []
	}

	private func neighborhoods(
		from endpoint: URL,
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance
	) async throws -> [WatchNeighborhoodCandidate] {
		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.timeoutInterval = 12
		request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		request.httpBody = query(near: coordinate, radiusMeters: radiusMeters).data(using: .utf8)

		let (data, urlResponse) = try await session.data(for: request)
		guard let httpResponse = urlResponse as? HTTPURLResponse else {
			throw WatchReportError.invalidResponse
		}
		guard (200..<300).contains(httpResponse.statusCode) else {
			throw WatchReportError.serverError(httpResponse.statusCode)
		}
		let response = try JSONDecoder().decode(WatchOverpassPlaceResponse.self, from: data)
		return WatchNeighborhoodBuilder().candidates(from: response)
	}

	private var userAgent: String {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
		return "Intersector/\(version) (com.marconius.crossStreet.watchkitapp; marco@marconius.com)"
	}

	private func query(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance
	) -> String {
		let radius = Int(radiusMeters.rounded())
		let body = """
		[out:json][timeout:10];
		(
		  node(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["place"~"^(neighbourhood|quarter|suburb|locality)$"]["name"];
		  way(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["place"~"^(neighbourhood|quarter|suburb|locality)$"]["name"];
		  relation(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["place"~"^(neighbourhood|quarter|suburb|locality)$"]["name"];
		  relation(around:\(radius),\(coordinate.latitude),\(coordinate.longitude))["boundary"~"^(place|administrative)$"]["name"]["admin_level"~"^(8|9|10|11)$"];
		);
		out center tags;
		"""
		let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
		let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
		return "data=\(encoded)"
	}
}

struct WatchNeighborhoodCandidate: Equatable, Identifiable {
	var id: String
	var name: String
	var coordinate: CLLocationCoordinate2D
	var kind: WatchNeighborhoodKind

	var priority: Int {
		kind.priority
	}
}

enum WatchNeighborhoodKind: String, Equatable {
	case neighbourhood
	case quarter
	case suburb
	case locality
	case administrative
	case placeBoundary

	var priority: Int {
		switch self {
		case .neighbourhood:
			0
		case .quarter:
			1
		case .placeBoundary:
			2
		case .suburb:
			3
		case .locality:
			4
		case .administrative:
			5
		}
	}
}

struct WatchNeighborhoodBuilder {
	func candidates(from response: WatchOverpassPlaceResponse) -> [WatchNeighborhoodCandidate] {
		var seen = Set<String>()
		return response.elements.compactMap { element -> WatchNeighborhoodCandidate? in
			guard
				let name = element.tags?["name"],
				let coordinate = element.coordinate,
				let kind = kind(for: element.tags)
			else {
				return nil
			}
			let dedupeKey = "\(name.lowercased())-\(kind.rawValue)"
			guard seen.insert(dedupeKey).inserted else {
				return nil
			}
			return WatchNeighborhoodCandidate(
				id: "\(element.type)-\(element.id)",
				name: name,
				coordinate: coordinate,
				kind: kind
			)
		}
	}

	private func kind(for tags: [String: String]?) -> WatchNeighborhoodKind? {
		if let place = tags?["place"], let kind = WatchNeighborhoodKind(rawValue: place) {
			return kind
		}
		switch tags?["boundary"] {
		case "place":
			return .placeBoundary
		case "administrative":
			return .administrative
		default:
			return nil
		}
	}
}

struct WatchNeighborhoodResolver {
	func context(
		from candidates: [WatchNeighborhoodCandidate],
		origin: CLLocationCoordinate2D,
		heading: CLLocationDirection?,
		mode: WatchAreaMode
	) -> WatchNeighborhoodContext {
		guard mode != .off else {
			return WatchNeighborhoodContext(area: nil, toward: nil)
		}
		let area = bestNearbyCandidate(from: candidates, origin: origin)?.name
		let toward: String?
		if mode == .toward, let heading {
			toward = bestTowardCandidate(from: candidates, origin: origin, heading: heading)?.name
		} else {
			toward = nil
		}
		return WatchNeighborhoodContext(area: area, toward: toward)
	}

	private func bestNearbyCandidate(
		from candidates: [WatchNeighborhoodCandidate],
		origin: CLLocationCoordinate2D
	) -> WatchNeighborhoodCandidate? {
		candidates.min {
			nearbyScore($0, origin: origin) < nearbyScore($1, origin: origin)
		}
	}

	private func bestTowardCandidate(
		from candidates: [WatchNeighborhoodCandidate],
		origin: CLLocationCoordinate2D,
		heading: CLLocationDirection
	) -> WatchNeighborhoodCandidate? {
		let matches = candidates.map { candidate in
			let bearing = WatchGeo.bearingDegrees(from: origin, to: candidate.coordinate)
			let delta = WatchIntersectionFinder().angleDelta(from: heading, to: bearing)
			return (candidate: candidate, delta: delta)
		}
		return matches
			.filter { $0.delta <= 70 }
			.min {
				towardScore($0.candidate, origin: origin, delta: $0.delta)
					< towardScore($1.candidate, origin: origin, delta: $1.delta)
			}?
			.candidate
	}

	private func nearbyScore(
		_ candidate: WatchNeighborhoodCandidate,
		origin: CLLocationCoordinate2D
	) -> CLLocationDistance {
		let distance = WatchGeo.distanceMeters(from: origin, to: candidate.coordinate)
		return distance + CLLocationDistance(candidate.priority * 350)
	}

	private func towardScore(
		_ candidate: WatchNeighborhoodCandidate,
		origin: CLLocationCoordinate2D,
		delta: CLLocationDirection
	) -> CLLocationDistance {
		let distance = WatchGeo.distanceMeters(from: origin, to: candidate.coordinate)
		return distance + CLLocationDistance(candidate.priority * 300) + (delta * 20)
	}
}

struct WatchNeighborhoodContext: Equatable {
	var area: String?
	var toward: String?
}

struct WatchOverpassPlaceResponse: Decodable {
	var elements: [WatchOverpassPlaceElement]
}

struct WatchOverpassPlaceElement: Decodable {
	var type: String
	var id: Int64
	var lat: Double?
	var lon: Double?
	var center: WatchOverpassCenter?
	var tags: [String: String]?

	var coordinate: CLLocationCoordinate2D? {
		if let lat, let lon {
			return CLLocationCoordinate2D(latitude: lat, longitude: lon)
		}
		if let center {
			return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
		}
		return nil
	}

	enum CodingKeys: String, CodingKey {
		case type
		case id
		case lat
		case lon
		case center
		case tags
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		type = try container.decode(String.self, forKey: .type)
		id = try container.decode(Int64.self, forKey: .id)
		lat = try container.decodeIfPresent(Double.self, forKey: .lat)
		lon = try container.decodeIfPresent(Double.self, forKey: .lon)
		center = try container.decodeIfPresent(WatchOverpassCenter.self, forKey: .center)
		tags = try container.decodeIfPresent([String: WatchFlexibleString].self, forKey: .tags)?
			.mapValues(\.value)
	}
}

struct WatchOverpassCenter: Decodable, Equatable {
	var lat: Double
	var lon: Double
}

enum WatchGeo {
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

	static func localizedDirection(_ degrees: CLLocationDirection, prefs: WatchAppPrefs) -> String {
		let direction = compassDirection(degrees)
		guard prefs.manhattanSnobMode else {
			return direction
		}
		return manhattanDirection(for: direction)
	}

	static func manhattanDirection(for direction: String) -> String {
		switch direction {
		case "north":
			"uptown"
		case "south":
			"downtown"
		case "east":
			"East Side"
		case "west":
			"West Side"
		case "northeast":
			"uptown toward the East Side"
		case "northwest":
			"uptown toward the West Side"
		case "southeast":
			"downtown toward the East Side"
		case "southwest":
			"downtown toward the West Side"
		default:
			direction
		}
	}

	static func spokenDistance(_ meters: CLLocationDistance, unit: WatchMeasurementUnit = .feet) -> String {
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
		if meters < 500 {
			let rounded = (meters / 10).rounded() * 10
			return "\(Int(rounded)) meters"
		}
		let kilometers = meters / 1_000
		return String(format: "%.1f kilometers", kilometers)
	}
}

actor WatchMapEndpointHealth {
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

extension CLLocationCoordinate2D: @retroactive Equatable {
	public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
		lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
	}
}
