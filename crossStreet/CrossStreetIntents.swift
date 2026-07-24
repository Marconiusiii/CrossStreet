//
//  IntersectorIntents.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import AppIntents
import CoreLocation
import Foundation

/// Returns the spoken announcement as a plain dialog only. Siri speaks it and
/// shows its own native dialog bubble — one correctly-formatted copy of the
/// text. Earlier attempts paired the dialog with a custom snippet view, which
/// rendered the text a second time (larger, left-justified, no margins) and
/// forced a snippet card that appeared as an empty bubble while `perform()` was
/// still fetching. Returning `ProvidesDialog` alone matches the native system
/// behavior and avoids both problems.
private func intersectorResult(
	_ text: String
) -> some IntentResult & ProvidesDialog {
	.result(dialog: IntentDialog(stringLiteral: text))
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
