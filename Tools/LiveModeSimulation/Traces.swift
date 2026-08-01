//
//  Traces.swift
//  Live Mode fetch simulation
//
//  Synthetic GPS traces standing in for real device traces. Each trace is a
//  list of timestamped coordinates, which is exactly what a replayed
//  CLLocationManager session would hand Live Mode.
//

import CoreLocation
import Foundation

struct TraceFix {
	var coordinate: CLLocationCoordinate2D
	var time: TimeInterval
	var speedMetersPerSecond: Double
}

struct Trace {
	var name: String
	var detail: String
	var fixes: [TraceFix]

	var duration: TimeInterval {
		(fixes.last?.time ?? 0) - (fixes.first?.time ?? 0)
	}

	/// True distance travelled, integrated from reported speed rather than from
	/// the jittered coordinates. Summing hops between noisy fixes counts the GPS
	/// wander as real movement — at 1 Hz with 5 m of jitter that manufactures
	/// kilometres of phantom travel for someone standing still.
	var distanceMeters: CLLocationDistance {
		guard fixes.count > 1 else {
			return 0
		}
		return zip(fixes, fixes.dropFirst()).reduce(0) { total, pair in
			total + pair.0.speedMetersPerSecond * (pair.1.time - pair.0.time)
		}
	}
}

/// A small deterministic generator so every run produces identical numbers.
/// Seeded splitmix64 — good enough for jitter, and repeatable across machines.
struct SeededRandom {
	private var state: UInt64

	init(seed: UInt64) {
		state = seed
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		return z ^ (z >> 31)
	}

	/// Uniform in [-magnitude, magnitude].
	mutating func jitter(magnitude: Double) -> Double {
		let unit = Double(next() >> 11) / Double(1 << 53)
		return (unit * 2 - 1) * magnitude
	}
}

enum TraceLibrary {
	/// Manhattan, heading north up Amsterdam Avenue from roughly West 93rd.
	/// The grid here is the app's best-tested territory and matches the
	/// curated-crossing work already in the codebase.
	static let amsterdamOrigin = CLLocationCoordinate2D(
		latitude: 40.79165,
		longitude: -73.97125
	)

	/// Applies GPS noise to a clean path. Real fixes wander by several meters
	/// even standing still, and that wander matters: it can push a coordinate
	/// just past a reuse boundary and trigger a fetch the clean path would miss.
	private static func addJitter(
		to fixes: [TraceFix],
		magnitudeMeters: Double,
		seed: UInt64
	) -> [TraceFix] {
		var random = SeededRandom(seed: seed)
		return fixes.map { fix in
			let offsetBearing = (Double(random.next() >> 11) / Double(1 << 53)) * 360
			let offsetDistance = abs(random.jitter(magnitude: magnitudeMeters))
			return TraceFix(
				coordinate: projected(
					from: fix.coordinate,
					bearingDegrees: offsetBearing,
					meters: offsetDistance
				),
				time: fix.time,
				speedMetersPerSecond: fix.speedMetersPerSecond
			)
		}
	}

	/// Constant-speed travel along a fixed bearing, sampled every `interval`.
	private static func straightLine(
		from origin: CLLocationCoordinate2D,
		bearingDegrees: Double,
		speedMetersPerSecond: Double,
		duration: TimeInterval,
		interval: TimeInterval
	) -> [TraceFix] {
		var fixes: [TraceFix] = []
		var time: TimeInterval = 0
		while time <= duration {
			fixes.append(
				TraceFix(
					coordinate: projected(
						from: origin,
						bearingDegrees: bearingDegrees,
						meters: speedMetersPerSecond * time
					),
					time: time,
					speedMetersPerSecond: speedMetersPerSecond
				)
			)
			time += interval
		}
		return fixes
	}

	/// A steady walk: 1.35 m/s is a typical adult pace, and a slightly slower
	/// one is realistic for a cane or guide dog user navigating a city block.
	static func walk(
		minutes: Double = 15,
		speedMetersPerSecond: Double = 1.35,
		sampleInterval: TimeInterval = 1
	) -> Trace {
		let clean = straightLine(
			from: amsterdamOrigin,
			bearingDegrees: 0,
			speedMetersPerSecond: speedMetersPerSecond,
			duration: minutes * 60,
			interval: sampleInterval
		)
		return Trace(
			name: "Walk",
			detail: String(
				format: "%.0f min at %.2f m/s (%.1f mph), 1 s fixes, 5 m GPS jitter",
				minutes,
				speedMetersPerSecond,
				speedMetersPerSecond * 2.23694
			),
			fixes: addJitter(to: clean, magnitudeMeters: 5, seed: 0xA11CE)
		)
	}

	/// A city bus: stop-and-go rather than constant speed. Roughly 20 seconds
	/// of travel at ~9 m/s between stops, then ~25 seconds dwelling at a stop.
	/// The dwell time matters — a stationary bus should be getting cache hits,
	/// and if it isn't, that points at a policy problem rather than a speed one.
	static func bus(
		minutes: Double = 20,
		sampleInterval: TimeInterval = 1
	) -> Trace {
		let cruiseSpeed: Double = 9.0
		let runDuration: TimeInterval = 20
		let dwellDuration: TimeInterval = 25

		var fixes: [TraceFix] = []
		var position = amsterdamOrigin
		var time: TimeInterval = 0
		let total = minutes * 60
		var isMoving = true
		var phaseElapsed: TimeInterval = 0

		while time <= total {
			fixes.append(
				TraceFix(
					coordinate: position,
					time: time,
					speedMetersPerSecond: isMoving ? cruiseSpeed : 0
				)
			)

			if isMoving {
				position = projected(
					from: position,
					bearingDegrees: 0,
					meters: cruiseSpeed * sampleInterval
				)
			}

			time += sampleInterval
			phaseElapsed += sampleInterval

			let phaseLimit = isMoving ? runDuration : dwellDuration
			if phaseElapsed >= phaseLimit {
				isMoving.toggle()
				phaseElapsed = 0
			}
		}

		return Trace(
			name: "Bus",
			detail: String(
				format: "%.0f min stop-and-go, %.0f m/s (%.0f mph) cruise, %.0f s runs / %.0f s dwells",
				minutes,
				cruiseSpeed,
				cruiseSpeed * 2.23694,
				runDuration,
				dwellDuration
			),
			fixes: addJitter(to: fixes, magnitudeMeters: 8, seed: 0xB0551)
		)
	}

	/// A rideshare on an arterial: faster and continuous, no dwelling.
	/// This is the worst case for the current cache and the clearest test of
	/// whether Car mode can run on network fetches at all.
	static func car(
		minutes: Double = 20,
		speedMetersPerSecond: Double = 13.4,
		sampleInterval: TimeInterval = 1
	) -> Trace {
		let clean = straightLine(
			from: amsterdamOrigin,
			bearingDegrees: 0,
			speedMetersPerSecond: speedMetersPerSecond,
			duration: minutes * 60,
			interval: sampleInterval
		)
		return Trace(
			name: "Car",
			detail: String(
				format: "%.0f min at %.1f m/s (%.0f mph), 1 s fixes, 8 m GPS jitter",
				minutes,
				speedMetersPerSecond,
				speedMetersPerSecond * 2.23694
			),
			fixes: addJitter(to: clean, magnitudeMeters: 8, seed: 0xCA5)
		)
	}

	/// A control case: standing at a corner. Should be almost entirely cache
	/// hits. If it isn't, the jitter alone is defeating the reuse rule.
	static func standing(minutes: Double = 10, sampleInterval: TimeInterval = 1) -> Trace {
		var fixes: [TraceFix] = []
		var time: TimeInterval = 0
		while time <= minutes * 60 {
			fixes.append(
				TraceFix(
					coordinate: amsterdamOrigin,
					time: time,
					speedMetersPerSecond: 0
				)
			)
			time += sampleInterval
		}
		return Trace(
			name: "Standing",
			detail: String(format: "%.0f min stationary, 1 s fixes, 5 m GPS jitter", minutes),
			fixes: addJitter(to: fixes, magnitudeMeters: 5, seed: 0x57A4D)
		)
	}
}
