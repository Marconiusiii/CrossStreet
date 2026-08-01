//
//  main.swift
//  Live Mode fetch simulation
//
//  Replays GPS traces through the cache policy and counts Overpass fetches.
//
//  The question this answers: if Live Mode asks for map data on every location
//  update, how many network requests does a walk, a bus ride, or a car ride
//  actually generate — and can a public Overpass endpoint survive that?
//

import CoreLocation
import Foundation

// MARK: - Live Mode request policy

/// How often Live Mode asks the cache for data, and how wide it asks.
///
/// This is the part that is not yet written in the app, so it is a proposal
/// rather than a mirror. The defaults match what Point and Scan does today:
/// a 450 m radius (PointScanController.swift:68) requested whenever the engine
/// wants to know what is nearby.
struct LiveModePolicy {
	var name: String
	var radiusMeters: CLLocationDistance
	var tuning: CacheTuning

	/// Minimum seconds between cache consultations. Live Mode does not need to
	/// re-evaluate on every 1 Hz fix; the announcement logic only needs data
	/// when the picture could have changed.
	var evaluationInterval: TimeInterval

	/// If set, the engine prefetches ahead along the direction of travel once
	/// it has moved this far from the last fetch center, instead of waiting to
	/// fall out of the cached circle. This is the "corridor prefetch" idea.
	var prefetchAfterMeters: CLLocationDistance?

	/// How far ahead of the current position the prefetch is centered.
	var prefetchLeadMeters: CLLocationDistance
}

extension LiveModePolicy {
	/// What you would get by wiring Live Mode straight into the existing client
	/// with no changes: today's radius, today's cache, evaluated every second.
	static let naive = LiveModePolicy(
		name: "Naive (today's cache, 450 m, 1 s)",
		radiusMeters: 450,
		tuning: .shipping,
		evaluationInterval: 1,
		prefetchAfterMeters: nil,
		prefetchLeadMeters: 0
	)

	/// The same cache, but only consulted every 5 seconds. Tests whether simple
	/// throttling is enough on its own.
	static let throttled = LiveModePolicy(
		name: "Throttled (today's cache, 450 m, 5 s)",
		radiusMeters: 450,
		tuning: .shipping,
		evaluationInterval: 5,
		prefetchAfterMeters: nil,
		prefetchLeadMeters: 0
	)

	/// Wider radius and a longer TTL, sized for someone who is moving.
	static let widened = LiveModePolicy(
		name: "Widened (1200 m radius, 15 min TTL, 8 entries)",
		radiusMeters: 1_200,
		tuning: CacheTuning(
			reuseDistanceMeters: 150,
			timeToLive: 900,
			staleTimeToLive: 2_700,
			maxEntries: 8
		),
		evaluationInterval: 5,
		prefetchAfterMeters: nil,
		prefetchLeadMeters: 0
	)

	/// Widened plus corridor prefetch: fetch ahead of travel before falling out
	/// of coverage, so the network request overlaps with data you still have.
	static let corridor = LiveModePolicy(
		name: "Corridor prefetch (1200 m, lead 600 m, 15 min TTL)",
		radiusMeters: 1_200,
		tuning: CacheTuning(
			reuseDistanceMeters: 150,
			timeToLive: 900,
			staleTimeToLive: 2_700,
			maxEntries: 8
		),
		evaluationInterval: 5,
		prefetchAfterMeters: 600,
		prefetchLeadMeters: 600
	)

	static let all: [LiveModePolicy] = [.naive, .throttled, .widened, .corridor]
}

// MARK: - Results

struct SimulationResult {
	var traceName: String
	var policyName: String
	var evaluations: Int
	var fetches: Int
	var freshHits: Int
	var staleHits: Int
	var durationMinutes: Double
	var distanceKilometers: Double

	var fetchesPerMinute: Double {
		durationMinutes > 0 ? Double(fetches) / durationMinutes : 0
	}

	var fetchesPerKilometer: Double {
		distanceKilometers > 0 ? Double(fetches) / distanceKilometers : 0
	}

	/// Overpass's public instances are widely documented as tolerating roughly
	/// 10k queries per day per user under fair use. This projects a single
	/// user's hourly rate against that, which is the number that decides whether
	/// the public endpoint is viable.
	var projectedFetchesPerHour: Double {
		fetchesPerMinute * 60
	}
}

// MARK: - Simulator

enum Simulator {
	static func run(trace: Trace, policy: LiveModePolicy) -> SimulationResult {
		var cache = SimulatedCache(tuning: policy.tuning)
		var evaluations = 0
		var fetches = 0
		var freshHits = 0
		var staleHits = 0
		var lastEvaluation: TimeInterval = -.greatestFiniteMagnitude
		var lastFetchCenter: CLLocationCoordinate2D?

		for fix in trace.fixes {
			guard fix.time - lastEvaluation >= policy.evaluationInterval else {
				continue
			}
			lastEvaluation = fix.time
			evaluations += 1

			// Decide where to center the request. Without prefetch, that is
			// simply the current position. With prefetch, once we have travelled
			// far enough from the last fetch center we re-center ahead of
			// ourselves along the direction of travel.
			var requestCenter = fix.coordinate
			if let prefetchAfterMeters = policy.prefetchAfterMeters {
				let travelled = lastFetchCenter.map {
					metersBetween(from: $0, to: fix.coordinate)
				} ?? .greatestFiniteMagnitude

				// Only lead the request center when we are genuinely moving.
				// CLLocation reports a negative course when stationary, and
				// DeviceContext already discards it (LocationProvider.swift:237).
				// Without this guard, GPS jitter at a standstill yields a random
				// bearing and throws the prefetch center hundreds of metres in an
				// arbitrary direction on every evaluation.
				let isMoving = fix.speedMetersPerSecond >= 0.5

				if travelled >= prefetchAfterMeters, isMoving {
					requestCenter = projected(
						from: fix.coordinate,
						bearingDegrees: bearing(at: fix, in: trace),
						meters: policy.prefetchLeadMeters
					)
				} else {
					// Still inside the corridor we already fetched — ask about
					// that same center so the cache can serve it.
					requestCenter = lastFetchCenter ?? fix.coordinate
				}
			}

			let outcome = cache.request(
				near: requestCenter,
				radiusMeters: policy.radiusMeters,
				now: fix.time
			)

			switch outcome {
			case .fetch:
				fetches += 1
				lastFetchCenter = requestCenter
			case .freshHit:
				freshHits += 1
			case .staleHit:
				staleHits += 1
			}
		}

		return SimulationResult(
			traceName: trace.name,
			policyName: policy.name,
			evaluations: evaluations,
			fetches: fetches,
			freshHits: freshHits,
			staleHits: staleHits,
			durationMinutes: trace.duration / 60,
			distanceKilometers: trace.distanceMeters / 1_000
		)
	}

	/// Direction of travel at a given fix, taken from the trace itself. On the
	/// device this would come from CLLocation.course, which DeviceContext
	/// already captures (LocationProvider.swift:237).
	private static func bearing(at fix: TraceFix, in trace: Trace) -> Double {
		guard let index = trace.fixes.firstIndex(where: { $0.time == fix.time }),
			  index + 1 < trace.fixes.count else {
			return 0
		}
		let next = trace.fixes[index + 1]
		return bearingDegrees(from: fix.coordinate, to: next.coordinate)
	}

	private static func bearingDegrees(
		from start: CLLocationCoordinate2D,
		to end: CLLocationCoordinate2D
	) -> Double {
		let startLatitude = start.latitude * .pi / 180
		let endLatitude = end.latitude * .pi / 180
		let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
		let y = sin(deltaLongitude) * cos(endLatitude)
		let x = cos(startLatitude) * sin(endLatitude)
			- sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)
		return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
	}
}

// MARK: - Reporting

func pad(_ text: String, _ width: Int) -> String {
	text.count >= width
		? String(text.prefix(width))
		: text + String(repeating: " ", count: width - text.count)
}

func padLeft(_ text: String, _ width: Int) -> String {
	text.count >= width
		? String(text.prefix(width))
		: String(repeating: " ", count: width - text.count) + text
}

let traces = [
	TraceLibrary.standing(),
	TraceLibrary.walk(),
	TraceLibrary.bus(),
	TraceLibrary.car()
]

print("")
print("Live Mode Overpass fetch simulation")
print(String(repeating: "=", count: 96))
print("")
print("Cache policy mirrored from crossStreet/MapDataClient.swift:409-570.")
print("Fetch counts are per single user, per trip.")
print("")

for trace in traces {
	print(String(repeating: "-", count: 96))
	print("\(trace.name) — \(trace.detail)")
	print(
		String(
			format: "  %.1f min, %.2f km travelled, %d GPS fixes",
			trace.duration / 60,
			trace.distanceMeters / 1_000,
			trace.fixes.count
		)
	)
	print("")
	print(
		"  " + pad("Policy", 46)
			+ padLeft("Evals", 7)
			+ padLeft("Fetch", 7)
			+ padLeft("Fresh", 7)
			+ padLeft("Stale", 7)
			+ padLeft("/min", 8)
			+ padLeft("/hour", 8)
	)

	for policy in LiveModePolicy.all {
		let result = Simulator.run(trace: trace, policy: policy)
		print(
			"  " + pad(result.policyName, 46)
				+ padLeft("\(result.evaluations)", 7)
				+ padLeft("\(result.fetches)", 7)
				+ padLeft("\(result.freshHits)", 7)
				+ padLeft("\(result.staleHits)", 7)
				+ padLeft(String(format: "%.1f", result.fetchesPerMinute), 8)
				+ padLeft(String(format: "%.0f", result.projectedFetchesPerHour), 8)
		)
	}
	print("")
}

// MARK: - Fleet projection

print(String(repeating: "=", count: 96))
print("")
print("Fleet projection — daily Overpass load")
print("")
print("Assumes each active user runs one 30-minute Live Mode session per day.")
print("Public Overpass fair-use is commonly cited around 10,000 queries/day/source;")
print("all app traffic shares one source IP range, so this is the ceiling that matters.")
print("")

let fleetSizes = [100, 500, 1_000, 5_000]
let sessionMinutes = 30.0

for policy in LiveModePolicy.all {
	let busResult = Simulator.run(trace: TraceLibrary.bus(), policy: policy)
	let perSession = busResult.fetchesPerMinute * sessionMinutes

	print("  \(policy.name)")
	print(String(format: "    %.0f fetches per 30-minute session", perSession))
	for size in fleetSizes {
		let daily = perSession * Double(size)
		let verdict = daily > 10_000 ? "OVER public fair-use" : "within fair-use"
		print(
			String(
				format: "      %5d users -> %9.0f fetches/day   %@",
				size,
				daily,
				verdict
			)
		)
	}
	print("")
}
