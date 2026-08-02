//
//  IntersectorIntents.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import AppIntents
import CoreLocation
import Foundation

private func intersectorResult(
	_ text: String
) -> some IntentResult & ProvidesDialog {
	.result(dialog: IntentDialog(stringLiteral: text))
}

struct IntersectorShortcutResult: AppEntity {
	typealias ID = String

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Intersector Result")
	static var defaultQuery = IntersectorShortcutResultQuery()

	var id: String

	@Property(title: "Announcement Text")
	var announcementText: String

	@Property(title: "Intersection")
	var intersection: String

	@Property(title: "Distance")
	var distance: String

	@Property(title: "Direction")
	var direction: String

	@Property(title: "Heading")
	var heading: String

	@Property(title: "Neighborhood")
	var neighborhood: String

	@Property(title: "Toward")
	var toward: String

	@Property(title: "Details")
	var details: String

	@Property(title: "Confidence")
	var confidence: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(announcementText)")
	}

	init(
		id: String = UUID().uuidString,
		announcementText: String,
		intersection: String = "",
		distance: String = "",
		direction: String = "",
		heading: String = "",
		neighborhood: String = "",
		toward: String = "",
		details: String = "",
		confidence: String = ""
	) {
		self.id = id
		self.announcementText = announcementText
		self.intersection = intersection
		self.distance = distance
		self.direction = direction
		self.heading = heading
		self.neighborhood = neighborhood
		self.toward = toward
		self.details = details
		self.confidence = confidence
	}
}

struct IntersectorShortcutResultQuery: EntityQuery {
	func entities(for identifiers: [IntersectorShortcutResult.ID]) async throws -> [IntersectorShortcutResult] {
		[]
	}

	func suggestedEntities() async throws -> [IntersectorShortcutResult] {
		[]
	}
}

private func shortcutResult(from report: OrientReport, prefs: AppPrefs, rank: Int? = nil) -> IntersectorShortcutResult {
	let announcementText = if let rank {
		report.text(with: prefs, rank: rank)
	} else {
		report.text(with: prefs)
	}
	return IntersectorShortcutResult(
		announcementText: announcementText,
		intersection: report.cross,
		distance: report.dist,
		direction: report.relDir ?? "",
		heading: report.head ?? "",
		neighborhood: report.area ?? "",
		toward: report.toward ?? "",
		details: report.intersectionDetails?.spokenPhrases.joined(separator: ", ") ?? "",
		confidence: confidenceText(report.conf)
	)
}

private func confidenceText(_ confidence: ConfLev) -> String {
	switch confidence {
	case .high:
		"High"
	case .medium:
		"Medium"
	case .low:
		"Low"
	}
}

private func getIntersectionResult(
	_ kind: ReportKind,
	rank: Int = 1
) async throws -> IntersectorShortcutResult {
	let prefs = AppPrefs.saved()
	let report = try await OrientSvc.shared.report(kind, rank: rank, prefs: prefs)
	return shortcutResult(from: report, prefs: prefs, rank: rank == 1 ? nil : rank)
}

struct NearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Nearest Intersection"
	static var description = IntentDescription("Reports the closest mapped intersection.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let text = try await OrientSvc.shared.spokenText(.nearest, prefs: prefs)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't find your nearest intersection. Please try again.")
		}
	}
}

struct UpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Upcoming Intersection"
	static var description = IntentDescription("Reports the mapped intersection ahead.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let text = try await OrientSvc.shared.spokenText(.upcoming, prefs: prefs)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't find your upcoming intersection. Please try again.")
		}
	}
}

struct SecondNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "2nd Nearest Intersection"
	static var description = IntentDescription("Reports the second closest mapped intersection.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let report = try await OrientSvc.shared.report(.nearest, rank: 2, prefs: prefs)
			let text = report.text(with: prefs, rank: 2)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't find your second nearest intersection. Please try again.")
		}
	}
}

struct ThirdNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "3rd Nearest Intersection"
	static var description = IntentDescription("Reports the third closest mapped intersection.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let report = try await OrientSvc.shared.report(.nearest, rank: 3, prefs: prefs)
			let text = report.text(with: prefs, rank: 3)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't find your third nearest intersection. Please try again.")
		}
	}
}

struct SecondUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "2nd Upcoming Intersection"
	static var description = IntentDescription("Reports the second mapped intersection ahead.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let report = try await OrientSvc.shared.report(.upcoming, rank: 2, prefs: prefs)
			let text = report.text(with: prefs, rank: 2)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't find your second upcoming intersection. Please try again.")
		}
	}
}

struct ThirdUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "3rd Upcoming Intersection"
	static var description = IntentDescription("Reports the third mapped intersection ahead.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let report = try await OrientSvc.shared.report(.upcoming, rank: 3, prefs: prefs)
			let text = report.text(with: prefs, rank: 3)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't find your third upcoming intersection. Please try again.")
		}
	}
}

struct GetNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get Nearest Intersection"
	static var description = IntentDescription("Gets the closest mapped intersection as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		.result(value: try await getIntersectionResult(.nearest))
	}
}

struct GetSecondNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 2nd Nearest Intersection"
	static var description = IntentDescription("Gets the second closest mapped intersection as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		.result(value: try await getIntersectionResult(.nearest, rank: 2))
	}
}

struct GetThirdNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 3rd Nearest Intersection"
	static var description = IntentDescription("Gets the third closest mapped intersection as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		.result(value: try await getIntersectionResult(.nearest, rank: 3))
	}
}

struct GetUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get Upcoming Intersection"
	static var description = IntentDescription("Gets the mapped intersection ahead as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		.result(value: try await getIntersectionResult(.upcoming))
	}
}

struct GetSecondUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 2nd Upcoming Intersection"
	static var description = IntentDescription("Gets the second mapped intersection ahead as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		.result(value: try await getIntersectionResult(.upcoming, rank: 2))
	}
}

struct GetThirdUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 3rd Upcoming Intersection"
	static var description = IntentDescription("Gets the third mapped intersection ahead as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		.result(value: try await getIntersectionResult(.upcoming, rank: 3))
	}
}

struct GetMyDirectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get My Direction"
	static var description = IntentDescription("Gets the direction the device is facing as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntersectorShortcutResult> {
		let prefs = AppPrefs.saved()
		let provider = LocationProvider()
		let heading = try await provider.currentHeading(allowCached: false)
		let direction = Geo.localizedDirection(heading, prefs: prefs)
		return .result(
			value: IntersectorShortcutResult(
				announcementText: "Facing \(direction).",
				direction: direction,
				heading: Geo.compassDirection(heading)
			)
		)
	}
}

struct MyDirectionIntent: AppIntent {
	static var title: LocalizedStringResource = "My Direction"
	static var description = IntentDescription("Reports the cardinal direction the device is facing.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		do {
			let prefs = AppPrefs.saved()
			let provider = LocationProvider()
			let heading = try await provider.currentHeading(allowCached: false)
			let text = Self.spokenDirection(for: heading, prefs: prefs)
			return intersectorResult(text)
		} catch {
			return intersectorResult("I couldn't get your direction. Please try again.")
		}
	}

	static func spokenDirection(for heading: CLLocationDirection, prefs: AppPrefs) -> String {
		"Facing \(Geo.localizedDirection(heading, prefs: prefs))."
	}
}

enum LaunchKeys {
	static let startPointScan = "startPointScanOnLaunch"
}

struct StartPointScanIntent: AppIntent {
	static var title: LocalizedStringResource = "Start Point and Scan"
	static var description = IntentDescription("Opens Intersector and starts live Point and Scan mode.")
	static var openAppWhenRun = true

	func perform() async throws -> some IntentResult & ProvidesDialog {
		UserDefaults.standard.set(true, forKey: await LaunchKeys.startPointScan)
		return .result(dialog: "Opening Intersector with Point and Scan.")
	}
}

struct IntersectorShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: NearestIntersectionIntent(),
			phrases: [
				"Nearest intersection in \(.applicationName)",
				"Where is the nearest intersection with \(.applicationName)",
				"What's my nearest intersection with \(.applicationName)",
				"What is my nearest intersection with \(.applicationName)",
				"What's the nearest intersection with \(.applicationName)",
				"What intersection am I near with \(.applicationName)"
			],
			shortTitle: "Nearest",
			systemImageName: "location.fill"
		)
		AppShortcut(
			intent: UpcomingIntersectionIntent(),
			phrases: [
				"Upcoming intersection in \(.applicationName)",
				"What intersection is ahead with \(.applicationName)",
				"What's my upcoming intersection with \(.applicationName)",
				"What is my upcoming intersection with \(.applicationName)",
				"What's the next intersection with \(.applicationName)",
				"What intersection is coming up with \(.applicationName)"
			],
			shortTitle: "Upcoming",
			systemImageName: "arrow.up.circle.fill"
		)
		AppShortcut(
			intent: SecondNearestIntersectionIntent(),
			phrases: [
				"2nd nearest intersection in \(.applicationName)",
				"Second nearest intersection in \(.applicationName)",
				"What's my 2nd nearest intersection with \(.applicationName)",
				"What's my second nearest intersection with \(.applicationName)",
				"What's the 2nd nearest intersection with \(.applicationName)",
				"What's the second nearest intersection with \(.applicationName)",
				"What is my second nearest intersection with \(.applicationName)",
				"Find my second nearest intersection with \(.applicationName)"
			],
			shortTitle: "2nd Nearest",
			systemImageName: "2.circle.fill"
		)
		AppShortcut(
			intent: ThirdNearestIntersectionIntent(),
			phrases: [
				"3rd nearest intersection in \(.applicationName)",
				"Third nearest intersection in \(.applicationName)",
				"What's my 3rd nearest intersection with \(.applicationName)",
				"What's my third nearest intersection with \(.applicationName)",
				"What's the 3rd nearest intersection with \(.applicationName)",
				"What's the third nearest intersection with \(.applicationName)",
				"What is my third nearest intersection with \(.applicationName)",
				"Find my third nearest intersection with \(.applicationName)"
			],
			shortTitle: "3rd Nearest",
			systemImageName: "3.circle.fill"
		)
		AppShortcut(
			intent: SecondUpcomingIntersectionIntent(),
			phrases: [
				"2nd upcoming intersection in \(.applicationName)",
				"Second upcoming intersection in \(.applicationName)",
				"What's my 2nd upcoming intersection with \(.applicationName)",
				"What's my second upcoming intersection with \(.applicationName)",
				"What's the 2nd upcoming intersection with \(.applicationName)",
				"What's the second upcoming intersection with \(.applicationName)",
				"What is my second upcoming intersection with \(.applicationName)",
				"Find my second upcoming intersection with \(.applicationName)"
			],
			shortTitle: "2nd Upcoming",
			systemImageName: "2.circle"
		)
		AppShortcut(
			intent: ThirdUpcomingIntersectionIntent(),
			phrases: [
				"3rd upcoming intersection in \(.applicationName)",
				"Third upcoming intersection in \(.applicationName)",
				"What's my 3rd upcoming intersection with \(.applicationName)",
				"What's my third upcoming intersection with \(.applicationName)",
				"What's the 3rd upcoming intersection with \(.applicationName)",
				"What's the third upcoming intersection with \(.applicationName)",
				"What is my third upcoming intersection with \(.applicationName)",
				"Find my third upcoming intersection with \(.applicationName)"
			],
			shortTitle: "3rd Upcoming",
			systemImageName: "3.circle"
		)
		AppShortcut(
			intent: MyDirectionIntent(),
			phrases: [
				"My direction in \(.applicationName)",
				"Which way am I facing with \(.applicationName)",
				"What direction am I facing with \(.applicationName)",
				"What way am I facing with \(.applicationName)",
				"Where am I facing with \(.applicationName)"
			],
			shortTitle: "Direction",
			systemImageName: "safari.fill"
		)
		AppShortcut(
			intent: StartPointScanIntent(),
			phrases: [
				"Start Point and Scan in \(.applicationName)",
				"Scan for intersections with \(.applicationName)"
			],
			shortTitle: "Point Scan",
			systemImageName: "dot.radiowaves.left.and.right"
		)
	}
}
