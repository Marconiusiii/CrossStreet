//
//  PointScanController.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class PointScanController: ObservableObject {
	@Published private(set) var isPreparing = false
	@Published private(set) var isScanning = false

	private let locationProvider = LocationProvider()
	private let mapDataClient = MapDataClient()
	private let finder = IntersectionFinder()
	private let haptics = HapticFeedback()
	private var scanTask: Task<Void, Never>?
	private var preparationHapticsTask: Task<Void, Never>?
	private var lastPulse = Date.distantPast
	private var spokenCooldowns: [String: Date] = [:]

	func setScanning(
		_ enabled: Bool,
		prefs: AppPrefs,
		onUpdate: @escaping (String) -> Void
	) {
		if enabled {
			start(prefs: prefs, onUpdate: onUpdate)
		} else {
			stop()
		}
	}

	func stopScanning() {
		stop()
	}

	private func start(
		prefs: AppPrefs,
		onUpdate: @escaping (String) -> Void
	) {
		guard scanTask == nil else {
			return
		}

		isPreparing = true
		let loadingText = "Point Mode Loading..."
		onUpdate(loadingText)
		VoiceOverAnnouncer.reportUpdated(loadingText)
		if prefs.haptics {
			startPreparationHaptics()
		}

		scanTask = Task { [weak self] in
			guard let self else {
				return
			}

			do {
				let initialContext = try await locationProvider.currentContext(requiresFreshHeading: true)
				let mapData = try await mapDataClient.mapData(
					near: initialContext.coordinate,
					radiusMeters: 450,
					options: prefs.mapDetails
				)
				let intersections = mapData.currentStreetScanTargets(
					from: initialContext.coordinate,
					includeCrossings: prefs.mapDetails.includeCrossings
				)

				guard !intersections.isEmpty else {
					throw OrientError.noIntersections
				}

				isPreparing = false
				isScanning = true
				stopPreparationHaptics()
				let readyText = "Point Mode Ready."
				onUpdate(readyText)
				VoiceOverAnnouncer.reportUpdated(readyText)

				for await heading in locationProvider.headingUpdates() {
					guard !Task.isCancelled else {
						return
					}
					let context = DeviceContext(
						coordinate: initialContext.coordinate,
						headingDegrees: heading
					)
					handleHeading(
						context,
						intersections: intersections,
						mapData: mapData,
						prefs: prefs,
						onUpdate: onUpdate
					)
				}
			} catch {
				isPreparing = false
				isScanning = false
				scanTask = nil
				stopPreparationHaptics()
				let text = "Unable to start Point and Scan. \(error.localizedDescription)"
				onUpdate(text)
				VoiceOverAnnouncer.reportUpdated(text)
			}
		}
	}

	private func stop() {
		scanTask?.cancel()
		scanTask = nil
		stopPreparationHaptics()
		isPreparing = false
		isScanning = false
	}

	private func startPreparationHaptics() {
		preparationHapticsTask?.cancel()
		haptics.pulse(intensity: 0.45)
		preparationHapticsTask = Task { [weak self] in
			var delay: UInt64 = 350_000_000
			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: delay)
				guard !Task.isCancelled else {
					return
				}
				await MainActor.run {
					self?.haptics.pulse(intensity: 0.45)
				}
				delay = max(170_000_000, delay - 45_000_000)
			}
		}
	}

	private func stopPreparationHaptics() {
		preparationHapticsTask?.cancel()
		preparationHapticsTask = nil
	}

	private func handleHeading(
		_ context: DeviceContext,
		intersections: [IntersectionCandidate],
		mapData: MapDataSet,
		prefs: AppPrefs,
		onUpdate: @escaping (String) -> Void
	) {
		guard let match = finder.scanMatch(from: context, in: intersections) else {
			return
		}

		let pulseWindow = 45.0
		if prefs.haptics, match.angleDelta <= pulseWindow {
			let intensity = 1.0 - (match.angleDelta / pulseWindow)
			pulseIfNeeded(intensity: intensity)
		}

		guard match.angleDelta <= 8, canAnnounce(match.candidate.id) else {
			return
		}

		let currentStreet = mapData.nearestRoadName(
			to: context.coordinate,
			matching: match.candidate.roadNames
		)
		let crossStreet: String? = currentStreet.flatMap { roadName in
			let names = mapData.crossStreetNames(
				for: match.candidate,
				on: roadName,
				heading: context.dependableTravelDirection
			)
			return names.isEmpty ? nil : names.joined(separator: " and ")
		}
		let cross = currentStreet.flatMap { roadName in
			crossStreet.map { "\(roadName) and \($0)" }
		} ?? match.candidate.title

		let report = OrientReport(
			kind: .scan,
			cross: cross,
			dist: Geo.spokenDistance(match.distanceMeters, unit: prefs.measurementUnit),
			relDir: nil,
			relDegrees: nil,
			street: currentStreet,
			crossStreet: crossStreet,
			head: Geo.compassDirection(match.bearingDegrees),
			area: nil,
			toward: nil,
			conf: .high
		)
		let text = report.text(with: prefs)
		spokenCooldowns[match.candidate.id] = Date()
		onUpdate(text)
		if prefs.haptics {
			haptics.identify()
		}
		VoiceOverAnnouncer.reportUpdated(text)
	}

	private func pulseIfNeeded(intensity: Double) {
		let now = Date()
		guard now.timeIntervalSince(lastPulse) >= 0.18 else {
			return
		}
		lastPulse = now
		haptics.pulse(intensity: intensity)
	}

	private func canAnnounce(_ id: String) -> Bool {
		guard let lastSpoken = spokenCooldowns[id] else {
			return true
		}
		return Date().timeIntervalSince(lastSpoken) >= 8
	}
}
