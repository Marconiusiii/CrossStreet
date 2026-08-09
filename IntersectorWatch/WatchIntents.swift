//
//  WatchIntents.swift
//  Intersector Watch App
//
//  Created by Marco Salsiccia on 6/17/26.
//

import AppIntents
import Foundation

private func watchIntersectorResult(
	_ text: String
) -> some IntentResult & ProvidesDialog {
	.result(dialog: IntentDialog(stringLiteral: text))
}

struct WatchIntersectorShortcutResult: AppEntity {
	typealias ID = String

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Intersector Result")
	static var defaultQuery = WatchIntersectorShortcutResultQuery()

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
		details: String = ""
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
	}
}

struct WatchIntersectorShortcutResultQuery: EntityQuery {
	func entities(for identifiers: [WatchIntersectorShortcutResult.ID]) async throws -> [WatchIntersectorShortcutResult] {
		[]
	}

	func suggestedEntities() async throws -> [WatchIntersectorShortcutResult] {
		[]
	}
}

@MainActor
private func watchShortcutResult(
	from report: WatchOrientationReport,
	prefs: WatchAppPrefs,
	rank: Int? = nil
) -> WatchIntersectorShortcutResult {
	let announcementText = if let rank {
		report.text(with: prefs, rank: rank)
	} else {
		report.text(with: prefs)
	}
	return WatchIntersectorShortcutResult(
		announcementText: announcementText,
		intersection: report.cross,
		distance: report.dist,
		direction: report.relDir ?? "",
		heading: report.head ?? "",
		neighborhood: report.area ?? "",
		toward: report.toward ?? "",
		details: report.intersectionDetails?.spokenPhrases.joined(separator: ", ") ?? ""
	)
}

struct WatchNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Nearest Intersection"
	static var description = IntentDescription("Reports the closest mapped intersection.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let text = await IntersectorWatchReporter.reportText(for: .nearest)
		return watchIntersectorResult(text)
	}
}

struct WatchUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Upcoming Intersection"
	static var description = IntentDescription("Reports the mapped intersection ahead.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let text = await IntersectorWatchReporter.reportText(for: .upcoming)
		return watchIntersectorResult(text)
	}
}

struct WatchMyDirectionIntent: AppIntent {
	static var title: LocalizedStringResource = "My Direction"
	static var description = IntentDescription("Reports the direction you are facing.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let text = await IntersectorWatchReporter.directionText()
		return watchIntersectorResult(text)
	}
}

struct WatchGetNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get Nearest Intersection"
	static var description = IntentDescription("Gets the closest mapped intersection as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let report = try await WatchOrientationService().report(.nearest, prefs: prefs)
		return .result(value: watchShortcutResult(from: report, prefs: prefs))
	}
}

struct WatchGetSecondNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 2nd Nearest Intersection"
	static var description = IntentDescription("Gets the second closest mapped intersection as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let report = try await WatchOrientationService().report(.nearest, rank: 2, prefs: prefs)
		return .result(value: watchShortcutResult(from: report, prefs: prefs, rank: 2))
	}
}

struct WatchGetThirdNearestIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 3rd Nearest Intersection"
	static var description = IntentDescription("Gets the third closest mapped intersection as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let report = try await WatchOrientationService().report(.nearest, rank: 3, prefs: prefs)
		return .result(value: watchShortcutResult(from: report, prefs: prefs, rank: 3))
	}
}

struct WatchGetUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get Upcoming Intersection"
	static var description = IntentDescription("Gets the mapped intersection ahead as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let report = try await WatchOrientationService().report(.upcoming, prefs: prefs)
		return .result(value: watchShortcutResult(from: report, prefs: prefs))
	}
}

struct WatchGetSecondUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 2nd Upcoming Intersection"
	static var description = IntentDescription("Gets the second mapped intersection ahead as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let report = try await WatchOrientationService().report(.upcoming, rank: 2, prefs: prefs)
		return .result(value: watchShortcutResult(from: report, prefs: prefs, rank: 2))
	}
}

struct WatchGetThirdUpcomingIntersectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get 3rd Upcoming Intersection"
	static var description = IntentDescription("Gets the third mapped intersection ahead as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let report = try await WatchOrientationService().report(.upcoming, rank: 3, prefs: prefs)
		return .result(value: watchShortcutResult(from: report, prefs: prefs, rank: 3))
	}
}

struct WatchGetMyDirectionIntent: AppIntent {
	static var title: LocalizedStringResource = "Get My Direction"
	static var description = IntentDescription("Gets the direction the watch is facing as a Shortcuts value.")
	static var openAppWhenRun = false

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<WatchIntersectorShortcutResult> {
		let prefs = WatchAppPrefs.saved()
		let heading = try await WatchLocationProvider().currentHeading(allowCached: false)
		let direction = WatchGeo.localizedDirection(heading, prefs: prefs)
		return .result(
			value: WatchIntersectorShortcutResult(
				announcementText: "Facing \(direction).",
				direction: direction,
				heading: WatchGeo.compassDirection(heading)
			)
		)
	}
}

struct IntersectorWatchShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: WatchNearestIntersectionIntent(),
			phrases: [
				"Nearest intersection in \(.applicationName)",
				"Where is the nearest intersection with \(.applicationName)",
				"What's my nearest intersection with \(.applicationName)",
				"What intersection am I near with \(.applicationName)"
			],
			shortTitle: "Nearest",
			systemImageName: "location.fill"
		)
		AppShortcut(
			intent: WatchUpcomingIntersectionIntent(),
			phrases: [
				"Upcoming intersection in \(.applicationName)",
				"What intersection is ahead with \(.applicationName)",
				"What's my upcoming intersection with \(.applicationName)",
				"What intersection is coming up with \(.applicationName)"
			],
			shortTitle: "Upcoming",
			systemImageName: "arrow.up.circle.fill"
		)
		AppShortcut(
			intent: WatchMyDirectionIntent(),
			phrases: [
				"My direction in \(.applicationName)",
				"Which way am I facing with \(.applicationName)",
				"What direction am I facing with \(.applicationName)"
			],
			shortTitle: "Direction",
			systemImageName: "safari.fill"
		)
	}
}
