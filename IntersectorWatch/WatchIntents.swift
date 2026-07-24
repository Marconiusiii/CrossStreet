//
//  WatchIntents.swift
//  Intersector Watch App
//
//  Created by Marco Salsiccia on 6/17/26.
//

import AppIntents
import Foundation

/// Returns the spoken announcement as a plain dialog only. Siri speaks it and
/// shows its own native dialog bubble — one correctly-formatted copy of the
/// text. Earlier attempts paired the dialog with a custom snippet view, which
/// rendered the text a second time (larger, left-justified, no margins) and
/// forced a snippet card that appeared as an empty bubble while `perform()` was
/// still fetching. Returning `ProvidesDialog` alone matches the native system
/// behavior and avoids both problems.
private func watchIntersectorResult(
	_ text: String
) -> some IntentResult & ProvidesDialog {
	.result(dialog: IntentDialog(stringLiteral: text))
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
