//
//  WatchContentView.swift
//  Intersector Watch App
//
//  Created by Marco Salsiccia on 6/17/26.
//

import SwiftUI
import WatchConnectivity

private let watchLookupLoadingText = "Intersecting..."

@MainActor
private enum WatchVoiceOverAnnouncer {
	/// Speak the freshly-updated result through VoiceOver. A plain announcement
	/// posted the instant a button is activated collides with VoiceOver still
	/// speaking that button, so the system drops it — which is why users had to
	/// manually focus the Current Info row to hear the output. Marking the
	/// announcement high priority tells VoiceOver to queue it rather than discard
	/// it, and a short delay lets the activation speech settle first so it lands.
	static func reportUpdated(_ text: String) {
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(350))
			var announcement = AttributedString(text)
			announcement.accessibilitySpeechAnnouncementPriority = .high
			AccessibilityNotification.Announcement(announcement).post()
		}
	}
}

private final class WatchSettingsReceiver: NSObject, WCSessionDelegate {
	private let session: WCSession?

	override init() {
		if WCSession.isSupported() {
			session = WCSession.default
		} else {
			session = nil
		}
		super.init()
		session?.delegate = self
		session?.activate()
	}

	func session(
		_ session: WCSession,
		activationDidCompleteWith activationState: WCSessionActivationState,
		error: Error?
	) {
		guard activationState == .activated else {
			return
		}
		let settings = session.receivedApplicationContext
		DispatchQueue.main.async {
			self.apply(settings)
		}
	}

	func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
		DispatchQueue.main.async {
			self.apply(applicationContext)
		}
	}

	private func apply(_ settings: [String: Any]) {
		let defaults = UserDefaults.standard
		setString("areaMode", from: settings, in: defaults)
		setString("measurementUnit", from: settings, in: defaults)
		setString("directionStyle", from: settings, in: defaults)
		setInt("spokenIntersectionCount", from: settings, in: defaults)
		setBool("includeAnnouncementDistance", from: settings, in: defaults)
		setBool("includeAnnouncementDirection", from: settings, in: defaults)
		setBool("includeAnnouncementNeighborhood", from: settings, in: defaults)
		setBool("includeIntersectionDetails", from: settings, in: defaults)
		setBool("includeCrossings", from: settings, in: defaults)
		setBool("includeWalkingPaths", from: settings, in: defaults)
		setBool("manhattanSnobMode", from: settings, in: defaults)
	}

	private func setString(_ key: String, from settings: [String: Any], in defaults: UserDefaults) {
		guard let value = settings[key] as? String else {
			return
		}
		defaults.set(value, forKey: key)
	}

	private func setInt(_ key: String, from settings: [String: Any], in defaults: UserDefaults) {
		guard let value = settings[key] as? Int else {
			return
		}
		defaults.set(value, forKey: key)
	}

	private func setBool(_ key: String, from settings: [String: Any], in defaults: UserDefaults) {
		guard let value = settings[key] as? Bool else {
			return
		}
		defaults.set(value, forKey: key)
	}
}

struct WatchContentView: View {
	@AppStorage("areaMode") private var areaModeRaw = WatchAreaMode.near.rawValue
	@AppStorage("measurementUnit") private var measurementUnitRaw = WatchMeasurementUnit.feet.rawValue
	@AppStorage("directionStyle") private var directionStyleRaw = WatchDirectionStyle.words.rawValue
	@AppStorage("spokenIntersectionCount") private var spokenIntersectionCountRaw = WatchSpokenIntersectionCount.one.rawValue
	@AppStorage("includeAnnouncementDistance") private var includeAnnouncementDistance = true
	@AppStorage("includeAnnouncementDirection") private var includeAnnouncementDirection = true
	@AppStorage("includeAnnouncementNeighborhood") private var includeAnnouncementNeighborhood = false
	@AppStorage("includeIntersectionDetails") private var includeIntersectionDetails = false
	@AppStorage("includeCrossings") private var includeCrossings = false
	@AppStorage("includeWalkingPaths") private var includeWalkingPaths = false
	@AppStorage("manhattanSnobMode") private var manhattanSnobMode = false
	@State private var statusText = "Choose an action."
	@State private var isLoading = false
	@State private var isDirectionLoading = false
	@State private var isShowingSettings = false
	@State private var settingsReceiver = WatchSettingsReceiver()

	private var prefs: WatchAppPrefs {
		WatchAppPrefs(
			areaMode: selectedAreaMode,
			measurementUnit: WatchMeasurementUnit(rawValue: measurementUnitRaw) ?? .feet,
			directionStyle: WatchDirectionStyle(rawValue: directionStyleRaw) ?? .words,
			intersectionWording: .direct,
			spokenIntersectionCount: WatchSpokenIntersectionCount(rawValue: spokenIntersectionCountRaw) ?? .one,
			announcementOptions: WatchAnnouncementOptions(
				includeDistance: includeAnnouncementDistance,
				includeDirection: includeAnnouncementDirection,
				includeNeighborhood: includeAnnouncementNeighborhood,
				includeIntersectionDetails: includeIntersectionDetails
			),
			mapDetails: WatchMapDetailOptions(
				includeCrossings: includeCrossings,
				includeWalkingPaths: includeWalkingPaths
			),
			manhattanSnobMode: manhattanSnobMode
		)
	}

	private var selectedAreaMode: WatchAreaMode {
		let mode = WatchAreaMode(rawValue: areaModeRaw) ?? .near
		return mode == .off ? .near : mode
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 8) {
					headerView
					statusView
					actionButton(
						"Nearest",
						systemImage: "location.fill",
						accessibilityLabel: "Nearest Intersection"
					) {
						await update(.nearest)
					}
					.accessibilityAction(named: Text("3rd Nearest Intersection")) {
						Task {
							await update(.nearest, rank: 3)
						}
					}
					.accessibilityAction(named: Text("2nd Nearest Intersection")) {
						Task {
							await update(.nearest, rank: 2)
						}
					}
					actionButton(
						"Upcoming",
						systemImage: "arrow.up.circle.fill",
						accessibilityLabel: "Upcoming Intersection"
					) {
						await update(.upcoming)
					}
					.accessibilityAction(named: Text("3rd Upcoming Intersection")) {
						Task {
							await update(.upcoming, rank: 3)
						}
					}
					.accessibilityAction(named: Text("2nd Upcoming Intersection")) {
						Task {
							await update(.upcoming, rank: 2)
						}
					}
					actionButton(
						"Direction",
						systemImage: "safari.fill",
						accessibilityLabel: "My Direction",
						accessibilityHint: "Speaks cardinal direction.",
						isDisabled: isDirectionLoading
					) {
						await updateDirection()
					}
				}
				.frame(maxWidth: .infinity)
				.padding(.bottom, 8)
			}
			.background(Color.watchCrossBg)
			.toolbar {
				ToolbarItem(placement: .automatic) {
					Button {
						isShowingSettings = true
					} label: {
						Image(systemName: "gearshape")
					}
					.accessibilityLabel("Settings")
					.accessibilityHint("Shows settings synced from iPhone.")
				}
			}
			.sheet(isPresented: $isShowingSettings) {
				settingsView
			}
		}
		.tint(Color.watchCrossAccent)
	}

	private var headerView: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Intersector")
				.font(.title3)
				.fontWeight(.bold)
				.foregroundStyle(Color.watchCrossText)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 10)
		.padding(.top, 6)
	}

	private var statusView: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Current Info")
				.font(.headline)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)
			Text(statusText)
				.font(.body)
				.foregroundStyle(Color.watchCrossInv)
				.multilineTextAlignment(.leading)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(Color.watchCrossPanel)
	}

	private var settingsView: some View {
		NavigationStack {
			Form {
				Section {
					Text("Settings sync from iPhone")
						.font(.headline)
						.foregroundStyle(Color.watchCrossText)
						.accessibilityAddTraits(.isHeader)
					Text("Open Intersector on iPhone to change announcement settings.")
						.font(.footnote)
						.foregroundStyle(Color.watchCrossText)
						.lineLimit(nil)
						.fixedSize(horizontal: false, vertical: true)
					Text("Sample Announcement")
						.font(.headline)
						.foregroundStyle(Color.watchCrossText)
						.accessibilityAddTraits(.isHeader)
					Text(announcementSampleText)
						.font(.footnote)
						.foregroundStyle(Color.watchCrossText)
						.lineLimit(nil)
						.fixedSize(horizontal: false, vertical: true)
				} header: {
					Text("Announcements")
				}
			}
			.scrollContentBackground(.hidden)
			.background(Color.watchCrossBg)
			.navigationTitle("Settings")
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						isShowingSettings = false
					}
				}
			}
		}
	}

	private var announcementSampleText: String {
		let report = WatchOrientationReport(
			kind: .nearest,
			cross: "Crossing on Amsterdam Avenue near West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			crossStreet: nil,
			head: "north",
			area: "Upper West Side",
			toward: "Manhattan Valley",
			intersectionDetails: WatchIntersectionDetails(
				isSignalized: true,
				hasPedestrianIsland: true
			)
		)
		return "Sample: \(report.text(with: prefs))"
	}

	private func actionButton(
		_ title: String,
		systemImage: String,
		accessibilityLabel: String? = nil,
		accessibilityHint: String? = nil,
		isDisabled: Bool? = nil,
		action: @escaping () async -> Void
	) -> some View {
		Button {
			Task {
				await action()
			}
		} label: {
			Label {
				Text(title)
					.multilineTextAlignment(.center)
					.lineLimit(nil)
					.fixedSize(horizontal: false, vertical: true)
			} icon: {
				Image(systemName: systemImage)
			}
			.font(.headline)
			.fontWeight(.semibold)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
			.padding(.horizontal, 10)
			.contentShape(Rectangle())
		}
		.buttonStyle(WatchIntersectorActionButtonStyle())
		.disabled(isDisabled ?? isLoading)
		.accessibilityLabel(accessibilityLabel ?? title)
		.accessibilityHint(accessibilityHint ?? "")
	}

	private func update(_ kind: WatchReportKind, rank: Int = 1) async {
		guard !isLoading else {
			return
		}
		isLoading = true
		let showsProgressImmediately = rank > 1
		if showsProgressImmediately {
			statusText = watchLookupLoadingText
		}
		let loadingTask = Task { @MainActor in
			do {
				try await Task.sleep(for: .milliseconds(800))
				guard !showsProgressImmediately else {
					return
				}
				statusText = watchLookupLoadingText
			} catch {}
		}
		do {
			let text = if rank == 1 {
				try await WatchOrientationService().spokenText(kind, prefs: prefs)
			} else {
				try await WatchOrientationService().report(kind, rank: rank, prefs: prefs).text(with: prefs, rank: rank)
			}
			loadingTask.cancel()
			statusText = text
			WatchVoiceOverAnnouncer.reportUpdated(text)
		} catch {
			loadingTask.cancel()
			let text = reportFailureText(kind, rank: rank)
			statusText = text
			WatchVoiceOverAnnouncer.reportUpdated(text)
		}
		isLoading = false
	}

	private func reportFailureText(_ kind: WatchReportKind, rank: Int) -> String {
		if rank > 1 {
			return "Intersector could not find the \(rankedFailureLabel(kind, rank: rank)). Please try again."
		}
		return "Intersector is having trouble loading map data. Please try again."
	}

	private func rankedFailureLabel(_ kind: WatchReportKind, rank: Int) -> String {
		switch kind {
		case .nearest:
			return "\(ordinal(rank)) Nearest intersection"
		case .upcoming:
			return "\(ordinal(rank)) Upcoming intersection"
		}
	}

	private func updateDirection() async {
		guard !isDirectionLoading else {
			return
		}
		isDirectionLoading = true
		let text = await IntersectorWatchReporter.directionText(prefs: prefs)
		statusText = text
		WatchVoiceOverAnnouncer.reportUpdated(text)
		isDirectionLoading = false
	}

	private func reportLabel(_ kind: WatchReportKind, rank: Int) -> String {
		guard rank > 1 else {
			return kind.intentLabel
		}
		return "\(ordinal(rank)) \(kind.intentLabel)"
	}

	private func ordinal(_ value: Int) -> String {
		switch value {
		case 2:
			"2nd"
		case 3:
			"3rd"
		default:
			"\(value)th"
		}
	}
}

private struct WatchIntersectorActionButtonStyle: ButtonStyle {
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.foregroundStyle(Color.watchCrossButtonText)
			.background(Color.watchCrossBtn)
			.overlay(Rectangle().stroke(Color.watchCrossButtonBorder, lineWidth: 1))
			.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
			.scaleEffect(configuration.isPressed ? 0.985 : 1)
	}
}

extension Color {
	static let watchCrossBg = Color(red: 0.02, green: 0.02, blue: 0.02)
	static let watchCrossBtn = Color(red: 1.00, green: 0.80, blue: 0.18)
	static let watchCrossPanel = Color(red: 0.12, green: 0.12, blue: 0.12)
	static let watchCrossText = Color(red: 0.98, green: 0.98, blue: 0.96)
	static let watchCrossButtonText = Color(red: 0.02, green: 0.02, blue: 0.02)
	static let watchCrossButtonBorder = Color(red: 0.42, green: 0.28, blue: 0.00)
	static let watchCrossInv = Color(red: 0.98, green: 0.98, blue: 0.96)
	static let watchCrossAccent = Color(red: 1.00, green: 0.80, blue: 0.18)
}

#if DEBUG
	#Preview {
		WatchContentView()
	}
#endif
