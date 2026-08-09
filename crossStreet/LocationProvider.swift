//
//  LocationProvider.swift
//  Intersector
//
//  Created by Marco Salsiccia on 6/7/26.
//

import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, LocationProviding {
	private let manager = CLLocationManager()
	private var continuation: CheckedContinuation<DeviceContext, Error>?
	private var locationTimeoutTask: Task<Void, Never>?
	private var bestActiveLocation: CLLocation?
	private var latestLocation: CLLocation?
	private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
	private var prewarmContinuation: CheckedContinuation<Bool, Never>?
	private var prewarmTimeoutTask: Task<Void, Never>?
	private var headingContinuation: CheckedContinuation<CLLocationDirection, Error>?
	private var headingTimeoutTask: Task<Void, Never>?
	private var headingSettlingTask: Task<Void, Never>?
	private var latestHeading: CLLocationDirection?
	private var latestHeadingDate: Date?
	private var headingContinuations: [UUID: AsyncStream<CLLocationDirection>.Continuation] = [:]
	private let idealAccuracyMeters: CLLocationAccuracy = 35
	private let usableAccuracyMeters: CLLocationAccuracy = 85
	private let recentLocationAge: TimeInterval = 20
	private let locationTimeoutNanoseconds: UInt64 = 7_000_000_000

	override init() {
		super.init()
		manager.delegate = self
		manager.desiredAccuracy = kCLLocationAccuracyBest
		manager.distanceFilter = kCLDistanceFilterNone
		manager.headingFilter = 5
	}

	func currentContext() async throws -> DeviceContext {
		try await currentContext(requiresFreshHeading: false)
	}

	func currentContext(requiresFreshHeading: Bool) async throws -> DeviceContext {
		switch manager.authorizationStatus {
		case .notDetermined:
			let status = await requestWhenInUseAuthorization()
			guard status == .authorizedAlways || status == .authorizedWhenInUse else {
				throw CLError(.denied)
			}
		case .authorizedAlways, .authorizedWhenInUse:
			break
		case .denied, .restricted:
			throw CLError(.denied)
		@unknown default:
			throw CLError(.denied)
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

		if let location = latestLocation, isRecentEnough(location), isUsable(location) {
			let context = DeviceContext(
				coordinate: location.coordinate,
				headingDegrees: latestHeading
			)
			stopHeadingIfIdle()
			return context
		}

		return try await withCheckedThrowingContinuation { continuation in
			self.continuation = continuation
			bestActiveLocation = nil
			locationTimeoutTask?.cancel()
			locationTimeoutTask = Task { [weak self] in
				try? await Task.sleep(nanoseconds: self?.locationTimeoutNanoseconds ?? 7_000_000_000)
				await MainActor.run {
					self?.finishWithBestLocationOrFailure()
				}
			}
			manager.startUpdatingLocation()
		}
	}

	func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
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

	func prewarmContext(timeout: TimeInterval = 4) async -> Bool {
		switch manager.authorizationStatus {
		case .notDetermined:
			let status = await requestWhenInUseAuthorization()
			guard status == .authorizedAlways || status == .authorizedWhenInUse else {
				return false
			}
		case .authorizedAlways, .authorizedWhenInUse:
			break
		case .denied, .restricted:
			return false
		@unknown default:
			return false
		}

		if let location = latestLocation, isRecentEnough(location), isUsable(location) {
			return true
		}

		return await withCheckedContinuation { continuation in
			prewarmContinuation = continuation
			prewarmTimeoutTask?.cancel()
			prewarmTimeoutTask = Task { [weak self] in
				let nanoseconds = UInt64(timeout * 1_000_000_000)
				try? await Task.sleep(nanoseconds: nanoseconds)
				await MainActor.run {
					guard let self else {
						return
					}
					let hasUsableLocation = self.bestActiveLocation.map(self.isUsable) ?? false
					self.finishPrewarm(success: hasUsableLocation)
				}
			}
			manager.startUpdatingLocation()
		}
	}

	func currentHeading(timeout: TimeInterval = 1.5, allowCached: Bool = true) async throws -> CLLocationDirection {
		guard CLLocationManager.headingAvailable() else {
			throw OrientError.headingUnavailable
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
					self?.finishHeading(with: .failure(OrientError.headingUnavailable))
				}
			}
		}
	}

	func headingUpdates() -> AsyncStream<CLLocationDirection> {
		if CLLocationManager.headingAvailable() {
			manager.startUpdatingHeading()
		}

		return AsyncStream { continuation in
			let id = UUID()
			headingContinuations[id] = continuation
			continuation.onTermination = { [weak self] _ in
				Task { @MainActor [weak self] in
					self?.headingContinuations[id] = nil
					if self?.headingContinuations.isEmpty == true {
						self?.manager.stopUpdatingHeading()
					}
				}
			}
		}
	}

	private func finish(with result: Result<DeviceContext, Error>) {
		guard let continuation else {
			return
		}
		self.continuation = nil
		bestActiveLocation = nil
		manager.stopUpdatingLocation()
		locationTimeoutTask?.cancel()
		locationTimeoutTask = nil
		stopHeadingIfIdle()
		switch result {
		case .success(let context):
			continuation.resume(returning: context)
		case .failure(let error):
			continuation.resume(throwing: error)
		}
	}

	private func finishPrewarm(success: Bool) {
		guard let prewarmContinuation else {
			return
		}
		self.prewarmContinuation = nil
		prewarmTimeoutTask?.cancel()
		prewarmTimeoutTask = nil
		if continuation == nil {
			manager.stopUpdatingLocation()
		}
		prewarmContinuation.resume(returning: success)
	}

	private func finishWithBestLocationOrFailure() {
		if let location = bestActiveLocation ?? latestLocation, isUsable(location) {
			finish(with: .success(context(from: location)))
		} else {
			finish(with: .failure(OrientError.locationUnavailable))
		}
	}

	private func context(from location: CLLocation) -> DeviceContext {
		DeviceContext(
			coordinate: location.coordinate,
			headingDegrees: latestHeading,
			courseDegrees: location.course >= 0 ? location.course : nil,
			courseAccuracy: location.courseAccuracy >= 0 ? location.courseAccuracy : nil,
			speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
			horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
		)
	}

	private func consider(_ location: CLLocation) {
		guard location.horizontalAccuracy >= 0 else {
			return
		}

		if latestLocation == nil || location.horizontalAccuracy <= latestLocation!.horizontalAccuracy || isRecentEnough(location) {
			latestLocation = location
		}

		guard isRecentEnough(location) else {
			return
		}

		if bestActiveLocation == nil || location.horizontalAccuracy < bestActiveLocation!.horizontalAccuracy {
			bestActiveLocation = location
		}
	}

	private func isIdeal(_ location: CLLocation) -> Bool {
		location.horizontalAccuracy <= idealAccuracyMeters
	}

	private func isUsable(_ location: CLLocation) -> Bool {
		isRecentEnough(location) && location.horizontalAccuracy <= usableAccuracyMeters
	}

	private func isRecentEnough(_ location: CLLocation) -> Bool {
		abs(location.timestamp.timeIntervalSinceNow) <= recentLocationAge
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
		if headingContinuation == nil && headingContinuations.isEmpty {
			manager.stopUpdatingHeading()
		}
	}

	private func clearHeading() {
		latestHeading = nil
		latestHeadingDate = nil
	}
}

extension LocationProvider: CLLocationManagerDelegate {
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		if let authorizationContinuation {
			self.authorizationContinuation = nil
			authorizationContinuation.resume(returning: manager.authorizationStatus)
		}

		switch manager.authorizationStatus {
		case .authorizedAlways, .authorizedWhenInUse:
			if continuation != nil || prewarmContinuation != nil {
				manager.startUpdatingLocation()
			}
		case .denied, .restricted:
			finish(with: .failure(CLError(.denied)))
			finishPrewarm(success: false)
		default:
			break
		}
	}

	func locationManager(
		_ manager: CLLocationManager,
		didUpdateLocations locations: [CLLocation]
	) {
		guard !locations.isEmpty else {
			finish(with: .failure(CLError(.locationUnknown)))
			return
		}

		for location in locations {
			consider(location)
		}

		if let bestActiveLocation, isUsable(bestActiveLocation) {
			finishPrewarm(success: true)
		}

		if let bestActiveLocation, isIdeal(bestActiveLocation) {
			finish(with: .success(context(from: bestActiveLocation)))
		}
	}

	func locationManager(
		_ manager: CLLocationManager,
		didUpdateHeading newHeading: CLHeading
	) {
		guard newHeading.headingAccuracy >= 0 else {
			return
		}
		let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
		latestHeading = heading >= 0 ? heading : nil
		if let latestHeading {
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
			for continuation in headingContinuations.values {
				continuation.yield(latestHeading)
			}
		}
	}

	func locationManager(
		_ manager: CLLocationManager,
		didFailWithError error: Error
	) {
		if (error as? CLError)?.code == .locationUnknown {
			if let location = bestActiveLocation ?? latestLocation, isUsable(location) {
				finish(with: .success(context(from: location)))
			}
		} else {
			finish(with: .failure(error))
		}
	}
}
