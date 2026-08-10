//
//  IntersectorTests.swift
//  IntersectorTests
//
//  Created by Marco Salsiccia on 6/7/26.
//

import CoreLocation
import Foundation
import Testing
@testable import Intersector

struct IntersectorTests {
	@Test @MainActor func freshInstallDefaultsNeighborhoodToOff() {
		let suiteName = "IntersectorTests.freshInstall.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer {
			defaults.removePersistentDomain(forName: suiteName)
		}

		let prefs = AppPrefs.saved(from: defaults)

		#expect(AppPrefs().areaMode == .off)
		#expect(prefs.areaMode == .near)
		#expect(!prefs.announcementOptions.includeNeighborhood)
		#expect(AreaMode.selectableCases == [.near, .toward])
	}

	@Test @MainActor func legacyNeighborhoodOffMigratesToDisabledNearbyMode() throws {
		let suiteName = "IntersectorTests.legacyNeighborhood.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		defaults.set(AreaMode.off.rawValue, forKey: "areaMode")

		let prefs = AppPrefs.saved(from: defaults)

		#expect(prefs.areaMode == .near)
		#expect(!prefs.announcementOptions.includeNeighborhood)
	}

	@Test func announcementOptionsCanSpeakIntersectionNameOnly() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .toward
		prefs.intersectionWording = .streetContext
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		let report = OrientReport(
			kind: .upcoming,
			cross: "Amsterdam Avenue and West 94th Street",
			dist: "140 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			crossStreet: "West 94th Street",
			head: "north",
			area: "Upper West Side",
			toward: "Manhattan Valley",
			conf: .medium
		)

		#expect(report.text(with: prefs) == "Upcoming: Amsterdam Avenue and West 94th Street.")
	}

	@Test func intersectionNameOnlyUsesCurrentStreetFirst() async throws {
		var prefs = AppPrefs()
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		let report = OrientReport(
			kind: .nearest,
			cross: "Main Street and Oak Avenue",
			dist: "80 feet",
			relDir: "left",
			relDegrees: 270,
			street: "Oak Avenue",
			crossStreet: "Main Street",
			head: "west",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs) == "Nearest: Oak Avenue and Main Street.")
	}

	@Test @MainActor func savedPreferencesLoadSiriSettings() async throws {
		let suiteName = "IntersectorTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		defaults.set(DetailLev.minimal.rawValue, forKey: "detailLevel")
		defaults.set(true, forKey: "includeAnnouncementDistance")
		defaults.set(false, forKey: "includeAnnouncementDirection")
		defaults.set(true, forKey: "includeAnnouncementNeighborhood")
		defaults.set(true, forKey: "includeIntersectionDetails")
		defaults.set(true, forKey: "includeCrossings")
		defaults.set(true, forKey: "includeWalkingPaths")
		defaults.set(MeasurementUnit.meters.rawValue, forKey: "measurementUnit")
		defaults.set(SpokenIntersectionCount.three.rawValue, forKey: "spokenIntersectionCount")
		defaults.set(true, forKey: "manhattanSnobMode")

		let prefs = AppPrefs.saved(from: defaults)

		#expect(prefs.announcementOptions.includeDistance)
		#expect(!prefs.announcementOptions.includeDirection)
		#expect(prefs.announcementOptions.includeNeighborhood)
		#expect(prefs.announcementOptions.includeIntersectionDetails)
		#expect(prefs.mapDetails.includeCrossings)
		#expect(prefs.mapDetails.includeWalkingPaths)
		#expect(prefs.measurementUnit == .meters)
		#expect(prefs.spokenIntersectionCount == .three)
		#expect(prefs.manhattanSnobMode)
	}

	@Test func myDirectionIntentUsesSavedDirectionWording() async throws {
		var prefs = AppPrefs()

		#expect(MyDirectionIntent.spokenDirection(for: 90, prefs: prefs) == "Facing east.")

		prefs.manhattanSnobMode = true

		#expect(MyDirectionIntent.spokenDirection(for: 90, prefs: prefs) == "Facing East Side.")
	}

	@Test func reportTextCanHideArea() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let report = OrientReport(
			kind: .nearest,
			cross: "Oak Street and Pine Street",
			dist: "80 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Oak Street",
			head: "north",
			area: "Downtown",
			toward: nil,
			conf: .high
		)

		let text = report.text(with: prefs)

		#expect(text.contains("Nearest:"))
		#expect(text.contains("Oak Street and Pine Street"))
		#expect(text.contains("80 feet ahead"))
		#expect(!text.contains("On Oak Street"))
		#expect(!text.contains("appears"))
		#expect(!text.contains("Downtown"))
	}

	@Test func reportTextUsesClockFaceDirection() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .toward
		prefs.directionStyle = .clockFace
		let report = OrientReport(
			kind: .upcoming,
			cross: "Mission Street and 6th Street",
			dist: "140 feet",
			relDir: "ahead and right",
			relDegrees: 45,
			street: "Mission Street",
			head: "northeast",
			area: nil,
			toward: "Civic Center",
			conf: .high
		)

		let text = report.text(with: prefs)

		#expect(text == "Upcoming: Mission Street and 6th Street, about 140 feet at 2 o'clock toward Civic Center.")
	}

	@Test func manhattanSnobModeDoesNotOverrideRelativeWordReports() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.manhattanSnobMode = true
		let report = OrientReport(
			kind: .nearest,
			cross: "Amsterdam Avenue and West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs) == "Nearest: Amsterdam Avenue and West 94th Street, about 120 feet ahead.")
		#expect(Geo.localizedDirection(180, prefs: prefs) == "Downtown")
	}

	@Test func cardinalDirectionStyleUsesGeographicBearing() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.directionStyle = .cardinal
		let report = OrientReport(
			kind: .upcoming,
			cross: "Riverside Drive and West 100th Street",
			dist: "300 feet",
			relDir: "ahead and left",
			relDegrees: 315,
			street: "Riverside Drive",
			head: "northwest",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(
			report.text(with: prefs) ==
				"Upcoming: Riverside Drive and West 100th Street, about 300 feet northwest."
		)
	}

	@Test func cardinalDirectionStyleUsesManhattanWordingWhenEnabled() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.directionStyle = .cardinal
		prefs.manhattanSnobMode = true
		let report = OrientReport(
			kind: .nearest,
			cross: "Amsterdam Avenue and West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(
			report.text(with: prefs) ==
				"Nearest: Amsterdam Avenue and West 94th Street, about 120 feet toward Uptown."
		)
	}

	@Test func savedWordsDirectionStyleRemainsRelative() {
		#expect(DirectionStyle(rawValue: "words") == .words)
		#expect(DirectionStyle.words.label == "Relative")
	}

	@Test func manhattanSnobModeDoesNotOverrideClockFaceReports() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.directionStyle = .clockFace
		prefs.manhattanSnobMode = true
		let report = OrientReport(
			kind: .upcoming,
			cross: "Amsterdam Avenue and West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs) == "Upcoming: Amsterdam Avenue and West 94th Street, about 120 feet at 12 o'clock.")
	}

	@Test func rankedReportTextIncludesRankPrefix() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let report = OrientReport(
			kind: .nearest,
			cross: "Amsterdam Avenue and West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs, rank: 3) == "3rd Nearest: Amsterdam Avenue and West 94th Street, about 120 feet ahead.")
	}

	@Test func rankedMinimalReportTextIncludesRankPrefix() async throws {
		var prefs = AppPrefs()
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		let report = OrientReport(
			kind: .upcoming,
			cross: "Amsterdam Avenue and West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			crossStreet: "West 94th Street",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs, rank: 2) == "2nd Upcoming: Amsterdam Avenue and West 94th Street.")
	}

	@Test func multipleNameOnlyReportsKeepNearestPrefix() async throws {
		var prefs = AppPrefs()
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		let reports = IntersectionReportList(reports: [
			OrientReport(
				kind: .nearest,
				cross: "Main Street and First Street",
				dist: "100 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Main Street",
				crossStreet: "First Street",
				head: "north",
				area: nil,
				toward: nil,
				conf: .high
			),
			OrientReport(
				kind: .nearest,
				cross: "Main Street and Second Street",
				dist: "200 feet",
				relDir: "behind",
				relDegrees: 180,
				street: "Main Street",
				crossStreet: "Second Street",
				head: "south",
				area: nil,
				toward: nil,
				conf: .high
			)
		])

		#expect(reports.text(with: prefs) == "Nearest: Main Street and First Street, Second Street.")
	}

	@Test func multipleNameOnlyReportsKeepUpcomingPrefix() async throws {
		var prefs = AppPrefs()
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		let reports = IntersectionReportList(reports: [
			OrientReport(
				kind: .upcoming,
				cross: "Oak Avenue and Third Street",
				dist: "100 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Oak Avenue",
				crossStreet: "Third Street",
				head: "north",
				area: nil,
				toward: nil,
				conf: .high
			),
			OrientReport(
				kind: .upcoming,
				cross: "Oak Avenue and Fourth Street",
				dist: "200 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Oak Avenue",
				crossStreet: "Fourth Street",
				head: "north",
				area: nil,
				toward: nil,
				conf: .high
			)
		])

		#expect(reports.text(with: prefs) == "Upcoming: Oak Avenue and Third Street, Fourth Street.")
	}

	@Test func streetContextNamesCurrentStreetBeforeCrossStreet() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.intersectionWording = .streetContext
		let report = OrientReport(
			kind: .upcoming,
			cross: "E 20th Avenue and Main Street",
			dist: "140 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "E 20th Avenue",
			crossStreet: "Main Street",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs) == "Upcoming: On E 20th Avenue at Main Street, about 140 feet ahead.")
	}

	@Test func streetContextFallsBackToDirectWordingWithoutCurrentStreet() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.intersectionWording = .streetContext
		let report = OrientReport(
			kind: .nearest,
			cross: "E 20th Avenue and Main Street",
			dist: "80 feet",
			relDir: "left",
			relDegrees: 270,
			street: nil,
			head: "west",
			area: nil,
			toward: nil,
			conf: .high
		)

		#expect(report.text(with: prefs) == "Nearest: E 20th Avenue and Main Street, about 80 feet left.")
	}

	@Test func reportTextOmitsDynamicConfidenceWording() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let report = OrientReport(
			kind: .upcoming,
			cross: "Oak Street and Pine Street",
			dist: "100 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Oak Street",
			head: "north",
			area: nil,
			toward: nil,
			conf: .medium
		)

		let text = report.text(with: prefs)

		#expect(text == "Upcoming: Oak Street and Pine Street, about 100 feet ahead.")
		#expect(!text.localizedCaseInsensitiveContains("estimate"))
		#expect(!text.localizedCaseInsensitiveContains("uncertain"))
	}

	@Test func announcementOptionsCanOmitNeighborhoodContext() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .toward
		prefs.announcementOptions.includeNeighborhood = false
		let report = OrientReport(
			kind: .upcoming,
			cross: "Mission Street and 6th Street",
			dist: "140 feet",
			relDir: "ahead and right",
			relDegrees: 45,
			street: "Mission Street",
			head: "northeast",
			area: "SoMa",
			toward: "Civic Center",
			conf: .high
		)

		let text = report.text(with: prefs)

		#expect(text == "Upcoming: Mission Street and 6th Street, about 140 feet ahead and right.")
	}

	@Test func announcementOptionsCanIncludeNeighborhoodContext() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .toward
		prefs.announcementOptions.includeNeighborhood = true
		let report = OrientReport(
			kind: .upcoming,
			cross: "Mission Street and 6th Street",
			dist: "140 feet",
			relDir: "ahead and right",
			relDegrees: 45,
			street: "Mission Street",
			head: "northeast",
			area: "SoMa",
			toward: "Civic Center",
			conf: .high
		)

		let text = report.text(with: prefs)

		#expect(text == "Upcoming: Mission Street and 6th Street, about 140 feet ahead and right toward Civic Center.")
	}

	@Test func intersectionDetailsAreSpokenWhenEnabled() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions.includeIntersectionDetails = true
		let report = OrientReport(
			kind: .nearest,
			cross: "Crossing on Main Street near Oak Street",
			dist: "90 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Main Street",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high,
			intersectionDetails: IntersectionDetails(
				isSignalized: true,
				hasPedestrianIsland: true
			)
		)

		let text = report.text(with: prefs)

		#expect(
			text ==
				"Nearest: Crossing on Main Street near Oak Street, about 90 feet ahead, signalized crossing, pedestrian island."
		)
	}

	@Test func intersectionDetailsAreOmittedWhenDisabled() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions.includeIntersectionDetails = false
		let report = OrientReport(
			kind: .nearest,
			cross: "Crossing on Main Street near Oak Street",
			dist: "90 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Main Street",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high,
			intersectionDetails: IntersectionDetails(
				isSignalized: true,
				hasPedestrianIsland: true
			)
		)

		let text = report.text(with: prefs)

		#expect(text == "Nearest: Crossing on Main Street near Oak Street, about 90 feet ahead.")
	}

	@Test func crossingTagsCreateIntersectionDetails() async throws {
		let response = OverpassResponse(elements: [
			OverpassElement(
				type: "node",
				id: 1,
				lat: 37.0,
				lon: -122.0,
				nodes: nil,
				tags: nil
			),
			OverpassElement(
				type: "node",
				id: 2,
				lat: 37.0005,
				lon: -122.0,
				nodes: nil,
				tags: [
					"highway": "crossing",
					"crossing": "traffic_signals",
					"crossing:island": "yes"
				]
			),
			OverpassElement(
				type: "node",
				id: 3,
				lat: 37.001,
				lon: -122.0,
				nodes: nil,
				tags: nil
			),
			OverpassElement(
				type: "way",
				id: 10,
				lat: nil,
				lon: nil,
				nodes: [1, 2, 3],
				tags: [
					"highway": "residential",
					"name": "Main Street"
				]
			),
			OverpassElement(
				type: "way",
				id: 11,
				lat: nil,
				lon: nil,
				nodes: [1],
				tags: [
					"highway": "residential",
					"name": "Oak Street"
				]
			)
		])

		let mapData = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true)
		)
		let crossing = try #require(mapData.intersections.first { $0.id == "crossing-2" })

		#expect(crossing.intersectionDetails?.isSignalized == true)
		#expect(crossing.intersectionDetails?.hasPedestrianIsland == true)
	}

	@Test func multipleReportsShareMatchingNeighborhoodTextOnce() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .near
		prefs.announcementOptions.includeNeighborhood = true
		let reports = IntersectionReportList(reports: [
			OrientReport(
				kind: .upcoming,
				cross: "Oak Street and First Street",
				dist: "100 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Oak Street",
				head: "north",
				area: "Downtown",
				toward: nil,
				conf: .medium
			),
			OrientReport(
				kind: .upcoming,
				cross: "Oak Street and Second Street",
				dist: "200 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Oak Street",
				head: "north",
				area: "Downtown",
				toward: nil,
				conf: .medium
			)
		])

		let text = reports.text(with: prefs)

		#expect(
			text ==
				"Upcoming: Oak Street and First Street, about 100 feet ahead. Oak Street and Second Street, about 200 feet ahead in Downtown."
		)
	}

	@Test func multipleReportsKeepDifferentNeighborhoodTextWithEachReport() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .near
		prefs.announcementOptions.includeNeighborhood = true
		let reports = IntersectionReportList(reports: [
			OrientReport(
				kind: .upcoming,
				cross: "Oak Street and First Street",
				dist: "100 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Oak Street",
				head: "north",
				area: "Downtown",
				toward: nil,
				conf: .medium
			),
			OrientReport(
				kind: .upcoming,
				cross: "Oak Street and Second Street",
				dist: "200 feet",
				relDir: "ahead",
				relDegrees: 0,
				street: "Oak Street",
				head: "north",
				area: "Uptown",
				toward: nil,
				conf: .medium
			)
		])

		let text = reports.text(with: prefs)

		#expect(
			text ==
				"Upcoming: Oak Street and First Street, about 100 feet ahead in Downtown. Oak Street and Second Street, about 200 feet ahead in Uptown."
		)
	}

	@Test func distanceTextCanUseMeters() async throws {
		#expect(Geo.spokenDistance(42, unit: .meters) == "40 meters")
		#expect(Geo.spokenDistance(1_200, unit: .meters) == "1.2 kilometers")
	}

	@Test func pointedReportOmitsRedundantDirectionText() async throws {
		let report = OrientReport(
			kind: .scan,
			cross: "Valencia Street and 16th Street",
			dist: "220 feet",
			relDir: nil,
			relDegrees: nil,
			street: "Valencia Street",
			head: "north",
			area: nil,
			toward: nil,
			conf: .high
		)

		let text = report.text(with: AppPrefs())

		#expect(text == "Pointed: Valencia Street and 16th Street, about 220 feet.")
		#expect(!text.localizedCaseInsensitiveContains("where the phone is pointing"))
	}

	@Test func currentStreetMatchingIgnoresUnrelatedCloserRoad() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0, longitude: -122.001),
						CLLocationCoordinate2D(latitude: 37.0, longitude: -121.999)
					]
				),
				MapRoad(
					id: "pine",
					name: "Pine Street",
					nodeIDs: [3, 4],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0005, longitude: -122.0005),
						CLLocationCoordinate2D(latitude: 37.0005, longitude: -121.9995)
					]
				),
				MapRoad(
					id: "service",
					name: "Service Road",
					nodeIDs: [5],
					coordinates: [origin]
				)
			]
		)

		let street = mapData.nearestRoadName(
			to: origin,
			matching: ["Oak Street", "Pine Street"]
		)

		#expect(street == "Oak Street")
	}

	@Test func roadDistanceUsesFullSegmentBetweenNodes() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let road = MapRoad(
			id: "oak",
			name: "Oak Street",
			nodeIDs: [1, 2],
			coordinates: [
				CLLocationCoordinate2D(latitude: 37.0, longitude: -122.001),
				CLLocationCoordinate2D(latitude: 37.0, longitude: -121.999)
			]
		)

		#expect(road.minimumDistance(to: origin) < 1)
	}

	@Test func spokenIntersectionsFindsBothSidesAndFollowingStreet() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "south",
					names: ["Amsterdam Avenue", "West 93rd Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "north",
					names: ["Amsterdam Avenue", "West 94th Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "following",
					names: ["Amsterdam Avenue", "West 95th Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "amsterdam",
					name: "Amsterdam Avenue",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				)
			]
		)
		let context = DeviceContext(
			coordinate: origin,
			headingDegrees: 0,
			horizontalAccuracy: 10
		)

		let position = try #require(mapData.streetPosition(from: context, count: .three))
		var briefPrefs = AppPrefs()
		briefPrefs.announcementOptions.includeNeighborhood = false
		var minimalPrefs = AppPrefs()
		minimalPrefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)

		#expect(position.boundaries.map(\.id) == ["south", "north"])
		#expect(position.following?.id == "following")
		#expect(position.isOnStreet)
		#expect(
			position.text(with: briefPrefs) ==
				"On Amsterdam Avenue between West 93rd Street and West 94th Street, toward West 95th Street."
		)
		#expect(
			position.text(with: minimalPrefs) ==
				"Amsterdam Avenue and West 93rd Street, West 94th Street, West 95th Street."
		)
	}

	@Test func intersectionNameOnlySpokenIntersectionsKeepsUnrelatedIntersectionsComplete() async throws {
		var prefs = AppPrefs()
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		let position = StreetPositionContext(
			streetName: "Foothill Boulevard",
			boundaries: [
				IntersectionCandidate(
					id: "first",
					names: ["Foothill Boulevard", "Frazier Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -118.0)
				),
				IntersectionCandidate(
					id: "second",
					names: ["Stanley Avenue", "Talbot Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 34.001, longitude: -118.0)
				)
			],
			following: nil,
			isOnStreet: true
		)

		#expect(
			position.text(with: prefs) ==
				"Foothill Boulevard and Frazier Avenue, Stanley Avenue and Talbot Avenue."
		)
	}

	@Test func spokenIntersectionsUsesAlongWhenAwayFromStreet() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -121.999)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "south",
					names: ["Central Park West", "West 93rd Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.997, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "north",
					names: ["Central Park West", "West 94th Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.003, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "park-west",
					name: "Central Park West",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				)
			]
		)
		let context = DeviceContext(
			coordinate: origin,
			headingDegrees: nil,
			horizontalAccuracy: 10
		)

		let position = try #require(mapData.streetPosition(from: context, count: .two))

		#expect(!position.isOnStreet)
		#expect(
			position.text(with: AppPrefs()) ==
				"Along Central Park West between West 93rd Street and West 94th Street."
		)
	}

	@Test func dependableDirectionPrefersAccurateWalkingCourse() async throws {
		let moving = DeviceContext(
			coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
			headingDegrees: 180,
			courseDegrees: 0,
			courseAccuracy: 10,
			speedMetersPerSecond: 1,
			horizontalAccuracy: 10
		)
		let uncertainCourse = DeviceContext(
			coordinate: moving.coordinate,
			headingDegrees: 180,
			courseDegrees: 0,
			courseAccuracy: 90,
			speedMetersPerSecond: 1,
			horizontalAccuracy: 10
		)

		#expect(moving.dependableTravelDirection == 0)
		#expect(uncertainCourse.dependableTravelDirection == 180)
	}

	@Test func scanMatchIgnoresAlignedIntersectionsBeyondImmediateRange() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let context = DeviceContext(coordinate: origin, headingDegrees: 0)
		let candidates = [
			IntersectionCandidate(
				id: "far-ahead",
				names: ["Oak Street", "Far Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
			),
			IntersectionCandidate(
				id: "near-left",
				names: ["Oak Street", "Near Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.0008, longitude: -122.00005)
			)
		]

		let match = IntersectionFinder().scanMatch(from: context, in: candidates)

		#expect(match?.candidate.id == "near-left")
	}

	@Test func multipleUpcomingIntersectionsFollowPhoneHeading() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "behind",
					names: ["Oak Street", "Behind Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.9995, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "first-ahead",
					names: ["Oak Street", "First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "second-ahead",
					names: ["Oak Street", "Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				)
			]
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		prefs.spokenIntersectionCount = .two

		let text = try await service.spokenText(.upcoming, prefs: prefs)

		#expect(text == "Oak Street and First Street, Second Street.")
		#expect(!text.contains("Behind Street"))
	}

	@Test func upcomingIntersectionsFollowCurrentRoadProgressBeforeNearbyConeCandidates() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "nearby-diagonal",
					names: ["Pine Street", "Diagonal Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0006, longitude: -121.9998)
				),
				IntersectionCandidate(
					id: "first-ahead",
					names: ["Oak Street", "First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "second-ahead",
					names: ["Oak Street", "Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "third-ahead",
					names: ["Oak Street", "Third Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.003, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				),
				MapRoad(
					id: "pine",
					name: "Pine Street",
					nodeIDs: [3, 4],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -121.9998),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -121.9998)
					]
				),
				MapRoad(
					id: "diagonal",
					name: "Diagonal Street",
					nodeIDs: [5, 6],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0006, longitude: -122.001),
						CLLocationCoordinate2D(latitude: 37.0006, longitude: -121.9998)
					]
				)
			]
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		prefs.spokenIntersectionCount = .three

		let text = try await service.spokenText(.upcoming, prefs: prefs)
		let thirdReport = try await service.report(.upcoming, rank: 3, prefs: prefs)

		#expect(text == "Oak Street and First Street, Second Street, Third Street.")
		#expect(!text.contains("Diagonal Street"))
		#expect(thirdReport.cross == "Oak Street and Third Street")
	}

	@Test func currentRoadUpcomingRejectsRoadProgressBehindPhoneHeading() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "behind-progress",
					names: ["Oak Street", "Behind Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "ahead",
					names: ["Oak Street", "Ahead Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0)
					]
				)
			]
		)

		let ranked = IntersectionFinder().rankedUpcoming(
			from: DeviceContext(coordinate: origin, headingDegrees: 0),
			in: mapData
		)

		#expect(ranked.map(\.id) == ["ahead"])
	}

	@Test func currentRoadUpcomingUsesPhoneHeadingInsteadOfWalkingCourse() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "north",
					names: ["Oak Street", "North Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "south",
					names: ["Oak Street", "South Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
					]
				)
			]
		)
		let context = DeviceContext(
			coordinate: origin,
			headingDegrees: 0,
			courseDegrees: 180,
			courseAccuracy: 5,
			speedMetersPerSecond: 1.2,
			horizontalAccuracy: 10
		)

		let ranked = IntersectionFinder().rankedUpcoming(from: context, in: mapData)

		#expect(ranked.map(\.id) == ["north"])
	}

	@Test func upcomingFollowsCurvedRoadAndNeverFillsFromNearbyStreet() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let first = CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
		let second = CLLocationCoordinate2D(latitude: 37.001, longitude: -121.999)
		let third = CLLocationCoordinate2D(latitude: 37.002, longitude: -121.999)
		let sameNameBranch = CLLocationCoordinate2D(latitude: 37.0005, longitude: -121.9995)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "first-on-road",
					names: ["Oak Street", "First Street"],
					coordinate: first
				),
				IntersectionCandidate(
					id: "second-on-road",
					names: ["Oak Street", "Second Street"],
					coordinate: second
				),
				IntersectionCandidate(
					id: "third-on-road",
					names: ["Oak Street", "Third Street"],
					coordinate: third
				),
				IntersectionCandidate(
					id: "off-road",
					names: ["Pine Avenue", "Nearby Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0005, longitude: -121.9998)
				),
				IntersectionCandidate(
					id: "same-name-branch",
					names: ["Oak Street", "Branch Street"],
					coordinate: sameNameBranch
				)
			],
			roads: [
				MapRoad(
					id: "pine-crossing",
					name: "Pine Avenue",
					nodeIDs: [10, 11],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0, longitude: -122.001),
						CLLocationCoordinate2D(latitude: 37.0, longitude: -121.999)
					]
				),
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2, 3, 4],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0),
						first,
						second,
						third
					]
				),
				MapRoad(
					id: "oak-branch",
					name: "Oak Street",
					nodeIDs: [3, 5],
					coordinates: [second, sameNameBranch]
				)
			]
		)

		let sequence = IntersectionFinder().upcomingSequence(
			from: DeviceContext(coordinate: origin, headingDegrees: 0),
			in: mapData
		)

		#expect(sequence.map(\.id) == ["first-on-road", "second-on-road", "third-on-road"])
	}

	@Test func upcomingSequenceCanIncludeForwardCrossingOnRoad() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "first-on-road",
					names: ["Oak Street", "First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "crossing-oak-1",
					names: ["Oak Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0015, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "third-on-road",
					names: ["Oak Street", "Third Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2, 3, 4, 5],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.0015, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.003, longitude: -122.0)
					]
				)
			]
		)

		let sequence = IntersectionFinder().upcomingSequence(
			from: DeviceContext(coordinate: origin, headingDegrees: 0),
			in: mapData
		)

		#expect(sequence.map(\.id) == ["first-on-road", "crossing-oak-1", "third-on-road"])
	}

	@Test func cachedRankedUpcomingDoesNotSurviveHeadingChange() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "north-first",
					names: ["Oak Street", "North First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "north-second",
					names: ["Oak Street", "North Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "south-first",
					names: ["Oak Street", "South First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "south-second",
					names: ["Oak Street", "South Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 36.998, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				)
			]
		)
		let service = OrientSvc(
			locationProvider: SequentialLocationProvider(contexts: [
				DeviceContext(coordinate: origin, headingDegrees: 0),
				DeviceContext(coordinate: origin, headingDegrees: 180)
			]),
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)

		_ = try await service.report(.upcoming, prefs: prefs)
		let secondReport = try await service.report(.upcoming, rank: 2, prefs: prefs)

		#expect(secondReport.cross == "Oak Street and South Second Street")
	}

	@Test func splitCrossStreetsUseHeadingToSpeakLeftThenRight() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "stanley",
					names: ["Foothill Boulevard", "Stanley Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.00008)
				),
				IntersectionCandidate(
					id: "talbot",
					names: ["Foothill Boulevard", "Talbot Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -121.99992)
				),
				IntersectionCandidate(
					id: "next",
					names: ["Foothill Boulevard", "Next Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "foothill",
					name: "Foothill Boulevard",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				),
				MapRoad(
					id: "stanley",
					name: "Stanley Avenue",
					nodeIDs: [3, 4],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.001, longitude: -122.00008),
						CLLocationCoordinate2D(latitude: 37.001, longitude: -122.001)
					]
				),
				MapRoad(
					id: "talbot",
					name: "Talbot Avenue",
					nodeIDs: [5, 6],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.001, longitude: -121.99992),
						CLLocationCoordinate2D(latitude: 37.001, longitude: -121.999)
					]
				),
				MapRoad(
					id: "next",
					name: "Next Street",
					nodeIDs: [7, 8],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.002, longitude: -121.999)
					]
				)
			]
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		prefs.spokenIntersectionCount = .two

		let text = try await service.spokenText(.upcoming, prefs: prefs)

		#expect(text == "Foothill Boulevard and Stanley Avenue and Talbot Avenue, Next Street.")
	}

	@Test func scanReportUsesSplitCrossStreetAnnouncementWithinImmediateRange() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "stanley",
					names: ["Foothill Boulevard", "Stanley Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0008, longitude: -122.00008)
				),
				IntersectionCandidate(
					id: "talbot",
					names: ["Foothill Boulevard", "Talbot Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0008, longitude: -121.99992)
				),
				IntersectionCandidate(
					id: "far",
					names: ["Foothill Boulevard", "Far Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "foothill",
					name: "Foothill Boulevard",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.995, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.005, longitude: -122.0)
					]
				),
				MapRoad(
					id: "stanley",
					name: "Stanley Avenue",
					nodeIDs: [3, 4],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0008, longitude: -122.00008),
						CLLocationCoordinate2D(latitude: 37.0008, longitude: -122.001)
					]
				),
				MapRoad(
					id: "talbot",
					name: "Talbot Avenue",
					nodeIDs: [5, 6],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0008, longitude: -121.99992),
						CLLocationCoordinate2D(latitude: 37.0008, longitude: -121.999)
					]
				),
				MapRoad(
					id: "far",
					name: "Far Street",
					nodeIDs: [7, 8],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.002, longitude: -121.999)
					]
				)
			]
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)

		let text = try await service.spokenText(.scan, prefs: prefs)

		#expect(text == "Foothill Boulevard and Stanley Avenue and Talbot Avenue.")
		#expect(!text.contains("Far Street"))
	}

	@Test func rankedUpcomingReportSpeaksOnlyRequestedIntersection() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "first-ahead",
					names: ["Oak Street", "First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "second-ahead",
					names: ["Oak Street", "Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "third-ahead",
					names: ["Oak Street", "Third Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.003, longitude: -122.0)
				)
			],
			roads: [northboundOakRoad(near: origin)]
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)
		prefs.spokenIntersectionCount = .three

		let report = try await service.report(.upcoming, rank: 2, prefs: prefs)
		let text = report.text(with: prefs, rank: 2)

		#expect(text == "2nd Upcoming: Oak Street and Second Street.")
		#expect(!text.contains("First Street"))
		#expect(!text.contains("Third Street"))
	}

	@Test func explicitRankedUpcomingUsesFocusedRoadData() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapDataClient = RankedFocusedMapDataClient()
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: mapDataClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)

		_ = try await service.report(.upcoming, prefs: prefs)
		let thirdReport = try await service.report(.upcoming, rank: 3, prefs: prefs)

		#expect(thirdReport.cross == "Oak Street and Third Street")
		#expect(await mapDataClient.focusedRoadRequestCount == 1)
	}

	@Test func rankedUpcomingReusesLastUpcomingSnapshotWhenHeadingStillMatches() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "first-ahead",
					names: ["Oak Street", "First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "second-ahead",
					names: ["Oak Street", "Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "east",
					names: ["Oak Street", "East Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -121.999)
				)
			],
			roads: [northboundOakRoad(near: origin)]
		)
		let locationProvider = SequentialLocationProvider(contexts: [
			DeviceContext(coordinate: origin, headingDegrees: 0),
			DeviceContext(coordinate: origin, headingDegrees: 0)
		])
		let service = OrientSvc(
			locationProvider: locationProvider,
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)

		let firstReport = try await service.report(.upcoming, prefs: prefs)
		let secondReport = try await service.report(.upcoming, rank: 2, prefs: prefs)

		#expect(firstReport.cross == "Oak Street and First Street")
		#expect(secondReport.cross == "Oak Street and Second Street")
		#expect(await locationProvider.requestCount == 2)
	}

	@Test func upcomingRetriesASettledHeadingWithoutReloadingMapData() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let locationProvider = SequentialLocationProvider(contexts: [
			DeviceContext(coordinate: origin, headingDegrees: 90),
			DeviceContext(coordinate: origin, headingDegrees: 0)
		])
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: rankedStreetData(origin: origin),
			immediateData: rankedStreetData(origin: origin)
		)
		let service = OrientSvc(
			locationProvider: locationProvider,
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off

		let report = try await service.report(.upcoming, prefs: prefs)

		#expect(report.cross == "Oak Street and First Street")
		#expect(await locationProvider.requestCount == 2)
		#expect(await mapClient.immediateOptions == [MapDetailOptions()])
		#expect(await mapClient.fullOptions.isEmpty)
	}

	@Test func secondAndThirdUpcomingDoNotReturnSameIntersection() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "first-ahead",
					names: ["Oak Street", "First Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "second-ahead",
					names: ["Oak Street", "Second Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "third-ahead",
					names: ["Oak Street", "Third Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.003, longitude: -122.0)
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.004, longitude: -122.0)
					]
				)
			]
		)
		let locationProvider = SequentialLocationProvider(contexts: [
			DeviceContext(coordinate: origin, headingDegrees: 0),
			DeviceContext(coordinate: origin, headingDegrees: 0),
			DeviceContext(coordinate: origin, headingDegrees: 0)
		])
		let service = OrientSvc(
			locationProvider: locationProvider,
			mapDataClient: StaticMapDataClient(data: mapData),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.announcementOptions = AnnouncementOptions(
			includeDistance: false,
			includeDirection: false,
			includeNeighborhood: false
		)

		_ = try await service.report(.upcoming, prefs: prefs)
		let secondReport = try await service.report(.upcoming, rank: 2, prefs: prefs)
		let thirdReport = try await service.report(.upcoming, rank: 3, prefs: prefs)

		#expect(secondReport.cross != thirdReport.cross)
		#expect(secondReport.cross == "Oak Street and Second Street")
		#expect(thirdReport.cross == "Oak Street and Third Street")
	}

	@Test func upcomingRequestsFreshHeadingButNearestDoesNot() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let locationProvider = FreshHeadingRecordingLocationProvider(
			context: DeviceContext(coordinate: origin, headingDegrees: 0)
		)
		let service = OrientSvc(
			locationProvider: locationProvider,
			mapDataClient: StaticMapDataClient(
				data: MapDataSet(
					intersections: [
						IntersectionCandidate(
							id: "north",
							names: ["Oak Street", "North Street"],
							coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
						)
					],
					roads: [northboundOakRoad(near: origin)]
				)
			),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off

		_ = try await service.report(.nearest, prefs: prefs)
		_ = try await service.report(.upcoming, prefs: prefs)

		#expect(await locationProvider.freshHeadingRequests == [false, true])
	}

	@Test func firstNearestCanReturnImmediateCrossingWhenCrossingsEnabled() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: rankedStreetData(origin: origin),
			immediateData: crossingFirstData(origin: origin)
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(context: DeviceContext(coordinate: origin, headingDegrees: 0)),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)

		let report = try await service.report(.nearest, prefs: prefs)

		#expect(report.cross == "Crossing on Oak Street near Pine Street")
		#expect(await mapClient.immediateOptions == [MapDetailOptions(includeCrossings: true)])
		#expect(await mapClient.fullOptions.isEmpty)
	}

	@Test func firstNearestUsesImmediateCoreLookupWhenCrossingsAreOff() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: rankedStreetData(origin: origin),
			immediateData: rankedStreetData(origin: origin)
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(context: DeviceContext(coordinate: origin, headingDegrees: 0)),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions()

		let report = try await service.report(.nearest, prefs: prefs)

		#expect(report.cross == "Oak Street and First Street")
		#expect(await mapClient.immediateOptions == [MapDetailOptions()])
		#expect(await mapClient.fullOptions.isEmpty)
	}

	@Test func firstUpcomingPreservesEnabledWalkingPathOptions() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: crossingFirstData(origin: origin),
			immediateData: crossingFirstData(origin: origin)
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(context: DeviceContext(coordinate: origin, headingDegrees: 0)),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)

		let report = try await service.report(.upcoming, prefs: prefs)

		#expect(report.cross == "Crossing on Oak Street near Pine Street")
		#expect(await mapClient.immediateOptions.isEmpty)
		#expect(await mapClient.fullOptions == [MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)])
	}

	@Test func firstUpcomingCanFollowANamedWalkingPathWhenEnabled() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let junction = CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
		let pathData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "garden-lake",
					names: ["Garden Path", "Lake Path"],
					coordinate: junction
				)
			],
			roads: [
				MapRoad(
					id: "garden-path",
					name: "Garden Path",
					nodeIDs: [1, 2, 3],
					coordinates: [
						CLLocationCoordinate2D(latitude: 36.999, longitude: -122.0),
						origin,
						junction
					]
				),
				MapRoad(
					id: "lake-path",
					name: "Lake Path",
					nodeIDs: [4, 3, 5],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.001, longitude: -122.001),
						junction,
						CLLocationCoordinate2D(latitude: 37.001, longitude: -121.999)
					]
				)
			]
		)
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: pathData,
			immediateData: MapDataSet(intersections: [], roads: [])
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(coordinate: origin, headingDegrees: 0)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions(includeWalkingPaths: true)

		let report = try await service.report(.upcoming, prefs: prefs)

		#expect(report.cross == "Garden Path and Lake Path")
		#expect(await mapClient.immediateOptions.isEmpty)
		#expect(await mapClient.fullOptions == [MapDetailOptions(includeWalkingPaths: true)])
	}

	@Test func firstUpcomingUsesImmediateCoreLookupWhenCrossingsAreOff() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: rankedStreetData(origin: origin),
			immediateData: rankedStreetData(origin: origin)
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(context: DeviceContext(coordinate: origin, headingDegrees: 0)),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions()

		let report = try await service.report(.upcoming, prefs: prefs)

		#expect(report.cross == "Oak Street and First Street")
		#expect(await mapClient.immediateOptions == [MapDetailOptions()])
		#expect(await mapClient.fullOptions.isEmpty)
	}

	@Test func rankedNearestKeepsFullCrossingDetailsEnabled() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let mapClient = ImmediateRecordingMapDataClient(
			fullData: rankedStreetData(origin: origin),
			immediateData: crossingFirstData(origin: origin)
		)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(context: DeviceContext(coordinate: origin, headingDegrees: 0)),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)

		let report = try await service.report(.nearest, rank: 2, prefs: prefs)

		#expect(report.cross == "Oak Street and Second Street")
		#expect(await mapClient.immediateOptions.isEmpty)
		#expect(await mapClient.fullOptions == [MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)])
	}

	@Test func rankedNearestReturnsRequestedDistanceOrder() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let candidates = [
			IntersectionCandidate(
				id: "third",
				names: ["Oak Street", "Third Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.003, longitude: -122.0)
			),
			IntersectionCandidate(
				id: "first",
				names: ["Oak Street", "First Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
			),
			IntersectionCandidate(
				id: "second",
				names: ["Oak Street", "Second Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
			)
		]

		let match = IntersectionFinder().nearest(rank: 2, from: origin, in: candidates)

		#expect(match?.id == "second")
	}

	@Test func rankedNearestCollapsesNearbyDuplicateMapNodes() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let candidates = [
			IntersectionCandidate(
				id: "duplicate-a",
				names: ["Oak Street", "Pine Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
			),
			IntersectionCandidate(
				id: "duplicate-b",
				names: ["Pine Street", "Oak Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.0011, longitude: -122.0)
			),
			IntersectionCandidate(
				id: "second",
				names: ["Oak Street", "Cedar Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
			)
		]

		let ranked = IntersectionFinder().rankedNearest(from: origin, in: candidates)

		#expect(ranked.map(\.id) == ["duplicate-a", "second"])
	}

	@Test func pointScanFiltersToCurrentStreetIntersections() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 37.002, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 37.001, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 37.01, lon: -122.01, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 6, lat: 37.011, lon: -122.01, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 7, lat: 37.01, lon: -122.011, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 2], tags: ["highway": "residential", "name": "Pine Street"]),
				OverpassElement(type: "way", id: 12, lat: nil, lon: nil, nodes: [5, 6], tags: ["highway": "residential", "name": "Distant Street"]),
				OverpassElement(type: "way", id: 13, lat: nil, lon: nil, nodes: [7, 5], tags: ["highway": "residential", "name": "Far Avenue"])
			]
		)
		let data = IntersectionBuilder().mapData(from: response)
		let origin = CLLocationCoordinate2D(latitude: 37.0002, longitude: -122.0)

		let currentStreetIntersections = data.currentStreetIntersections(from: origin)

		#expect(currentStreetIntersections.map(\.title) == ["Oak Street and Pine Street"])
	}

	@Test func pointScanCanIncludeCurrentStreetCrossingsWhenEnabled() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0002, longitude: -122.0)
		let mapData = MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: "street-intersection",
					names: ["Oak Street", "Pine Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0)
				),
				IntersectionCandidate(
					id: "crossing-10",
					names: ["Crossing on Oak Street near Pine Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0004, longitude: -122.0),
					associatedRoadNames: ["Oak Street"]
				),
				IntersectionCandidate(
					id: "crossing-20",
					names: ["Crossing on Distant Street near Far Avenue"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0005, longitude: -122.0),
					associatedRoadNames: ["Distant Street"]
				)
			],
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)
					]
				),
				MapRoad(
					id: "distant",
					name: "Distant Street",
					nodeIDs: [3, 4],
					coordinates: [
						CLLocationCoordinate2D(latitude: 37.01, longitude: -122.0),
						CLLocationCoordinate2D(latitude: 37.012, longitude: -122.0)
					]
				)
			]
		)

		let withoutCrossings = mapData.currentStreetScanTargets(
			from: origin,
			includeCrossings: false
		)
		let withCrossings = mapData.currentStreetScanTargets(
			from: origin,
			includeCrossings: true
		)

		#expect(withoutCrossings.map(\.id) == ["street-intersection"])
		#expect(withCrossings.map(\.id) == ["crossing-10", "street-intersection"])
	}

	@Test func mapDataCacheReusesNearbyResults() async throws {
		let cache = MapDataCache()
		let counter = FetchCounter()
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let nearby = CLLocationCoordinate2D(latitude: 37.0002, longitude: -122.0)

		let first = try await cache.data(near: origin, radiusMeters: 450) {
			await counter.nextDataSet()
		}
		let second = try await cache.data(near: nearby, radiusMeters: 450) {
			await counter.nextDataSet()
		}

		#expect(first.intersections.first?.id == "fetch-1")
		#expect(second.intersections.first?.id == "fetch-1")
		#expect(await counter.count == 1)
	}

	@Test func mapDataCacheFetchesAgainForDistantResults() async throws {
		let cache = MapDataCache()
		let counter = FetchCounter()
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let distant = CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)

		let first = try await cache.data(near: origin, radiusMeters: 450) {
			await counter.nextDataSet()
		}
		let second = try await cache.data(near: distant, radiusMeters: 450) {
			await counter.nextDataSet()
		}

		#expect(first.intersections.first?.id == "fetch-1")
		#expect(second.intersections.first?.id == "fetch-2")
		#expect(await counter.count == 2)
	}

	@Test func mapDataCacheKeepsSeveralRecentAreas() async throws {
		let cache = MapDataCache()
		let counter = FetchCounter()
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let distant = CLLocationCoordinate2D(latitude: 37.002, longitude: -122.0)

		let first = try await cache.data(near: origin, radiusMeters: 225) {
			await counter.nextDataSet()
		}
		let second = try await cache.data(near: distant, radiusMeters: 225) {
			await counter.nextDataSet()
		}
		let reusedFirst = try await cache.data(near: origin, radiusMeters: 225) {
			await counter.nextDataSet()
		}

		#expect(first.intersections.first?.id == "fetch-1")
		#expect(second.intersections.first?.id == "fetch-2")
		#expect(reusedFirst.intersections.first?.id == "fetch-1")
		#expect(await counter.count == 2)
	}

	@Test func mapDataCacheSeparatesMapDetailOptions() async throws {
		let cache = MapDataCache()
		let counter = FetchCounter()
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)

		let first = try await cache.data(near: origin, radiusMeters: 450, options: MapDetailOptions()) {
			await counter.nextDataSet()
		}
		let second = try await cache.data(
			near: origin,
			radiusMeters: 450,
			options: MapDetailOptions(includeCrossings: true)
		) {
			await counter.nextDataSet()
		}

		#expect(first.intersections.first?.id == "fetch-1")
		#expect(second.intersections.first?.id == "fetch-2")
		#expect(await counter.count == 2)
	}

	@Test func mapDataCacheDoesNotReuseSmallerAreaForLargerRadius() async throws {
		let cache = MapDataCache()
		let counter = FetchCounter()
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)

		let first = try await cache.data(near: origin, radiusMeters: 225) {
			await counter.nextDataSet()
		}
		let expanded = try await cache.data(near: origin, radiusMeters: 750) {
			await counter.nextDataSet()
		}

		#expect(first.intersections.first?.id == "fetch-1")
		#expect(expanded.intersections.first?.id == "fetch-2")
		#expect(await counter.count == 2)
	}

	@Test func mapEndpointHealthSkipsTemporarilyFailedPrimaryEndpoint() async throws {
		let health = MapEndpointHealth()
		let primary = URL(string: "https://primary.example/api/interpreter")!
		let fallback = URL(string: "https://fallback.example/api/interpreter")!

		let initialOrder = await health.orderedEndpoints(primary: primary, fallbacks: [fallback])
		await health.markTemporaryFailure(primary)
		let failureOrder = await health.orderedEndpoints(primary: primary, fallbacks: [fallback])
		await health.markSuccess(primary)
		let recoveredOrder = await health.orderedEndpoints(primary: primary, fallbacks: [fallback])

		#expect(initialOrder == [primary, fallback])
		#expect(failureOrder == [fallback])
		#expect(recoveredOrder == [primary, fallback])
	}

	@Test func mapDataClientAcceptsAStaggeredFallbackBeforeThePrimaryTimesOut() async throws {
		let primary = URL(string: "https://slow-primary.example/api/interpreter")!
		let fallback = URL(string: "https://fast-fallback.example/api/interpreter")!
		let requestLog = MapRequestLog()
		var client = MapDataClient()
		client.endpoint = primary
		client.fallbackEndpoints = [fallback]
		client.requestHandler = { request in
			guard let url = request.url else {
				throw URLError(.badURL)
			}
			await requestLog.record(url)
			if url == primary {
				try await Task.sleep(for: .seconds(5))
				throw URLError(.timedOut)
			}
			let response = HTTPURLResponse(
				url: url,
				statusCode: 200,
				httpVersion: nil,
				headerFields: nil
			)!
			return MapHTTPResponse(
				data: Data("{\"elements\":[]}".utf8),
				response: response
			)
		}

		let clock = ContinuousClock()
		let start = clock.now
		let data = try await client.freshMapData(
			near: CLLocationCoordinate2D(latitude: 39.1234, longitude: -76.5432),
			radiusMeters: 225
		)
		let elapsed = start.duration(to: clock.now)

		#expect(data.intersections.isEmpty)
		#expect(await requestLog.urls == [primary, fallback])
		#expect(elapsed < .seconds(3))
	}

	@Test func intersectionBuilderIgnoresNonStreetPaths() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 37.0, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [3, 1], tags: ["highway": "footway", "name": "Garden Path"])
			]
		)

		let data = IntersectionBuilder().mapData(from: response)

		#expect(data.intersections.isEmpty)
		#expect(data.roads.map(\.name) == ["Oak Street"])
	}

	@Test func intersectionBuilderIncludesWalkingPathsWhenEnabled() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 37.0, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [3, 1], tags: ["highway": "footway", "name": "Garden Path"])
			]
		)
		let options = MapDetailOptions(includeWalkingPaths: true)

		let data = IntersectionBuilder().mapData(from: response, options: options)

		#expect(data.intersections.map(\.title) == ["Garden Path and Oak Street"])
		#expect(data.roads.map(\.name) == ["Oak Street", "Garden Path"])
	}

	@Test func intersectionBuilderIgnoresCrossingsByDefault() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: ["highway": "crossing"]),
				OverpassElement(type: "node", id: 3, lat: 37.002, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"])
			]
		)

		let data = IntersectionBuilder().mapData(from: response)

		#expect(data.intersections.isEmpty)
	}

	@Test func intersectionBuilderKeepsMidBlockCrossingsWhenEnabled() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: ["highway": "crossing"]),
				OverpassElement(type: "node", id: 3, lat: 37.002, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"])
			]
		)
		let options = MapDetailOptions(includeCrossings: true)

		let data = IntersectionBuilder().mapData(from: response, options: options)

		#expect(data.intersections.map(\.title) == ["Crossing on Oak Street"])
	}

	@Test func intersectionBuilderKeepsCrossingAndServiceRoadIntersectionSeparate() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 40.7960, lon: -73.9720, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 40.7970, lon: -73.9720, nodes: nil, tags: ["highway": "crossing"]),
				OverpassElement(type: "node", id: 3, lat: 40.7980, lon: -73.9720, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 40.7974, lon: -73.9717, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 40.7974, lon: -73.9713, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "primary", "name": "Riverside Drive"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 5], tags: ["highway": "residential", "name": "West 99th Street"]),
				OverpassElement(type: "way", id: 12, lat: nil, lon: nil, nodes: [2, 4], tags: ["highway": "residential", "name": "Riverside Drive"])
			]
		)

		let data = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true)
		)

		#expect(data.intersections.contains { $0.title == "Crossing on Riverside Drive near West 99th Street" })
		#expect(data.intersections.contains { $0.title == "Riverside Drive and West 99th Street" })
	}

	@Test func intersectionBuilderKeepsColumbusStyleCrossingWayWithoutWalkingPaths() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 40.7940, lon: -73.9667, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 40.7947, lon: -73.9662, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 40.7954, lon: -73.9657, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 40.7947, lon: -73.9664, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 40.7947, lon: -73.9660, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "primary", "name": "Columbus Avenue"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 2, 5], tags: [
					"highway": "footway",
					"footway": "crossing",
					"crossing": "traffic_signals",
					"crossing:markings": "zebra",
					"crossing:signals": "yes"
				]),
				OverpassElement(type: "way", id: 12, lat: nil, lon: nil, nodes: [4, 5], tags: [
					"highway": "service",
					"service": "driveway",
					"access": "private"
				])
			]
		)

		let data = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true, includeWalkingPaths: false)
		)

		#expect(data.intersections.map(\.title) == ["Crossing on Columbus Avenue"])
		#expect(data.intersections.first?.intersectionDetails?.isSignalized == true)
	}

	@Test func intersectionBuilderDoesNotSpeakNamedCrossingPathAsStreet() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 40.7940, lon: -73.9667, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 40.7947, lon: -73.9662, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 40.7954, lon: -73.9657, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 40.7947, lon: -73.9664, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 40.7947, lon: -73.9660, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "primary", "name": "Columbus Avenue"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 2, 5], tags: [
					"highway": "footway",
					"name": "Pedestrian Connector",
					"footway": "crossing",
					"crossing": "marked",
					"crossing:markings": "ladder"
				])
			]
		)

		let data = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)
		)

		#expect(data.intersections.map(\.title) == ["Crossing on Columbus Avenue"])
	}

	@Test func intersectionBuilderDoesNotValidateCrossingFromServiceRoadOnly() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 40.7947, lon: -73.9664, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 40.7947, lon: -73.9662, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 40.7947, lon: -73.9660, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: [
					"highway": "service",
					"name": "Private Drive",
					"service": "driveway",
					"access": "private"
				]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [1, 2, 3], tags: [
					"highway": "footway",
					"footway": "crossing",
					"crossing": "traffic_signals",
					"crossing:markings": "zebra"
				])
			]
		)

		let data = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)
		)

		#expect(data.intersections.isEmpty)
	}

	@Test func intersectionBuilderDoesNotAttachServiceRoadCrossingNodeToNearbyPublicStreet() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0000, lon: -122.0000, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.0010, lon: -122.0000, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 37.0005, lon: -122.00002, nodes: nil, tags: [
					"highway": "crossing",
					"crossing": "unmarked"
				]),
				OverpassElement(type: "node", id: 4, lat: 37.0005, lon: -122.0001, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 37.0005, lon: -121.9999, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2], tags: ["highway": "tertiary", "name": "Foothill Boulevard"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 3, 5], tags: ["highway": "service"])
			]
		)

		let data = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true)
		)

		#expect(data.intersections.isEmpty)
	}

	@Test func intersectionBuilderAnchorsCrossingsToNearbyIntersections() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.0005, lon: -122.0, nodes: nil, tags: ["highway": "crossing"]),
				OverpassElement(type: "node", id: 3, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 37.001, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 3], tags: ["highway": "residential", "name": "Pine Street"])
			]
		)
		let options = MapDetailOptions(includeCrossings: true)

		let data = IntersectionBuilder().mapData(from: response, options: options)

		#expect(data.intersections.map(\.title) == [
			"Oak Street and Pine Street",
			"Crossing on Oak Street near Pine Street"
		])
	}

	@Test func intersectionBuilderSuppressesCornerCrosswalkClusterAtWideStreetIntersection() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.74490, lon: -122.15000, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.74531, lon: -122.15019, nodes: nil, tags: ["highway": "crossing", "crossing": "traffic_signals"]),
				OverpassElement(type: "node", id: 3, lat: 37.74538, lon: -122.15023, nodes: nil, tags: ["highway": "crossing", "crossing": "traffic_signals"]),
				OverpassElement(type: "node", id: 4, lat: 37.74570, lon: -122.15040, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 37.74500, lon: -122.14955, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3, 4], tags: ["highway": "tertiary", "name": "Foothill Boulevard"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [5, 1], tags: ["highway": "residential", "name": "Talbot Avenue"])
			]
		)

		let data = IntersectionBuilder().mapData(
			from: response,
			options: MapDetailOptions(includeCrossings: true)
		)

		#expect(data.intersections.map(\.title) == ["Foothill Boulevard and Talbot Avenue"])
	}

	@Test func intersectionBuilderSuppressesCrossingAtStreetIntersectionNode() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: ["highway": "crossing"]),
				OverpassElement(type: "node", id: 3, lat: 37.002, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 37.001, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 2], tags: ["highway": "residential", "name": "Pine Street"])
			]
		)
		let options = MapDetailOptions(includeCrossings: true)

		let data = IntersectionBuilder().mapData(from: response, options: options)

		#expect(data.intersections.map(\.title) == ["Oak Street and Pine Street"])
	}

	@Test func intersectionBuilderAddsCrossingsFromOptionalEnrichmentResponse() async throws {
		let coreResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.0005, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 37.001, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 3], tags: ["highway": "residential", "name": "Pine Street"])
			]
		)
		let crossingResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 2, lat: 37.0005, lon: -122.0, nodes: nil, tags: ["highway": "crossing", "crossing": "traffic_signals"])
			]
		)
		let builder = IntersectionBuilder()
		let coreData = builder.mapData(from: coreResponse)

		let enrichedData = builder.mapData(
			from: crossingResponse,
			options: MapDetailOptions(includeCrossings: true),
			coreData: coreData
		)

		#expect(enrichedData.intersections.map(\.title) == [
			"Oak Street and Pine Street",
			"Crossing on Oak Street near Pine Street"
		])
		#expect(enrichedData.intersections.last?.intersectionDetails?.isSignalized == true)
	}

	@Test func intersectionBuilderDoesNotEnrichServiceRoadCrossingNodeOntoNearbyPublicStreet() async throws {
		let coreResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0000, lon: -122.0000, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.0010, lon: -122.0000, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2], tags: ["highway": "tertiary", "name": "Foothill Boulevard"])
			]
		)
		let crossingResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 3, lat: 37.0005, lon: -122.00002, nodes: nil, tags: [
					"highway": "crossing",
					"crossing": "unmarked"
				]),
				OverpassElement(type: "node", id: 4, lat: 37.0005, lon: -122.0001, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 5, lat: 37.0005, lon: -121.9999, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 3, 5], tags: ["highway": "service"])
			]
		)
		let builder = IntersectionBuilder()
		let coreData = builder.mapData(from: coreResponse)

		let enrichedData = builder.mapData(
			from: crossingResponse,
			options: MapDetailOptions(includeCrossings: true),
			coreData: coreData
		)

		#expect(enrichedData.intersections.isEmpty)
	}

	@Test func intersectionBuilderSuppressesEnrichedCornerCrosswalkCluster() async throws {
		let coreResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.74490, lon: -122.15000, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.74570, lon: -122.15040, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 3, lat: 37.74500, lon: -122.14955, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2], tags: ["highway": "tertiary", "name": "Foothill Boulevard"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [3, 1], tags: ["highway": "residential", "name": "Talbot Avenue"])
			]
		)
		let crossingResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 20, lat: 37.74531, lon: -122.15019, nodes: nil, tags: ["highway": "crossing", "crossing": "traffic_signals"]),
				OverpassElement(type: "node", id: 21, lat: 37.74538, lon: -122.15023, nodes: nil, tags: ["highway": "crossing", "crossing": "traffic_signals"])
			]
		)
		let builder = IntersectionBuilder()
		let coreData = builder.mapData(from: coreResponse)

		let enrichedData = builder.mapData(
			from: crossingResponse,
			options: MapDetailOptions(includeCrossings: true),
			coreData: coreData
		)

		#expect(enrichedData.intersections.map(\.title) == ["Foothill Boulevard and Talbot Avenue"])
	}

	@Test func intersectionBuilderAnchorsNearbyCrossingsThatAreNotRoadNodes() async throws {
		let coreResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2], tags: ["highway": "residential", "name": "Oak Street"])
			]
		)
		let crossingResponse = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 3, lat: 37.0005, lon: -122.00002, nodes: nil, tags: ["highway": "crossing"])
			]
		)
		let builder = IntersectionBuilder()
		let coreData = builder.mapData(from: coreResponse)

		let enrichedData = builder.mapData(
			from: crossingResponse,
			options: MapDetailOptions(includeCrossings: true),
			coreData: coreData
		)

		#expect(enrichedData.intersections.map(\.title) == ["Crossing on Oak Street"])
	}

	@Test func intersectionBuilderSuppressesCrossingBesideStreetIntersection() async throws {
		let response = OverpassResponse(
			elements: [
				OverpassElement(type: "node", id: 1, lat: 37.0, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 2, lat: 37.00005, lon: -122.0, nodes: nil, tags: ["highway": "crossing"]),
				OverpassElement(type: "node", id: 3, lat: 37.001, lon: -122.0, nodes: nil, tags: nil),
				OverpassElement(type: "node", id: 4, lat: 37.0, lon: -122.001, nodes: nil, tags: nil),
				OverpassElement(type: "way", id: 10, lat: nil, lon: nil, nodes: [1, 2, 3], tags: ["highway": "residential", "name": "Oak Street"]),
				OverpassElement(type: "way", id: 11, lat: nil, lon: nil, nodes: [4, 1], tags: ["highway": "residential", "name": "Pine Street"])
			]
		)
		let options = MapDetailOptions(includeCrossings: true)

		let data = IntersectionBuilder().mapData(from: response, options: options)

		#expect(data.intersections.map(\.title) == ["Oak Street and Pine Street"])
	}

	@Test func areaModeOffSkipsNeighborhoodLookup() async throws {
		let neighborhoodProvider = FakeNeighborhoodProvider(candidates: [
			NeighborhoodCandidate(
				id: "mission",
				name: "Mission District",
				coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
				kind: .neighbourhood
			)
		])
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: nil
				)
			),
			mapDataClient: FakeMapDataClient(),
			neighborhoodProvider: neighborhoodProvider
		)

		let report = try await service.report(.nearest, prefs: prefs)

		#expect(report.area == nil)
		#expect(report.toward == nil)
		#expect(await neighborhoodProvider.requestCount == 0)
	}

	@Test func areaModeNearAddsNeighborhoodText() async throws {
		let neighborhoodProvider = FakeNeighborhoodProvider(candidates: [
			NeighborhoodCandidate(
				id: "mission",
				name: "Mission District",
				coordinate: CLLocationCoordinate2D(latitude: 37.0001, longitude: -122.0),
				kind: .neighbourhood
			)
		])
		var prefs = AppPrefs()
		prefs.areaMode = .near
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: nil
				)
			),
			mapDataClient: FakeMapDataClient(),
			neighborhoodProvider: neighborhoodProvider
		)

		let report = try await service.report(.nearest, prefs: prefs)
		let text = report.text(with: prefs)

		#expect(report.area == "Mission District")
		#expect(text.contains("in Mission District"))
		#expect(await neighborhoodProvider.requestCount == 1)
	}

	@Test func areaModeTowardUsesHeadingAwareNeighborhood() async throws {
		let neighborhoodProvider = FakeNeighborhoodProvider(candidates: [
			NeighborhoodCandidate(
				id: "mission",
				name: "Mission District",
				coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.001),
				kind: .neighbourhood
			),
			NeighborhoodCandidate(
				id: "north-beach",
				name: "North Beach",
				coordinate: CLLocationCoordinate2D(latitude: 37.01, longitude: -122.0),
				kind: .neighbourhood
			)
		])
		var prefs = AppPrefs()
		prefs.areaMode = .toward
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: 0
				)
			),
			mapDataClient: FakeMapDataClient(),
			neighborhoodProvider: neighborhoodProvider
		)

		let report = try await service.report(.nearest, prefs: prefs)
		let text = report.text(with: prefs)

		#expect(report.area == "Mission District")
		#expect(report.toward == "North Beach")
		#expect(text.contains("toward North Beach"))
	}

	@Test func neighborhoodFailureDoesNotFailIntersectionReport() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .near
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: nil
				)
			),
			mapDataClient: FakeMapDataClient(),
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let report = try await service.report(.nearest, prefs: prefs)

		#expect(report.cross == "Oak Street and Pine Street")
		#expect(report.area == nil)
		#expect(report.toward == nil)
	}

	@Test func thirdNearestExpandsRadiusOnlyUntilEnoughResultsExist() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let mapClient = AdaptiveMapDataClient()
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: nil
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let report = try await service.report(.nearest, rank: 3, prefs: prefs)

		#expect(report.cross == "Oak Street and Third Street")
		#expect(await mapClient.requestedRadii == [225, 375, 750])
	}

	@Test func firstUpcomingDoesNotExpandRadiusToPrefetchRankedFollowups() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let mapClient = AdaptiveMapDataClient()
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: 0
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let report = try await service.report(.upcoming, prefs: prefs)

		#expect(report.cross == "Oak Street and First Street")
		#expect(await mapClient.requestedRadii == [225])
	}

	@Test func initialNearestPrewarmFetchesOneCoreResultWithoutOptionalMapDetails() async throws {
		let mapClient = AdaptiveMapDataClient()
		var prefs = AppPrefs()
		prefs.spokenIntersectionCount = .three
		prefs.mapDetails = MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: nil,
					horizontalAccuracy: 10
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let isReady = await service.prewarmInitialNearestMapData(prefs: prefs)

		#expect(isReady)
		#expect(await mapClient.requestedRadii == [225])
		#expect(await mapClient.requestedOptions == [
			MapDetailOptions()
		])
	}

	@Test func initialReportPrewarmLoadsNearestAndWalkingPathVariants() async throws {
		let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
		let data = crossingFirstData(origin: origin)
		let mapClient = ImmediateRecordingMapDataClient(fullData: data, immediateData: data)
		var prefs = AppPrefs()
		prefs.mapDetails = MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: origin,
					headingDegrees: 0,
					horizontalAccuracy: 10
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let isReady = await service.prewarmInitialReportMapData(prefs: prefs)

		#expect(isReady)
		#expect(await mapClient.immediateOptions == [
			MapDetailOptions(includeCrossings: true)
		])
		#expect(await mapClient.fullOptions == [
			MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)
		])
	}

	@Test func firstNearestWithOptionalMapDetailsKeepsCrossingsOnImmediateLookup() async throws {
		let mapClient = AdaptiveMapDataClient()
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions(includeCrossings: true, includeWalkingPaths: true)
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: nil,
					horizontalAccuracy: 10
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		_ = try await service.report(.nearest, prefs: prefs)
		_ = try await service.report(.nearest, prefs: prefs)

		#expect(await mapClient.requestedRadii == [225, 225])
		#expect(await mapClient.requestedOptions == [
			MapDetailOptions(includeCrossings: true),
			MapDetailOptions(includeCrossings: true)
		])
	}

	@Test func thirdUpcomingUsesOneFocusedRoadExpansion() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		let mapClient = AdaptiveMapDataClient()
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: 0
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let report = try await service.report(.upcoming, rank: 3, prefs: prefs)

		#expect(report.cross == "Oak Street and Third Street")
		#expect(await mapClient.requestedRadii == [225, 1_200])
	}

	@Test func rankedUpcomingRetriesExpandedCrossingFailuresWithoutDroppingRoadResults() async throws {
		var prefs = AppPrefs()
		prefs.areaMode = .off
		prefs.mapDetails = MapDetailOptions(includeCrossings: true)
		let mapClient = CrossingExpansionFailingMapDataClient()
		let service = OrientSvc(
			locationProvider: FakeLocationProvider(
				context: DeviceContext(
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
					headingDegrees: 0
				)
			),
			mapDataClient: mapClient,
			neighborhoodProvider: FailingNeighborhoodProvider()
		)

		let report = try await service.report(.upcoming, rank: 3, prefs: prefs)

		#expect(report.cross == "Oak Street and Third Street")
		#expect(await mapClient.requestedRadii == [225, 1_200, 1_200])
		#expect(await mapClient.requestedOptions == [
			MapDetailOptions(includeCrossings: true),
			MapDetailOptions(includeCrossings: true),
			MapDetailOptions()
		])
	}

}

actor FetchCounter {
	private(set) var count = 0

	func nextDataSet() -> MapDataSet {
		count += 1
		let id = "fetch-\(count)"
		return MapDataSet(
			intersections: [
				IntersectionCandidate(
					id: id,
					names: ["Oak Street", "Pine Street"],
					coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
				)
			],
			roads: []
		)
	}
}

struct FakeLocationProvider: LocationProviding {
	var context: DeviceContext

	func currentContext() async throws -> DeviceContext {
		context
	}
}

actor SequentialLocationProvider: LocationProviding {
	private let contexts: [DeviceContext]
	private var index = 0
	private(set) var requestCount = 0

	init(contexts: [DeviceContext]) {
		self.contexts = contexts
	}

	func currentContext() async throws -> DeviceContext {
		requestCount += 1
		guard !contexts.isEmpty else {
			throw OrientError.locationUnavailable
		}
		let context = contexts[min(index, contexts.count - 1)]
		index += 1
		return context
	}
}

actor FreshHeadingRecordingLocationProvider: LocationProviding {
	private let context: DeviceContext
	private(set) var freshHeadingRequests: [Bool] = []

	init(context: DeviceContext) {
		self.context = context
	}

	func currentContext() async throws -> DeviceContext {
		try await currentContext(requiresFreshHeading: false)
	}

	func currentContext(requiresFreshHeading: Bool) async throws -> DeviceContext {
		freshHeadingRequests.append(requiresFreshHeading)
		return context
	}
}

private func rankedStreetData(origin: CLLocationCoordinate2D) -> MapDataSet {
	MapDataSet(
		intersections: [
			IntersectionCandidate(
				id: "rank-1",
				names: ["Oak Street", "First Street"],
				coordinate: CLLocationCoordinate2D(latitude: origin.latitude + 0.001, longitude: origin.longitude)
			),
			IntersectionCandidate(
				id: "rank-2",
				names: ["Oak Street", "Second Street"],
				coordinate: CLLocationCoordinate2D(latitude: origin.latitude + 0.002, longitude: origin.longitude)
			)
		],
		roads: [
			MapRoad(
				id: "oak",
				name: "Oak Street",
				nodeIDs: [1, 2],
				coordinates: [
					CLLocationCoordinate2D(latitude: origin.latitude - 0.002, longitude: origin.longitude),
					CLLocationCoordinate2D(latitude: origin.latitude + 0.003, longitude: origin.longitude)
				]
			)
		]
	)
}

private func northboundOakRoad(near origin: CLLocationCoordinate2D) -> MapRoad {
	MapRoad(
		id: "oak",
		name: "Oak Street",
		nodeIDs: [1, 2],
		coordinates: [
			CLLocationCoordinate2D(latitude: origin.latitude - 0.002, longitude: origin.longitude),
			CLLocationCoordinate2D(latitude: origin.latitude + 0.005, longitude: origin.longitude)
		]
	)
}

private func crossingFirstData(origin: CLLocationCoordinate2D) -> MapDataSet {
	MapDataSet(
		intersections: [
			IntersectionCandidate(
				id: "crossing-1",
				names: ["Crossing on Oak Street near Pine Street"],
				coordinate: CLLocationCoordinate2D(latitude: origin.latitude + 0.0002, longitude: origin.longitude),
				associatedRoadNames: ["Oak Street"]
			),
			IntersectionCandidate(
				id: "street-1",
				names: ["Oak Street", "Pine Street"],
				coordinate: CLLocationCoordinate2D(latitude: origin.latitude + 0.001, longitude: origin.longitude)
			)
		],
		roads: [
			MapRoad(
				id: "oak",
				name: "Oak Street",
				nodeIDs: [1, 2],
				coordinates: [
					CLLocationCoordinate2D(latitude: origin.latitude - 0.002, longitude: origin.longitude),
					CLLocationCoordinate2D(latitude: origin.latitude + 0.003, longitude: origin.longitude)
				]
			)
		]
	)
}

actor ImmediateRecordingMapDataClient: MapDataFetching {
	private let fullData: MapDataSet
	private let immediateData: MapDataSet
	private(set) var fullOptions: [MapDetailOptions] = []
	private(set) var immediateOptions: [MapDetailOptions] = []

	init(fullData: MapDataSet, immediateData: MapDataSet) {
		self.fullData = fullData
		self.immediateData = immediateData
	}

	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate] {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		).intersections
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		fullOptions.append(options)
		return fullData
	}

	func immediateMapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		immediateOptions.append(options)
		return immediateData
	}
}

actor MapRequestLog {
	private(set) var urls: [URL] = []

	func record(_ url: URL) {
		urls.append(url)
	}
}

struct FakeMapDataClient: MapDataFetching {
	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate] {
		[
			IntersectionCandidate(
				id: "oak-pine",
				names: ["Oak Street", "Pine Street"],
				coordinate: CLLocationCoordinate2D(latitude: 37.0001, longitude: -122.0)
			)
		]
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		MapDataSet(
			intersections: try await intersections(
				near: coordinate,
				radiusMeters: radiusMeters,
				options: options
			),
			roads: []
		)
	}
}

struct StaticMapDataClient: MapDataFetching {
	var data: MapDataSet

	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate] {
		data.intersections
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		data
	}
}

actor RankedFocusedMapDataClient: MapDataFetching {
	private(set) var focusedRoadRequestCount = 0

	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate] {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		).intersections
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		rankedData(near: coordinate, count: 1)
	}

	func roadMapData(
		near coordinate: CLLocationCoordinate2D,
		roadName: String,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		focusedRoadRequestCount += 1
		return rankedData(near: coordinate, count: 3)
	}

	private func rankedData(
		near coordinate: CLLocationCoordinate2D,
		count: Int
	) -> MapDataSet {
		let names = ["First Street", "Second Street", "Third Street"]
		let candidates = (0..<count).map { index in
			IntersectionCandidate(
				id: "fresh-rank-\(index + 1)",
				names: ["Oak Street", names[index]],
				coordinate: CLLocationCoordinate2D(
					latitude: coordinate.latitude + Double(index + 1) * 0.001,
					longitude: coordinate.longitude
				)
			)
		}
		return MapDataSet(
			intersections: candidates,
			roads: [northboundOakRoad(near: coordinate)]
		)
	}
}

actor AdaptiveMapDataClient: MapDataFetching {
	private(set) var requestedRadii: [CLLocationDistance] = []
	private(set) var requestedOptions: [MapDetailOptions] = []

	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate] {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		).intersections
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		requestedRadii.append(radiusMeters)
		requestedOptions.append(options)
		let availableCount = radiusMeters < 375 ? 1 : (radiusMeters < 750 ? 2 : 3)
		let names = ["First Street", "Second Street", "Third Street"]
		let candidates = (0..<availableCount).map { index in
			IntersectionCandidate(
				id: "rank-\(index + 1)",
				names: ["Oak Street", names[index]],
				coordinate: CLLocationCoordinate2D(
					latitude: coordinate.latitude + Double(index + 1) * 0.001,
					longitude: coordinate.longitude
				)
			)
		}
		return MapDataSet(
			intersections: candidates,
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(
							latitude: coordinate.latitude - 0.005,
							longitude: coordinate.longitude
						),
						CLLocationCoordinate2D(
							latitude: coordinate.latitude + 0.005,
							longitude: coordinate.longitude
						)
					]
				)
			]
		)
	}
}

actor CrossingExpansionFailingMapDataClient: MapDataFetching {
	private(set) var requestedRadii: [CLLocationDistance] = []
	private(set) var requestedOptions: [MapDetailOptions] = []

	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate] {
		try await mapData(
			near: coordinate,
			radiusMeters: radiusMeters,
			options: options
		).intersections
	}

	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet {
		requestedRadii.append(radiusMeters)
		requestedOptions.append(options)
		if options.includeCrossings && radiusMeters > 225 {
			throw URLError(.timedOut)
		}

		let availableCount = radiusMeters < 375 ? 1 : (radiusMeters < 750 ? 2 : 3)
		let names = ["First Street", "Second Street", "Third Street"]
		let candidates = (0..<availableCount).map { index in
			IntersectionCandidate(
				id: "rank-\(index + 1)",
				names: ["Oak Street", names[index]],
				coordinate: CLLocationCoordinate2D(
					latitude: coordinate.latitude + Double(index + 1) * 0.001,
					longitude: coordinate.longitude
				)
			)
		}
		return MapDataSet(
			intersections: candidates,
			roads: [
				MapRoad(
					id: "oak",
					name: "Oak Street",
					nodeIDs: [1, 2],
					coordinates: [
						CLLocationCoordinate2D(
							latitude: coordinate.latitude - 0.005,
							longitude: coordinate.longitude
						),
						CLLocationCoordinate2D(
							latitude: coordinate.latitude + 0.005,
							longitude: coordinate.longitude
						)
					]
				)
			]
		)
	}
}

actor FakeNeighborhoodProvider: NeighborhoodProviding {
	private var count = 0
	private let candidates: [NeighborhoodCandidate]

	var requestCount: Int {
		count
	}

	init(candidates: [NeighborhoodCandidate]) {
		self.candidates = candidates
	}

	func neighborhoods(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance
	) async throws -> [NeighborhoodCandidate] {
		count += 1
		return candidates
	}
}

struct FailingNeighborhoodProvider: NeighborhoodProviding {
	func neighborhoods(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance
	) async throws -> [NeighborhoodCandidate] {
		throw MapDataError.invalidResponse
	}
}
