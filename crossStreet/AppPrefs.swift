//
//  AppPrefs.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import Foundation

struct AppPrefs {
	var areaMode = AreaMode.off
	var measurementUnit = MeasurementUnit.feet
	var directionStyle = DirectionStyle.words
	var intersectionWording = IntersectionWording.direct
	var spokenIntersectionCount = SpokenIntersectionCount.one
	var announcementOptions = AnnouncementOptions()
	var mapDetails = MapDetailOptions()
	var haptics = true
	var manhattanSnobMode = false

	nonisolated init(
		areaMode: AreaMode = .off,
		measurementUnit: MeasurementUnit = .feet,
		directionStyle: DirectionStyle = .words,
		intersectionWording: IntersectionWording = .direct,
		spokenIntersectionCount: SpokenIntersectionCount = .one,
		announcementOptions: AnnouncementOptions = AnnouncementOptions(),
		mapDetails: MapDetailOptions = MapDetailOptions(),
		haptics: Bool = true,
		manhattanSnobMode: Bool = false
	) {
		self.areaMode = areaMode
		self.measurementUnit = measurementUnit
		self.directionStyle = directionStyle
		self.intersectionWording = intersectionWording
		self.spokenIntersectionCount = spokenIntersectionCount
		self.announcementOptions = announcementOptions
		self.mapDetails = mapDetails
		self.haptics = haptics
		self.manhattanSnobMode = manhattanSnobMode
	}

	@MainActor
	static func saved(from defaults: UserDefaults = .standard) -> AppPrefs {
		let announcementOptions = AnnouncementOptions.saved(from: defaults)
		let savedAreaMode = AreaMode(rawValue: defaults.string(forKey: "areaMode") ?? "") ?? .near
		return AppPrefs(
			areaMode: savedAreaMode == .off ? .near : savedAreaMode,
			measurementUnit: MeasurementUnit(rawValue: defaults.string(forKey: "measurementUnit") ?? "") ?? .feet,
			directionStyle: DirectionStyle(rawValue: defaults.string(forKey: "directionStyle") ?? "") ?? .words,
			intersectionWording: .direct,
			spokenIntersectionCount: SpokenIntersectionCount(
				rawValue: defaults.integer(forKey: "spokenIntersectionCount")
			) ?? .one,
			announcementOptions: announcementOptions,
			mapDetails: MapDetailOptions(
				includeCrossings: defaults.object(forKey: "includeCrossings") as? Bool ?? false,
				includeWalkingPaths: defaults.object(forKey: "includeWalkingPaths") as? Bool ?? false
			),
			haptics: defaults.object(forKey: "hapticsEnabled") as? Bool ?? true,
			manhattanSnobMode: defaults.object(forKey: "manhattanSnobMode") as? Bool ?? false
		)
	}
}

struct AnnouncementOptions: Equatable, Hashable, Sendable {
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

	@MainActor
	static func saved(from defaults: UserDefaults) -> AnnouncementOptions {
		let savedAreaMode = AreaMode(rawValue: defaults.string(forKey: "areaMode") ?? "")
		let neighborhoodFallback = savedAreaMode.map { $0 != .off } ?? false
		let hasExplicitOptions =
			defaults.object(forKey: "includeAnnouncementDistance") != nil ||
			defaults.object(forKey: "includeAnnouncementDirection") != nil ||
			defaults.object(forKey: "includeAnnouncementNeighborhood") != nil ||
			defaults.object(forKey: "includeIntersectionDetails") != nil

		if hasExplicitOptions {
			return AnnouncementOptions(
				includeDistance: defaults.object(forKey: "includeAnnouncementDistance") as? Bool ?? true,
				includeDirection: defaults.object(forKey: "includeAnnouncementDirection") as? Bool ?? true,
				includeNeighborhood: defaults.object(forKey: "includeAnnouncementNeighborhood") as? Bool ?? neighborhoodFallback,
				includeIntersectionDetails: defaults.object(forKey: "includeIntersectionDetails") as? Bool ?? false
			)
		}

		switch DetailLev(rawValue: defaults.string(forKey: "detailLevel") ?? "") ?? .standard {
		case .minimal:
			return AnnouncementOptions(
				includeDistance: false,
				includeDirection: false,
				includeNeighborhood: false
			)
		case .brief:
			return AnnouncementOptions(includeNeighborhood: false)
		case .standard:
			return AnnouncementOptions(includeNeighborhood: neighborhoodFallback)
		}
	}
}

struct MapDetailOptions: Equatable, Hashable, Sendable {
	var includeCrossings = false
	var includeWalkingPaths = false

	nonisolated init(
		includeCrossings: Bool = false,
		includeWalkingPaths: Bool = false
	) {
		self.includeCrossings = includeCrossings
		self.includeWalkingPaths = includeWalkingPaths
	}

	nonisolated static func == (lhs: MapDetailOptions, rhs: MapDetailOptions) -> Bool {
		lhs.includeCrossings == rhs.includeCrossings &&
			lhs.includeWalkingPaths == rhs.includeWalkingPaths
	}

	nonisolated func hash(into hasher: inout Hasher) {
		hasher.combine(includeCrossings)
		hasher.combine(includeWalkingPaths)
	}
}

enum AreaMode: String, CaseIterable, Identifiable {
	case off
	case near
	case toward

	var id: String { rawValue }
	static let selectableCases: [AreaMode] = [.near, .toward]

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

enum DetailLev: String, CaseIterable, Identifiable {
	case minimal
	case brief
	case standard

	var id: String { rawValue }

	var label: String {
		switch self {
		case .minimal:
			"Minimal"
		case .brief:
			"Brief"
		case .standard:
			"Standard"
		}
	}
}

enum MeasurementUnit: String, CaseIterable, Identifiable {
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

enum DirectionStyle: String, CaseIterable, Identifiable {
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

enum IntersectionWording: String, CaseIterable, Identifiable {
	case direct
	case streetContext

	var id: String { rawValue }
}

enum SpokenIntersectionCount: Int, CaseIterable, Identifiable {
	case one = 1
	case two = 2
	case three = 3

	var id: Int { rawValue }
	var label: String { String(rawValue) }
}
