//
//  ContentView.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import AVFoundation
import Darwin
import MessageUI
import SwiftUI
import UIKit
import WatchConnectivity

private enum SettingsFocusTarget: Hashable {
	case displayLayout
	case neighborhood
	case crossings
	case walkingPaths
	case measurementUnit
	case direction
	case announcementDistance
	case announcementDirection
	case announcementNeighborhood
	case intersectionDetails
	case spokenIntersections
	case rankedControls
	case manhattanSnobMode
	case haptics
}

private enum DisplayLayout: String, CaseIterable, Identifiable {
	case standard
	case centered

	var id: String { rawValue }

	var label: String {
		switch self {
		case .standard:
			"Default"
		case .centered:
			"Centered"
		}
	}
}

private let lookupLoadingText = "Intersecting..."
private let startupLoadingText = "Loading Intersector."
private let mapPreparationText = "Preparing map data for Nearest and Upcoming."
private let mapWaitingText = "Waiting for map data. Nearest and Upcoming will become available automatically."
private let readyText = "Intersector Ready."

@MainActor
private enum IntersectorAudioSession {
	static func prepareForFeedback() {
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(
				.playback,
				mode: .default,
				options: [.duckOthers]
			)
			try session.setActive(true)
		} catch {}
	}
}

@MainActor
private enum LoadingThrobber {
	private static var player: AVAudioPlayer?
	private static var hapticTask: Task<Void, Never>?
	private static let loopDuration: TimeInterval = 2.20

	static func start(hapticsEnabled: Bool) {
		do {
			IntersectorAudioSession.prepareForFeedback()
			if player == nil {
				player = try AVAudioPlayer(data: cueData())
				player?.volume = 0.42
				player?.numberOfLoops = -1
				player?.prepareToPlay()
			}
			player?.currentTime = 0
			player?.play()
		} catch {}
		startHapticsIfNeeded(hapticsEnabled)
	}

	static func stop() {
		player?.stop()
		player?.currentTime = 0
		hapticTask?.cancel()
		hapticTask = nil
	}

	private static func cueData() -> Data {
		let sampleRate = 22_050
		let duration = loopDuration
		let frameCount = Int(Double(sampleRate) * duration)
		let dataSize = frameCount * MemoryLayout<Int16>.size
		var data = Data()
		data.append(contentsOf: "RIFF".utf8)
		data.append(UInt32(36 + dataSize).littleEndianData)
		data.append(contentsOf: "WAVEfmt ".utf8)
		data.append(UInt32(16).littleEndianData)
		data.append(UInt16(1).littleEndianData)
		data.append(UInt16(1).littleEndianData)
		data.append(UInt32(sampleRate).littleEndianData)
		data.append(UInt32(sampleRate * MemoryLayout<Int16>.size).littleEndianData)
		data.append(UInt16(MemoryLayout<Int16>.size).littleEndianData)
		data.append(UInt16(16).littleEndianData)
		data.append(contentsOf: "data".utf8)
		data.append(UInt32(dataSize).littleEndianData)

		var samples: [Double] = []
		samples.reserveCapacity(frameCount)
		for index in 0..<frameCount {
			let time = Double(index) / Double(sampleRate)
			let pad = padValue(time: time, duration: duration) * 0.16
			let pulses = pulseValue(
				time: time,
				start: 0.12,
				attack: 0.025,
				decay: 0.20,
				sustain: 0.05,
				frequency: 660
			) + pulseValue(
				time: time,
				start: 0.48,
				attack: 0.03,
				decay: 0.24,
				sustain: 0.07,
				frequency: 330
			) + pulseValue(
				time: time,
				start: 0.86,
				attack: 0.03,
				decay: 0.36,
				sustain: 0,
				frequency: 494
			)
			samples.append(pad + pulses)
		}

		let echoedSamples = samples.addingEcho(
			sampleRate: sampleRate,
			taps: [
				(delay: 0.14, gain: 0.24),
				(delay: 0.31, gain: 0.11)
			]
		)
		for value in echoedSamples {
			let sample = Int16(max(-1, min(1, value)) * 2_300)
			data.append(sample.littleEndianData)
		}

		return data
	}

	private static func startHapticsIfNeeded(_ isEnabled: Bool) {
		hapticTask?.cancel()
		guard isEnabled else {
			hapticTask = nil
			return
		}
		hapticTask = Task { @MainActor in
			let pulses: [(offset: TimeInterval, intensity: Double)] = [
				(0.12, 0.95),
				(0.48, 0.55),
				(0.86, 0.25)
			]
			var firedPulseIndexes = Set<Int>()
			var previousPlaybackTime: TimeInterval = 0
			while !Task.isCancelled {
				guard
					let player,
					player.isPlaying
				else {
					try? await Task.sleep(for: .milliseconds(20))
					continue
				}
				let playbackTime = player.currentTime
				if playbackTime < previousPlaybackTime || playbackTime < 0.08 {
					firedPulseIndexes.removeAll()
				}
				for (index, pulse) in pulses.enumerated() where
					playbackTime >= pulse.offset &&
					previousPlaybackTime < pulse.offset &&
					!firedPulseIndexes.contains(index)
				{
					HapticFeedback().pulse(intensity: pulse.intensity)
					firedPulseIndexes.insert(index)
				}
				previousPlaybackTime = playbackTime
				try? await Task.sleep(for: .milliseconds(16))
			}
		}
	}

	private static func padValue(time: Double, duration: Double) -> Double {
		let fadeIn = min(1, time / 0.36)
		let fadeOut = min(1, max(0, (1.55 - time) / 0.45))
		let envelope = max(0, min(fadeIn, fadeOut))
		let base = sin(2 * Double.pi * 247 * time)
		let shimmer = sin(2 * Double.pi * 330 * time) * 0.35
		return (base + shimmer) * envelope * 0.14
	}

	private static func pulseValue(
		time: Double,
		start: Double,
		attack: Double,
		decay: Double,
		sustain: Double,
		frequency: Double
	) -> Double {
		let duration = attack + decay + sustain
		guard time >= start, time <= start + duration else {
			return 0
		}
		let localTime = time - start
		let envelope: Double
		if localTime <= attack {
			envelope = localTime / attack
		} else if localTime <= attack + sustain {
			envelope = 1
		} else {
			let decayProgress = (localTime - attack - sustain) / decay
			envelope = max(0, 1 - decayProgress)
		}
		let angle = 2 * Double.pi * frequency * localTime
		return sin(angle) * envelope * 0.78
	}
}

private extension FixedWidthInteger {
	var littleEndianData: Data {
		var value = littleEndian
		return Data(bytes: &value, count: MemoryLayout<Self>.size)
	}
}

@MainActor
private enum ReadyEarcon {
	private static var player: AVAudioPlayer?
	private static var hapticTask: Task<Void, Never>?
	private static let noteStarts: [TimeInterval] = [0.16, 0.52, 0.92]

	static func play(hapticsEnabled: Bool) {
		do {
			IntersectorAudioSession.prepareForFeedback()
			player = try AVAudioPlayer(data: cueData())
			player?.volume = 0.42
			player?.prepareToPlay()
			player?.play()
		} catch {}
		playHapticsIfNeeded(hapticsEnabled)
	}

	private static func cueData() -> Data {
		let sampleRate = 22_050
		let duration = 1.42
		let frameCount = Int(Double(sampleRate) * duration)
		let dataSize = frameCount * MemoryLayout<Int16>.size
		var data = Data()
		data.append(contentsOf: "RIFF".utf8)
		data.append(UInt32(36 + dataSize).littleEndianData)
		data.append(contentsOf: "WAVEfmt ".utf8)
		data.append(UInt32(16).littleEndianData)
		data.append(UInt16(1).littleEndianData)
		data.append(UInt16(1).littleEndianData)
		data.append(UInt32(sampleRate).littleEndianData)
		data.append(UInt32(sampleRate * MemoryLayout<Int16>.size).littleEndianData)
		data.append(UInt16(MemoryLayout<Int16>.size).littleEndianData)
		data.append(UInt16(16).littleEndianData)
		data.append(contentsOf: "data".utf8)
		data.append(UInt32(dataSize).littleEndianData)

		var samples: [Double] = []
		samples.reserveCapacity(frameCount)
		for index in 0..<frameCount {
			let time = Double(index) / Double(sampleRate)
			let pad = readyPadValue(time: time) * 0.13
			let pulses = readyPulse(time: time, start: noteStarts[0], frequency: 494, gain: 0.58)
				+ readyPulse(time: time, start: noteStarts[1], frequency: 660, gain: 0.68)
				+ readyPulse(time: time, start: noteStarts[2], frequency: 988, gain: 0.76)
			samples.append(pad + pulses)
		}

		let echoedSamples = samples.addingEcho(
			sampleRate: sampleRate,
			taps: [
				(delay: 0.15, gain: 0.22),
				(delay: 0.34, gain: 0.10)
			]
		)
		for value in echoedSamples {
			let sample = Int16(max(-1, min(1, value)) * 2_900)
			data.append(sample.littleEndianData)
		}
		return data
	}

	private static func readyPadValue(time: Double) -> Double {
		let fadeIn = min(1, time / 0.24)
		let fadeOut = min(1, max(0, (1.34 - time) / 0.38))
		let envelope = max(0, min(fadeIn, fadeOut))
		let base = sin(2 * Double.pi * 247 * time)
		let shimmer = sin(2 * Double.pi * 370 * time) * 0.32
		return (base + shimmer) * envelope * 0.15
	}

	private static func readyPulse(
		time: Double,
		start: Double,
		frequency: Double,
		gain: Double
	) -> Double {
		let attack = 0.028
		let sustain = 0.08
		let decay = 0.24
		let duration = attack + sustain + decay
		guard time >= start, time <= start + duration else {
			return 0
		}
		let localTime = time - start
		let envelope: Double
		if localTime <= attack {
			envelope = localTime / attack
		} else if localTime <= attack + sustain {
			envelope = 1
		} else {
			let decayProgress = (localTime - attack - sustain) / decay
			envelope = max(0, 1 - decayProgress)
		}
		let angle = 2 * Double.pi * frequency * localTime
		return sin(angle) * envelope * gain
	}

	private static func playHapticsIfNeeded(_ isEnabled: Bool) {
		hapticTask?.cancel()
		guard isEnabled else {
			hapticTask = nil
			return
		}
		hapticTask = Task { @MainActor in
			let clock = ContinuousClock()
			let startTime = clock.now
			let pulses: [(offset: Duration, intensity: Double)] = [
				(.milliseconds(Int(noteStarts[0] * 1_000)), 0.25),
				(.milliseconds(Int(noteStarts[1] * 1_000)), 0.55),
				(.milliseconds(Int(noteStarts[2] * 1_000)), 0.95)
			]
			for pulse in pulses {
				let targetTime = startTime + pulse.offset
				if clock.now < targetTime {
					try? await Task.sleep(until: targetTime, clock: clock)
				}
				guard !Task.isCancelled else { return }
				HapticFeedback().pulse(intensity: pulse.intensity)
			}
		}
	}
}

private extension Array where Element == Double {
	func addingEcho(
		sampleRate: Int,
		taps: [(delay: Double, gain: Double)]
	) -> [Double] {
		var echoed = self
		for tap in taps {
			let delayFrames = Int(tap.delay * Double(sampleRate))
			guard delayFrames > 0 else {
				continue
			}
			for index in delayFrames..<count {
				echoed[index] += self[index - delayFrames] * tap.gain
			}
		}
		return echoed
	}
}

private struct WatchSettingsPayload {
	let areaMode: String
	let measurementUnit: String
	let directionStyle: String
	let spokenIntersectionCount: Int
	let includeAnnouncementDistance: Bool
	let includeAnnouncementDirection: Bool
	let includeAnnouncementNeighborhood: Bool
	let includeIntersectionDetails: Bool
	let includeCrossings: Bool
	let includeWalkingPaths: Bool
	let manhattanSnobMode: Bool

	var signature: String {
		[
			areaMode,
			measurementUnit,
			directionStyle,
			String(spokenIntersectionCount),
			String(includeAnnouncementDistance),
			String(includeAnnouncementDirection),
			String(includeAnnouncementNeighborhood),
			String(includeIntersectionDetails),
			String(includeCrossings),
			String(includeWalkingPaths),
			String(manhattanSnobMode)
		].joined(separator: "|")
	}

	var dictionary: [String: Any] {
		[
			"areaMode": areaMode,
			"measurementUnit": measurementUnit,
			"directionStyle": directionStyle,
			"spokenIntersectionCount": spokenIntersectionCount,
			"includeAnnouncementDistance": includeAnnouncementDistance,
			"includeAnnouncementDirection": includeAnnouncementDirection,
			"includeAnnouncementNeighborhood": includeAnnouncementNeighborhood,
			"includeIntersectionDetails": includeIntersectionDetails,
			"includeCrossings": includeCrossings,
			"includeWalkingPaths": includeWalkingPaths,
			"manhattanSnobMode": manhattanSnobMode
		]
	}
}

private final class WatchSettingsSync: NSObject, WCSessionDelegate {
	private let session: WCSession?
	private var pendingPayload: WatchSettingsPayload?

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

	func sync(_ payload: WatchSettingsPayload) {
		pendingPayload = payload
		guard let session, session.activationState == .activated else {
			return
		}
		do {
			try session.updateApplicationContext(payload.dictionary)
		} catch {
			pendingPayload = payload
		}
	}

	func session(
		_ session: WCSession,
		activationDidCompleteWith activationState: WCSessionActivationState,
		error: Error?
	) {
		guard activationState == .activated, let pendingPayload else {
			return
		}
		sync(pendingPayload)
	}

	func sessionDidBecomeInactive(_ session: WCSession) {}

	func sessionDidDeactivate(_ session: WCSession) {
		session.activate()
	}
}

struct ContentView: View {
	@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
	@AppStorage("areaMode") private var areaModeRaw = AreaMode.near.rawValue
	@AppStorage("measurementUnit") private var measurementUnitRaw = MeasurementUnit.feet.rawValue
	@AppStorage("directionStyle") private var directionStyleRaw = DirectionStyle.words.rawValue
	@AppStorage("spokenIntersectionCount") private var spokenIntersectionCountRaw = SpokenIntersectionCount.one.rawValue
	@AppStorage("includeAnnouncementDistance") private var includeAnnouncementDistance = true
	@AppStorage("includeAnnouncementDirection") private var includeAnnouncementDirection = true
	@AppStorage("includeAnnouncementNeighborhood") private var includeAnnouncementNeighborhood = false
	@AppStorage("includeIntersectionDetails") private var includeIntersectionDetails = false
	@AppStorage("includeCrossings") private var includeCrossings = false
	@AppStorage("includeWalkingPaths") private var includeWalkingPaths = false
	@AppStorage("hapticsEnabled") private var hapticsEnabled = true
	@AppStorage("manhattanSnobMode") private var manhattanSnobMode = false
	@AppStorage("showRankedControls") private var showRankedControls = true
	@AppStorage("displayLayout") private var displayLayoutRaw = DisplayLayout.standard.rawValue
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
	@Environment(\.openURL) private var openURL
	@Environment(\.scenePhase) private var scenePhase
	@ScaledMetric(relativeTo: .body) private var statusMinHeight: CGFloat = 112
	@ScaledMetric(relativeTo: .title2) private var actionMinHeight: CGFloat = 76
	@State private var statusText = "Choose an action."
	@State private var isLoading = false
	@State private var isDirectionLoading = false
	@State private var isStartupLoading = false
	@State private var isMapPreparationLoading = false
	@State private var isMapDataReady = false
	@State private var isLookupProgressVisible = false
	@State private var isShowingSettings = false
	@State private var isShowingHelp = false
	@State private var isShowingMailComposer = false
	@State private var hasPreparedInitialLocation = false
	@State private var startupTask: Task<Void, Never>?
	@State private var onboardingLocationProvider = LocationProvider()
	@State private var directionLocationProvider = LocationProvider()
	@StateObject private var pointScanner = PointScanController()
	@State private var watchSettingsSync = WatchSettingsSync()
	@AccessibilityFocusState private var settingsFocusTarget: SettingsFocusTarget?

	private var prefs: AppPrefs {
		AppPrefs(
			areaMode: selectedAreaMode,
			measurementUnit: MeasurementUnit(rawValue: measurementUnitRaw) ?? .feet,
			directionStyle: DirectionStyle(rawValue: directionStyleRaw) ?? .words,
			intersectionWording: .direct,
			spokenIntersectionCount: SpokenIntersectionCount(rawValue: spokenIntersectionCountRaw) ?? .one,
			announcementOptions: AnnouncementOptions(
				includeDistance: includeAnnouncementDistance,
				includeDirection: includeAnnouncementDirection,
				includeNeighborhood: includeAnnouncementNeighborhood,
				includeIntersectionDetails: includeIntersectionDetails
			),
			mapDetails: MapDetailOptions(
				includeCrossings: includeCrossings,
				includeWalkingPaths: includeWalkingPaths
			),
			haptics: hapticsEnabled,
			manhattanSnobMode: manhattanSnobMode
		)
	}

	private var watchSettingsPayload: WatchSettingsPayload {
		WatchSettingsPayload(
			areaMode: selectedAreaMode.rawValue,
			measurementUnit: measurementUnitRaw,
			directionStyle: directionStyleRaw,
			spokenIntersectionCount: spokenIntersectionCountRaw,
			includeAnnouncementDistance: includeAnnouncementDistance,
			includeAnnouncementDirection: includeAnnouncementDirection,
			includeAnnouncementNeighborhood: includeAnnouncementNeighborhood,
			includeIntersectionDetails: includeIntersectionDetails,
			includeCrossings: includeCrossings,
			includeWalkingPaths: includeWalkingPaths,
			manhattanSnobMode: manhattanSnobMode
		)
	}

	private var displayLayout: DisplayLayout {
		DisplayLayout(rawValue: displayLayoutRaw) ?? .standard
	}

	private var selectedAreaMode: AreaMode {
		let mode = AreaMode(rawValue: areaModeRaw) ?? .near
		return mode == .off ? .near : mode
	}

	private var mapReadinessSignature: String {
		"\(includeCrossings)-\(includeWalkingPaths)"
	}

	private var usesCenteredStatusLayout: Bool {
		displayLayout == .centered || dynamicTypeSize.isAccessibilitySize
	}

	var body: some View {
		Group {
			if hasCompletedOnboarding {
				mainView
			} else {
				OnboardingView(locationProvider: onboardingLocationProvider) {
					hasCompletedOnboarding = true
				}
			}
		}
		.tint(Color.crossAccent)
	}

	private var mainView: some View {
		NavigationStack {
			GeometryReader { geometry in
				ScrollView {
					VStack(spacing: 0) {
						headerView
						statusView
						Group {
							if showRankedControls {
								rankedActionRow(
									primary: nearestButton,
									menu: rankedMenu(
										title: "More Nearest",
										actions: [
											("2nd", { await updateReport(.nearest, rank: 2) }),
											("3rd", { await updateReport(.nearest, rank: 3) })
										]
									)
								)
							} else {
								nearestButton
							}
						}
						.frame(minHeight: actionMinHeight)
						Group {
							if showRankedControls {
								rankedActionRow(
									primary: upcomingButton,
									menu: rankedMenu(
										title: "More Upcoming",
										actions: [
											("2nd", { await updateReport(.upcoming, rank: 2) }),
											("3rd", { await updateReport(.upcoming, rank: 3) })
										]
									)
								)
							} else {
								upcomingButton
							}
						}
						.frame(minHeight: actionMinHeight)
						actionButton(
							"Direction",
							systemImage: "safari.fill",
							accessibilityLabel: "My Direction",
							accessibilityHint: "Speaks cardinal direction.",
							isDisabled: isDirectionLoading || isStartupLoading
						) {
							await updateDirection()
						}
						.frame(minHeight: actionMinHeight)
						pointScanToggle
					}
					.frame(maxWidth: .infinity)
					.frame(minHeight: geometry.size.height, alignment: .top)
				}
			}
			.background(Color.crossBg)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar(.hidden, for: .navigationBar)
			.sheet(isPresented: $isShowingSettings) {
				settingsView
			}
			.onAppear {
				if areaModeRaw == AreaMode.off.rawValue {
					areaModeRaw = AreaMode.near.rawValue
				}
				if !startRequestedPointScanIfNeeded() {
					prepareInitialLocationIfNeeded()
				}
				watchSettingsSync.sync(watchSettingsPayload)
			}
			.onChange(of: watchSettingsPayload.signature) { _, _ in
				watchSettingsSync.sync(watchSettingsPayload)
			}
			.onChange(of: mapReadinessSignature) { _, _ in
				restartInitialPreparation()
			}
			.onChange(of: scenePhase) { _, phase in
				if phase != .active {
					pointScanner.stopScanning()
				}
			}
		}
	}

	private var headerView: some View {
		HStack(alignment: .center, spacing: 0) {
			appTitle
			settingsButton
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.crossBg)
		.tint(Color.crossAccent)
	}

	private var appTitle: some View {
		Text("Intersector")
			.font(.largeTitle)
			.fontWeight(.bold)
			.foregroundStyle(Color.crossText)
			.lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.leading, 16)
			.padding(.trailing, 8)
			.padding(.vertical, 6)
			.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
			.contentShape(Rectangle())
			.accessibilityAddTraits(.isHeader)
	}

	private var settingsButton: some View {
		Button {
			isShowingSettings = true
		} label: {
			Text("Settings")
				.font(.body)
				.fontWeight(.semibold)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
				.padding(.horizontal, 14)
				.padding(.vertical, 6)
				.frame(minWidth: 96, minHeight: 56, alignment: .center)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.foregroundStyle(Color.crossAccent)
	}

	private var statusView: some View {
		Group {
			if usesCenteredStatusLayout {
				VStack(alignment: .center, spacing: 0) {
					currentInfoHeading(alignment: .center, isCentered: true)
					currentInfoBody(alignment: .center, textAlignment: .center)
				}
			} else {
				HStack(alignment: .top, spacing: 0) {
					currentInfoHeading(alignment: .leading, isCentered: false)
						.layoutPriority(1)
					currentInfoBody(alignment: .leading, textAlignment: .leading)
						.layoutPriority(2)
				}
			}
		}
		.frame(maxWidth: .infinity, minHeight: statusMinHeight, alignment: usesCenteredStatusLayout ? .center : .topLeading)
		.background(Color.crossPanel)
		.overlay(alignment: .topTrailing) {
			loadingStatusOverlay
				.padding(.top, 10)
				.padding(.trailing, 10)
		}
		.contentShape(Rectangle())
	}

	private func currentInfoHeading(
		alignment: Alignment,
		isCentered: Bool
	) -> some View {
		HStack(alignment: .center, spacing: 8) {
			Text("Current Info")
				.font(.title2)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.fixedSize(horizontal: true, vertical: false)
				.accessibilityAddTraits(.isHeader)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.frame(maxWidth: isCentered ? .infinity : nil, minHeight: 60, alignment: alignment)
		.contentShape(Rectangle())
	}

	private func currentInfoText(
		alignment: Alignment,
		textAlignment: TextAlignment
	) -> some View {
		Text(statusText)
			.font(.body)
			.foregroundStyle(Color.crossInv)
			.multilineTextAlignment(textAlignment)
			.lineLimit(nil)
			.textSelection(.enabled)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
			.frame(maxWidth: .infinity, minHeight: 60, alignment: alignment)
			.contentShape(Rectangle())
	}

	private func currentInfoBody(
		alignment: Alignment,
		textAlignment: TextAlignment
	) -> some View {
		currentInfoText(alignment: alignment, textAlignment: textAlignment)
	}

	@ViewBuilder
	private var loadingStatusOverlay: some View {
		let isVisible = isStartupLoading || isMapPreparationLoading || isLookupProgressVisible
		HStack(spacing: 8) {
			statusActivityIndicator
			if isLookupProgressVisible {
				Text(lookupLoadingText)
					.font(.caption)
					.fontWeight(.semibold)
					.foregroundStyle(Color.crossAccent)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(Color.crossBg.opacity(0.94), in: Capsule())
		.overlay(Capsule().stroke(Color.crossAccent.opacity(0.72), lineWidth: 1))
		.shadow(color: Color.black.opacity(0.22), radius: 3, x: 0, y: 1)
		.opacity(isVisible ? 1 : 0)
		.animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: isVisible)
		.accessibilityHidden(true)
	}

	@ViewBuilder
	private var statusActivityIndicator: some View {
		Group {
			if accessibilityReduceMotion {
				Image(systemName: "hourglass")
					.imageScale(.small)
					.foregroundStyle(Color.crossAccent)
			} else {
				ProgressView()
					.tint(Color.crossAccent)
					.controlSize(.regular)
			}
		}
		.frame(width: 24, height: 24)
		.accessibilityHidden(true)
	}

	private var nearestButton: some View {
		actionButton(
			"Nearest",
			systemImage: "location.fill",
			accessibilityLabel: "Nearest Intersection",
			isDisabled: isLoading || isStartupLoading || !isMapDataReady || pointScanner.isScanning || pointScanner.isPreparing,
			drawsChrome: !showRankedControls
		) {
			await updateReport(.nearest)
		}
		.accessibilityAction(named: Text("3rd Nearest Intersection")) {
			Task {
				await updateReport(.nearest, rank: 3)
			}
		}
		.accessibilityAction(named: Text("2nd Nearest Intersection")) {
			Task {
				await updateReport(.nearest, rank: 2)
			}
		}
	}

	private var upcomingButton: some View {
		actionButton(
			"Upcoming",
			systemImage: "arrow.up.circle.fill",
			accessibilityLabel: "Upcoming Intersection",
			isDisabled: isLoading || isStartupLoading || !isMapDataReady || pointScanner.isScanning || pointScanner.isPreparing,
			drawsChrome: !showRankedControls
		) {
			await updateReport(.upcoming)
		}
		.accessibilityAction(named: Text("3rd Upcoming Intersection")) {
			Task {
				await updateReport(.upcoming, rank: 3)
			}
		}
		.accessibilityAction(named: Text("2nd Upcoming Intersection")) {
			Task {
				await updateReport(.upcoming, rank: 2)
			}
		}
	}

	private var pointScanToggle: some View {
		Toggle(
			isOn: Binding(
				get: { pointScanner.isScanning || pointScanner.isPreparing },
				set: { enabled in
					pointScanner.setScanning(enabled, prefs: prefs) { text in
						statusText = text
					}
				}
			)
		) {
			actionLabel("Scan", systemImage: "dot.radiowaves.left.and.right")
				.padding(.horizontal, 6)
		}
		.toggleStyle(.button)
		.frame(maxWidth: .infinity, minHeight: actionMinHeight, alignment: .center)
		.foregroundStyle(Color.crossButtonText)
		.background(pointScanBackground)
		.overlay(Rectangle().stroke(Color.crossButtonStrongBorder, lineWidth: 3))
		.shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
		.contentShape(Rectangle())
		.disabled(isLoading || isStartupLoading)
		.accessibilityLabel("Point and Scan")
	}

	private var pointScanBackground: Color {
		pointScanner.isScanning || pointScanner.isPreparing ? Color.crossScanActive : Color.crossScanIdle
	}

	private func rankedActionRow(
		primary: some View,
		menu: some View
	) -> some View {
		ZStack(alignment: .trailing) {
			primary
				.frame(maxWidth: .infinity)
			menu
				.frame(width: 48, alignment: .center)
		}
		.background(Color.crossBtn)
		.overlay(Rectangle().stroke(Color.crossButtonStrongBorder, lineWidth: 2))
		.shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
		.contentShape(Rectangle())
	}

	private func rankedMenu(
		title: String,
		actions: [(String, () async -> Void)]
	) -> some View {
		Menu {
			ForEach(actions, id: \.0) { action in
				Button(action.0) {
					Task {
						await action.1()
					}
				}
			}
		} label: {
			Image(systemName: "chevron.down")
				.imageScale(.medium)
				.frame(width: 48)
				.frame(minHeight: actionMinHeight)
				.foregroundStyle(Color.crossChevron)
				.contentShape(Rectangle())
		}
		.menuStyle(.button)
		.buttonStyle(.plain)
		.disabled(isLoading || isStartupLoading || !isMapDataReady || pointScanner.isScanning || pointScanner.isPreparing)
		.accessibilityHidden(true)
	}

	private var areaModeBinding: Binding<AreaMode> {
		Binding {
			selectedAreaMode
		} set: { areaMode in
			areaModeRaw = areaMode.rawValue
			settingsFocusTarget = .neighborhood
		}
	}

	private var measurementUnitBinding: Binding<MeasurementUnit> {
		Binding {
			prefs.measurementUnit
		} set: { measurementUnit in
			measurementUnitRaw = measurementUnit.rawValue
			settingsFocusTarget = .measurementUnit
		}
	}

	private var directionStyleBinding: Binding<DirectionStyle> {
		Binding {
			prefs.directionStyle
		} set: { directionStyle in
			directionStyleRaw = directionStyle.rawValue
			settingsFocusTarget = .direction
		}
	}

	private var announcementDistanceBinding: Binding<Bool> {
		Binding {
			includeAnnouncementDistance
		} set: { isEnabled in
			includeAnnouncementDistance = isEnabled
			settingsFocusTarget = .announcementDistance
		}
	}

	private var announcementDirectionBinding: Binding<Bool> {
		Binding {
			includeAnnouncementDirection
		} set: { isEnabled in
			includeAnnouncementDirection = isEnabled
			settingsFocusTarget = .announcementDirection
		}
	}

	private var announcementNeighborhoodBinding: Binding<Bool> {
		Binding {
			includeAnnouncementNeighborhood
		} set: { isEnabled in
			if isEnabled, areaModeRaw == AreaMode.off.rawValue {
				areaModeRaw = AreaMode.near.rawValue
			}
			includeAnnouncementNeighborhood = isEnabled
			settingsFocusTarget = .announcementNeighborhood
		}
	}

	private var intersectionDetailsBinding: Binding<Bool> {
		Binding {
			includeIntersectionDetails
		} set: { isEnabled in
			includeIntersectionDetails = isEnabled
			settingsFocusTarget = .intersectionDetails
		}
	}

	private var announcementSampleText: String {
		let report = OrientReport(
			kind: .nearest,
			cross: includeCrossings
				? "Crossing on Amsterdam Avenue near West 94th Street"
				: "Amsterdam Avenue and West 94th Street",
			dist: "120 feet",
			relDir: "ahead",
			relDegrees: 0,
			street: "Amsterdam Avenue",
			crossStreet: nil,
			head: "north",
			area: "Upper West Side",
			toward: "Manhattan Valley",
			conf: .high,
			intersectionDetails: IntersectionDetails(
				isSignalized: true,
				hasPedestrianIsland: true
			)
		)
		return report.text(with: prefs)
	}

	private var spokenIntersectionCountDescription: String {
		switch prefs.spokenIntersectionCount {
		case .one:
			"Speaks one intersection."
		case .two:
			"Nearest speaks the two closest intersections. Upcoming speaks the first two intersections ahead."
		case .three:
			"Nearest speaks the three closest intersections. Upcoming speaks the first three intersections ahead."
		}
	}

	private var rankedControlsBinding: Binding<Bool> {
		Binding {
			showRankedControls
		} set: { isEnabled in
			showRankedControls = isEnabled
			settingsFocusTarget = .rankedControls
		}
	}

	private var displayLayoutBinding: Binding<DisplayLayout> {
		Binding {
			displayLayout
		} set: { layout in
			displayLayoutRaw = layout.rawValue
			settingsFocusTarget = .displayLayout
		}
	}

	private var spokenIntersectionCountBinding: Binding<SpokenIntersectionCount> {
		Binding {
			prefs.spokenIntersectionCount
		} set: { count in
			spokenIntersectionCountRaw = count.rawValue
			settingsFocusTarget = .spokenIntersections
		}
	}

	private func spokenIntersectionOptionAccessibilityLabel(_ count: SpokenIntersectionCount) -> String {
		switch count {
		case .one:
			"1 intersection"
		case .two:
			"2 intersections"
		case .three:
			"3 intersections"
		}
	}

	private var hapticsBinding: Binding<Bool> {
		Binding {
			hapticsEnabled
		} set: { isEnabled in
			hapticsEnabled = isEnabled
			settingsFocusTarget = .haptics
		}
	}

	private var manhattanSnobModeBinding: Binding<Bool> {
		Binding {
			manhattanSnobMode
		} set: { isEnabled in
			manhattanSnobMode = isEnabled
			settingsFocusTarget = .manhattanSnobMode
		}
	}

	private var crossingsBinding: Binding<Bool> {
		Binding {
			includeCrossings
		} set: { isEnabled in
			includeCrossings = isEnabled
			settingsFocusTarget = .crossings
		}
	}

	private var walkingPathsBinding: Binding<Bool> {
		Binding {
			includeWalkingPaths
		} set: { isEnabled in
			includeWalkingPaths = isEnabled
			settingsFocusTarget = .walkingPaths
		}
	}

	private var settingsView: some View {
		NavigationStack {
			GeometryReader { geometry in
				ScrollView {
					settingsContent
						.frame(maxWidth: .infinity)
						.frame(minHeight: geometry.size.height, alignment: .top)
				}
			}
			.background(Color.crossBg)
			.tint(Color.crossAccent)
			.navigationTitle("")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						isShowingSettings = false
					}
				}
			}
			.sheet(isPresented: $isShowingMailComposer) {
				MailComposerView(
					recipient: "marco@marconius.com",
					subject: "Intersector Feedback",
					body: feedbackEmailBody,
					onFinish: { _ in }
				)
			}
			.sheet(isPresented: $isShowingHelp) {
				helpView
			}
		}
	}

	private var settingsContent: some View {
		VStack(alignment: .leading, spacing: 0) {
			settingsIntroSection
			settingsDisplaySection
			settingsAnnouncementSection
			settingsRegionalWordingSection
			settingsMapDetailSection
			settingsInteractionSection
			settingsAboutSection
		}
		.frame(maxHeight: .infinity)
	}

	private var settingsIntroSection: some View {
		Group {
			settingsTitleRow
			settingsHelperText("Intersection directions and distances are estimates based on your location, device heading, and available map data. Accuracy can vary with GPS and compass conditions.")
		}
	}

	private var settingsTitleRow: some View {
		HStack(alignment: .center, spacing: 12) {
			Text("Settings")
				.font(.largeTitle)
				.fontWeight(.bold)
				.foregroundStyle(Color.crossText)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity, alignment: .leading)
				.accessibilityAddTraits(.isHeader)
			Button {
				isShowingHelp = true
			} label: {
				Text("Help")
					.font(.body)
					.fontWeight(.semibold)
					.foregroundStyle(Color.crossAccent)
					.lineLimit(1)
					.minimumScaleFactor(0.75)
					.padding(.horizontal, 14)
					.padding(.vertical, 6)
					.frame(minWidth: 72, minHeight: 52, alignment: .center)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityHint("Opens instructions for using Intersector.")
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
		.background(Color.crossSettingsHeader)
		.contentShape(Rectangle())
	}

	private var settingsDisplaySection: some View {
		Group {
			settingsHeader("Display")
			settingsControlRow {
				Picker("Current Info Layout", selection: displayLayoutBinding) {
					ForEach(DisplayLayout.allCases) { layout in
						Text(layout.label).tag(layout)
					}
				}
				.pickerStyle(.segmented)
				.accessibilityFocused($settingsFocusTarget, equals: .displayLayout)
			}
			settingsHelperText("Default keeps Current Info and the current announcement side by side. Centered puts each in its own centered row.")
		}
	}

	private var settingsAnnouncementSection: some View {
		Group {
			settingsHeader("Spoken Announcements")
			settingsControlRow {
				Toggle("Distance", isOn: announcementDistanceBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .announcementDistance)
			}
			if includeAnnouncementDistance {
				settingsControlRow {
					Picker("Measurement Unit", selection: measurementUnitBinding) {
						ForEach(MeasurementUnit.allCases) { item in
							Text(item.label).tag(item)
						}
					}
					.pickerStyle(.segmented)
					.accessibilityFocused($settingsFocusTarget, equals: .measurementUnit)
				}
			}
			settingsControlRow {
				Toggle("Direction", isOn: announcementDirectionBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .announcementDirection)
			}
			if includeAnnouncementDirection {
				settingsControlRow {
					Picker("Direction Style", selection: directionStyleBinding) {
						ForEach(DirectionStyle.allCases) { item in
							Text(item.label).tag(item)
						}
					}
					.pickerStyle(.segmented)
					.accessibilityFocused($settingsFocusTarget, equals: .direction)
				}
			}
			settingsControlRow {
				Toggle("Neighborhood", isOn: announcementNeighborhoodBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .announcementNeighborhood)
			}
			if includeAnnouncementNeighborhood {
				settingsControlRow {
					Picker("Neighborhood Context", selection: areaModeBinding) {
						ForEach(AreaMode.selectableCases) { mode in
							Text(mode.label).tag(mode)
						}
					}
					.pickerStyle(.segmented)
					.accessibilityFocused($settingsFocusTarget, equals: .neighborhood)
				}
			}
			settingsControlRow {
				Toggle("Intersection Details", isOn: intersectionDetailsBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .intersectionDetails)
			}
			settingsHelperText("Adds mapped details such as traffic signals and pedestrian islands when that information is available.")
			settingsControlRow {
				spokenIntersectionsControl
			}
			settingsHelperText(spokenIntersectionCountDescription)
			settingsControlRow {
				Toggle("Show 2nd and 3rd Controls", isOn: rankedControlsBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .rankedControls)
					.accessibilityHint("Toggles the visibility of the menu chevrons")
			}
			settingsControlRow {
				Text("Sample Announcement")
					.font(.headline)
					.foregroundStyle(Color.crossText)
					.accessibilityAddTraits(.isHeader)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			settingsHelperText(announcementSampleText)
		}
	}

	private var settingsRegionalWordingSection: some View {
		Group {
			settingsHeader("Regional Wording")
			settingsControlRow {
				Toggle("Manhattan Snob Mode", isOn: manhattanSnobModeBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .manhattanSnobMode)
			}
			settingsHelperText("Uses Uptown, Downtown, East Side, and West Side when cardinal directions are spoken.")
		}
	}

	private var spokenIntersectionsControl: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Spoken Intersections")
				.foregroundStyle(Color.crossText)
			Picker("Spoken Intersections", selection: spokenIntersectionCountBinding) {
				ForEach(SpokenIntersectionCount.allCases) { count in
					Text("\(count.rawValue)")
						.accessibilityLabel(spokenIntersectionOptionAccessibilityLabel(count))
						.tag(count)
				}
			}
			.pickerStyle(.segmented)
		}
		.accessibilityFocused($settingsFocusTarget, equals: .spokenIntersections)
	}

	private var settingsMapDetailSection: some View {
		Group {
			settingsHeader("Map Data")
			settingsControlRow {
				Toggle("Include crossings", isOn: crossingsBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .crossings)
			}
			settingsControlRow {
				Toggle("Include walking paths", isOn: walkingPathsBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .walkingPaths)
			}
			settingsHelperText("Includes named mapped paths in Upcoming and other intersection results. Unnamed paths cannot provide a named intersection. Keep this off to focus results on the street grid.")
		}
	}

	private var settingsInteractionSection: some View {
		Group {
			settingsHeader("Interaction")
			settingsControlRow {
				Toggle("Haptic scan feedback", isOn: hapticsBinding)
					.accessibilityFocused($settingsFocusTarget, equals: .haptics)
			}
		}
	}

	private var settingsAboutSection: some View {
		Group {
			settingsHeader("About Intersector")
			settingsControlRow {
				Button {
					if MFMailComposeViewController.canSendMail() {
						isShowingMailComposer = true
					} else {
						openMailFallback()
					}
				} label: {
					settingsButtonLabel("Send Intersector Feedback")
				}
				.buttonStyle(.plain)
				.accessibilityHint("Opens Mail so you can send feedback about Intersector.")
			}
			settingsControlRow {
				externalLink(title: "Privacy Policy", url: "https://marconius.com/csPrivacy/")
			}
			settingsControlRow {
				DisclosureGroup("Acknowledgements") {
					VStack(alignment: .leading, spacing: 8) {
						Text("Special thanks to Jen Walz for inspiring the creation of this app!")
							.lineLimit(nil)
							.fixedSize(horizontal: false, vertical: true)
						Text("Map data from OpenStreetMap, available under the Open Database License.")
							.lineLimit(nil)
							.fixedSize(horizontal: false, vertical: true)
						Link(
							"OpenStreetMap copyright and licence",
							destination: URL(string: "https://www.openstreetmap.org/copyright")!
						)
					}
					.font(.footnote)
				}
			}
			settingsControlRow {
				Text(appFooterText)
					.font(.footnote)
					.multilineTextAlignment(.center)
					.lineLimit(nil)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity, alignment: .center)
					.foregroundStyle(Color.crossText)
			}
		}
	}

	private var helpView: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					Text("Intersector helps you identify nearby intersections, understand the direction your phone is facing, and get quick street context from the app, Siri, Shortcuts, or Apple Watch. It uses your location, device heading, and available OpenStreetMap data to describe what is around you in concise spoken and visible announcements.")
						.font(.body)
						.foregroundStyle(Color.crossText)
						.lineLimit(nil)
						.fixedSize(horizontal: false, vertical: true)

					helpSection(
						title: "Nearest Intersection",
						body: "Use Nearest Intersection to find the intersection closest to your current location."
					)

					helpSection(
						title: "Upcoming Intersection",
						body: "Use Upcoming Intersection to find what comes next along the road you are on in the direction your phone is facing. Every Upcoming action follows the mapped path of that road through bends. If Intersector cannot identify the road or direction confidently, it reports no result instead of choosing an intersection on a nearby street."
					)

					helpSection(
						title: "My Direction",
						body: "Use My Direction to hear the cardinal direction your phone is facing. If Manhattan Snob Mode is on, Intersector can use Uptown, Downtown, East Side, and West Side wording when that style applies."
					)

					helpSection(
						title: "Point and Scan",
						body: "Turn on Point and Scan for a live orientation mode. Point the top of your phone around you to scan for nearby intersections and crossings. Haptics get stronger as your phone lines up with a result, and Intersector speaks the result when you are pointing directly toward it."
					)

					helpSection(
						title: "2nd and 3rd Results",
						body: "The chevron menus on Nearest and Upcoming expose 2nd and 3rd result actions. Nearest ranks by distance from you. Upcoming follows the direction your phone is facing and looks forward along your current street. You can hide the visible chevrons in Settings while keeping ranked actions available through VoiceOver, Siri, and Shortcuts."
					)

					announcementSettingsHelpSection

					helpSection(
						title: "Map Detail",
						body: "Crossings can include mapped crossing points on named roads. Walking Paths lets Upcoming follow named mapped paths and find their junctions with streets or other named paths. Unnamed paths cannot provide a named intersection. Keep Walking Paths off if you want results focused on the regular street grid."
					)

					helpSection(
						title: "Siri and Shortcuts",
						body: "Intersector includes shortcut actions for Nearest Intersection, Upcoming Intersection, My Direction, and Point and Scan. In the Shortcuts app, you can create your own phrase, such as Which way am I facing, and Siri can run that shortcut without needing you to say with Intersector."
					)

					helpSection(
						title: "Apple Watch",
						body: "The Apple Watch app supports quick intersection and direction reports. Settings sync from the iPhone app so your spoken announcement preferences stay consistent."
					)

					helpSection(
						title: "Accuracy",
						body: "Intersector depends on GPS, compass heading, and available OpenStreetMap data. Tall buildings, weak location signals, magnetic interference, missing map details, or unusual street layouts can affect results. Treat Intersector as orientation support, not turn-by-turn navigation."
					)
				}
				.padding(24)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.scrollContentBackground(.hidden)
			.background(Color.crossBg)
			.navigationTitle("Help")
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						isShowingHelp = false
					}
				}
			}
		}
		.tint(Color.crossAccent)
	}

	private func helpSection(title: String, body: String) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title)
				.font(.headline)
				.foregroundStyle(Color.crossText)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)
			Text(body)
				.font(.body)
				.foregroundStyle(Color.crossText)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private var announcementSettingsHelpSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Announcement Settings")
				.font(.headline)
				.foregroundStyle(Color.crossText)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)

			Text("Use the Announcements settings to choose what Intersector includes in spoken and visible results.")

			Text("Distance says approximately how far away the intersection is. You can choose feet or meters.")

			Text("Direction says where the intersection is in relation to the way your phone is pointing. Relative uses words such as ahead, left, and right. Cardinal uses directions such as north or southwest. Clock Face uses positions such as 10 o’clock.")

			Text("Neighborhood adds a neighborhood or local area name when one is available. Nearby only announces the area closest to your current location. Nearby and toward can also announce a different area in the direction your phone is pointing.")

			Text("Intersection Details adds useful mapped information such as traffic signals and pedestrian islands. If a detail has not been added to the map, Intersector cannot announce it.")

			Text("Spoken Intersections chooses whether Nearest and Upcoming speak one, two, or three results. Nearest reports the closest intersections. Upcoming reports the next intersections along the road ahead.")
		}
		.font(.body)
		.foregroundStyle(Color.crossText)
		.lineLimit(nil)
		.fixedSize(horizontal: false, vertical: true)
	}

	private func settingsHeader(_ title: String) -> some View {
		Text(title)
			.font(.title3)
			.fontWeight(.bold)
			.foregroundStyle(Color.crossText)
			.textCase(nil)
			.lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.horizontal, 16)
			.padding(.top, 14)
			.padding(.bottom, 8)
			.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
			.background(Color.crossSettingsHeader)
			.contentShape(Rectangle())
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(title)
			.accessibilityAddTraits(.isHeader)
	}

	private func settingsHelperText(_ text: String) -> some View {
		Text(text)
			.font(.footnote)
			.foregroundStyle(Color.crossText)
			.lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.horizontal, 16)
			.padding(.vertical, 8)
			.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
			.background(Color.crossSettingsHelper)
			.contentShape(Rectangle())
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(text)
	}

	private func settingsControlRow<Content: View>(
		@ViewBuilder content: () -> Content
	) -> some View {
		content()
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 16)
			.padding(.vertical, 8)
			.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
			.background(Color.crossSettingsRow)
			.overlay(alignment: .bottom) {
				Rectangle()
					.fill(Color.crossSettingsDivider)
					.frame(height: 1)
			}
			.contentShape(Rectangle())
			.accessibilityElement(children: .contain)
	}

	private func settingsButtonLabel(_ title: String) -> some View {
		Text(title)
			.font(.body)
			.fontWeight(.semibold)
			.foregroundStyle(Color.crossAccent)
			.lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
	}

	private func actionButton(
		_ title: String,
		systemImage: String,
		accessibilityLabel: String? = nil,
		accessibilityHint: String? = nil,
		isDisabled: Bool? = nil,
		drawsChrome: Bool = true,
		action: @escaping () async -> Void
	) -> some View {
		Button {
			Task {
				await action()
			}
		} label: {
			actionLabel(title, systemImage: systemImage)
				.frame(maxWidth: .infinity, minHeight: actionMinHeight, alignment: .center)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.foregroundStyle(Color.crossButtonText)
		.background(drawsChrome ? Color.crossBtn : Color.clear)
		.overlay(Rectangle().stroke(drawsChrome ? Color.crossButtonStrongBorder : Color.clear, lineWidth: 2))
		.shadow(color: drawsChrome ? Color.black.opacity(0.18) : Color.clear, radius: 2, x: 0, y: 1)
		.contentShape(Rectangle())
		.disabled(isDisabled ?? (isLoading || isStartupLoading || pointScanner.isScanning || pointScanner.isPreparing))
		.accessibilityLabel(accessibilityLabel ?? title)
		.accessibilityHint(accessibilityHint ?? "")
	}

	private func externalLink(title: String, url: String) -> some View {
		Link(title, destination: URL(string: url)!)
			.font(.body)
			.foregroundStyle(Color.crossAccent)
			.underline()
			.accessibilityTouchRegion(minHeight: 60, verticalPadding: 4, alignment: .leading)
			.accessibilityAddTraits(.isLink)
			.accessibilityRemoveTraits(.isButton)
			.accessibilityHint("Opens in external browser")
	}


	private func actionLabel(_ title: String, systemImage: String) -> some View {
		Label {
			Text(title)
				.multilineTextAlignment(.center)
				.lineLimit(1)
				.minimumScaleFactor(0.72)
		} icon: {
			Image(systemName: systemImage)
		}
		.font(.title2)
		.fontWeight(.semibold)
		.labelStyle(.titleAndIcon)
		.padding(12)
	}

	private func updateReport(_ kind: ReportKind, rank: Int = 1) async {
		guard !isLoading else {
			return
		}
		cancelStartupPreparationIfNeeded()
		isLoading = true
		let showsProgressImmediately = rank > 1
		if showsProgressImmediately {
			isLookupProgressVisible = true
			LoadingThrobber.start(hapticsEnabled: prefs.haptics)
		}
		let loadingTask = Task { @MainActor in
			do {
				try await Task.sleep(for: .milliseconds(800))
				guard !showsProgressImmediately else {
					return
				}
				isLookupProgressVisible = true
				LoadingThrobber.start(hapticsEnabled: prefs.haptics)
			} catch {}
		}

		while true {
			do {
				let text = if rank == 1 {
					try await OrientSvc.shared.spokenText(kind, prefs: prefs)
				} else {
					try await OrientSvc.shared.report(kind, rank: rank, prefs: prefs).text(with: prefs, rank: rank)
				}
				loadingTask.cancel()
				LoadingThrobber.stop()
				isLookupProgressVisible = false
				isMapPreparationLoading = false
				isMapDataReady = true
				statusText = text
				VoiceOverAnnouncer.reportUpdated(text)
				break
			} catch {
				if rank == 1, kind != .scan, isMapLoadingError(error) {
					await recoverMapDataForPendingReport()
					continue
				}
				loadingTask.cancel()
				LoadingThrobber.stop()
				isLookupProgressVisible = false
				let text = reportFailureText(kind, rank: rank, error: error)
				statusText = text
				VoiceOverAnnouncer.reportUpdated(text)
				break
			}
		}

		isLoading = false
	}

	private func isMapLoadingError(_ error: Error) -> Bool {
		error is MapDataError || error is URLError
	}

	private func recoverMapDataForPendingReport() async {
		isMapDataReady = false
		isMapPreparationLoading = true
		isLookupProgressVisible = true
		statusText = mapWaitingText
		VoiceOverAnnouncer.reportUpdated(mapWaitingText)

		var hasPreparedMapData = await OrientSvc.shared.prewarmInitialReportMapData(prefs: prefs)
		while !hasPreparedMapData {
			try? await Task.sleep(for: .seconds(2))
			hasPreparedMapData = await OrientSvc.shared.prewarmInitialReportMapData(prefs: prefs)
		}
		isMapPreparationLoading = false
		isMapDataReady = true
	}

	private func reportFailureText(_ kind: ReportKind, rank: Int, error: Error) -> String {
		if rank > 1 {
			return "Intersector could not find the \(rankedFailureLabel(kind, rank: rank)). Please try again."
		}
		if let orientError = error as? OrientError {
			switch orientError {
			case .noIntersections where kind == .upcoming:
				return "Intersector could not identify an Upcoming intersection for that direction. Please try again."
			case .headingUnavailable:
				return "Intersector could not get a stable direction yet. Please try again."
			case .locationUnavailable:
				return "Intersector could not get your location yet. Please try again."
			default:
				break
			}
		}
		return "Intersector is having trouble loading map data. Please try again."
	}

	private func rankedFailureLabel(_ kind: ReportKind, rank: Int) -> String {
		switch kind {
		case .nearest:
			return "\(ordinal(rank)) Nearest intersection"
		case .upcoming:
			return "\(ordinal(rank)) Upcoming intersection"
		case .scan:
			return "\(ordinal(rank)) Pointed intersection"
		}
	}

	private func reportLabel(_ kind: ReportKind, rank: Int) -> String {
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

	private func updateDirection() async {
		guard !isDirectionLoading else {
			return
		}
		isDirectionLoading = true

		do {
			let heading = try await directionLocationProvider.currentHeading(allowCached: false)
			let text = "Facing \(Geo.localizedDirection(heading, prefs: prefs))."
			statusText = text
			VoiceOverAnnouncer.reportUpdated(text)
		} catch {
			let text = "Intersector is having trouble getting your direction. Please try again."
			statusText = text
			VoiceOverAnnouncer.reportUpdated(text)
		}

		isDirectionLoading = false
	}

	private func prepareInitialLocationIfNeeded() {
		guard !hasPreparedInitialLocation else {
			return
		}
		hasPreparedInitialLocation = true
		startupTask = Task {
			isStartupLoading = true
			statusText = startupLoadingText
			VoiceOverAnnouncer.reportUpdated(startupLoadingText)
			LoadingThrobber.start(hapticsEnabled: prefs.haptics)

			var hasLocation = await OrientSvc.shared.prewarmLocation()
			while !hasLocation, !Task.isCancelled {
				let text = "Intersector could not get your location yet. Retrying automatically."
				statusText = text
				VoiceOverAnnouncer.reportUpdated(text)
				try? await Task.sleep(for: .seconds(2))
				guard !Task.isCancelled else {
					return
				}
				hasLocation = await OrientSvc.shared.prewarmLocation()
			}
			guard !Task.isCancelled else {
				return
			}

			isStartupLoading = false
			isMapPreparationLoading = true
			statusText = mapPreparationText

			var hasPreparedMapData = await OrientSvc.shared.prewarmInitialReportMapData(prefs: prefs)
			var announcedWaiting = false
			while !hasPreparedMapData, !Task.isCancelled {
				statusText = mapWaitingText
				if !announcedWaiting {
					VoiceOverAnnouncer.reportUpdated(mapWaitingText)
					announcedWaiting = true
				}
				try? await Task.sleep(for: .seconds(2))
				guard !Task.isCancelled else {
					return
				}
				hasPreparedMapData = await OrientSvc.shared.prewarmInitialReportMapData(prefs: prefs)
			}
			guard !Task.isCancelled else {
				return
			}

			LoadingThrobber.stop()
			isMapPreparationLoading = false
			isMapDataReady = true
			ReadyEarcon.play(hapticsEnabled: prefs.haptics)
			statusText = readyText
			Task { @MainActor in
				try? await Task.sleep(for: .milliseconds(1_350))
				VoiceOverAnnouncer.reportUpdated(readyText)
			}
		}
	}

	private func restartInitialPreparation() {
		startupTask?.cancel()
		startupTask = nil
		LoadingThrobber.stop()
		isStartupLoading = false
		isMapPreparationLoading = false
		isMapDataReady = false
		hasPreparedInitialLocation = false
		prepareInitialLocationIfNeeded()
	}

	private func cancelStartupPreparationIfNeeded() {
		startupTask?.cancel()
		startupTask = nil
		guard isStartupLoading else {
			return
		}
		LoadingThrobber.stop()
		isStartupLoading = false
		if statusText == startupLoadingText {
			statusText = "Choose an action."
		}
	}

	@discardableResult
	private func startRequestedPointScanIfNeeded() -> Bool {
		guard UserDefaults.standard.bool(forKey: LaunchKeys.startPointScan) else {
			return false
		}
		UserDefaults.standard.set(false, forKey: LaunchKeys.startPointScan)
		cancelStartupPreparationIfNeeded()
		pointScanner.setScanning(true, prefs: prefs) { text in
			statusText = text
		}
		return true
	}

	private var appFooterText: String {
		let year = Calendar.current.component(.year, from: .now)
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
		let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
		return "Copyright \(year) by Marco Salsiccia\nVersion \(version) (\(build))"
	}

	private var feedbackEmailBody: String {
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
		let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
		let device = UIDevice.current
		return """


		---
		Intersector version: \(version) (\(build))
		Device: \(device.model) (\(deviceHardwareIdentifier))
		OS: \(device.systemName) \(device.systemVersion)
		"""
	}

	private var deviceHardwareIdentifier: String {
		if let simulatorIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
			return simulatorIdentifier
		}
		var systemInfo = utsname()
		uname(&systemInfo)
		return withUnsafePointer(to: &systemInfo.machine) { pointer in
			pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
				String(cString: $0)
			}
		}
	}

	private func openMailFallback() {
		var components = URLComponents()
		components.scheme = "mailto"
		components.path = "marco@marconius.com"
		components.queryItems = [
			URLQueryItem(name: "subject", value: "Intersector Feedback"),
			URLQueryItem(name: "body", value: feedbackEmailBody)
		]
		guard let mailURL = components.url else {
			return
		}
		openURL(mailURL)
	}
}

extension View {
	func accessibilityTouchRegion(
		minHeight: CGFloat,
		verticalPadding: CGFloat,
		alignment: Alignment
	) -> some View {
		self
			.padding(.vertical, verticalPadding)
			.frame(minHeight: minHeight, alignment: alignment)
			.frame(maxWidth: .infinity, alignment: alignment)
			.contentShape(Rectangle())
	}
}

extension Color {
	static let crossBg = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
				: UIColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1)
		}
	)
	static let crossBtn = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.98, green: 0.75, blue: 0.18, alpha: 1)
				: UIColor(red: 1.00, green: 0.82, blue: 0.20, alpha: 1)
		}
	)
	static let crossPanel = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
				: UIColor(red: 0.18, green: 0.18, blue: 0.17, alpha: 1)
		}
	)
	static let crossSettingsHeader = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
				: UIColor(red: 0.94, green: 0.94, blue: 0.91, alpha: 1)
		}
	)
	static let crossSettingsRow = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1)
				: UIColor(red: 1.00, green: 1.00, blue: 0.98, alpha: 1)
		}
	)
	static let crossSettingsHelper = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
				: UIColor(red: 0.97, green: 0.97, blue: 0.94, alpha: 1)
		}
	)
	static let crossSettingsDivider = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.28, green: 0.28, blue: 0.28, alpha: 1)
				: UIColor(red: 0.78, green: 0.78, blue: 0.74, alpha: 1)
		}
	)
	static let crossText = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1)
				: UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
		}
	)
	static let crossButtonText = Color(red: 0.02, green: 0.02, blue: 0.02)
	static let crossButtonBorder = Color(red: 0.42, green: 0.28, blue: 0.00)
	static let crossButtonStrongBorder = Color(red: 0.02, green: 0.02, blue: 0.02)
	static let crossChevron = Color(red: 0.42, green: 0.28, blue: 0.00)
	static let crossScanIdle = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 1.00, green: 0.68, blue: 0.18, alpha: 1)
				: UIColor(red: 1.00, green: 0.76, blue: 0.18, alpha: 1)
		}
	)
	static let crossScanActive = Color(red: 1.00, green: 0.55, blue: 0.12)
	static let crossInv = Color(red: 0.98, green: 0.98, blue: 0.96)
	static let crossAccent = Color(
		UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(red: 1.00, green: 0.80, blue: 0.18, alpha: 1)
				: UIColor(red: 0.72, green: 0.46, blue: 0.00, alpha: 1)
		}
	)
}

#if DEBUG
	#Preview {
		ContentView()
	}
#endif
