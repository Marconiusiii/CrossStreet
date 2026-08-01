//
//  CachePolicy.swift
//  Live Mode fetch simulation
//
//  A faithful, time-injectable mirror of MapDataCache from
//  crossStreet/MapDataClient.swift:409-570.
//
//  The shipping cache calls Date() internally, which makes it impossible to
//  replay an hour-long trip in a fraction of a second. This copy takes `now`
//  as a parameter everywhere the original reads the clock. Every other rule —
//  reuseDistanceMeters, timeToLive, staleTimeToLive, maxEntries, the sameArea
//  coverage test, and the newest-first eviction order — is reproduced exactly.
//

import CoreLocation
import Foundation

// MARK: - Tunables

/// The cache knobs, pulled out so the simulation can sweep them.
/// Defaults are the shipping values from MapDataClient.swift:425-428.
struct CacheTuning {
	var reuseDistanceMeters: CLLocationDistance = 150
	var timeToLive: TimeInterval = 300
	var staleTimeToLive: TimeInterval = 900
	var maxEntries = 4

	/// Shipping configuration, for comparison against proposed changes.
	static let shipping = CacheTuning()
}

// MARK: - Cache

/// Mirrors MapDataCache's reuse policy with an injected clock.
///
/// Only the decision logic is modeled. There is no in-flight coalescing here
/// because the simulation is synchronous: each replayed fix resolves before the
/// next one arrives, so no two requests are ever outstanding at once. On the
/// real device, coalescing can only reduce fetches further, which means the
/// counts this produces are a ceiling rather than an underestimate.
struct SimulatedCache {
	private struct Entry {
		var center: CLLocationCoordinate2D
		var radiusMeters: CLLocationDistance
		var storedAt: TimeInterval
		var data: MapDataSetStub
	}

	/// Why a given request did or did not hit the network.
	enum Outcome {
		case freshHit
		case staleHit
		case fetch
	}

	private var entries: [Entry] = []
	private let tuning: CacheTuning

	init(tuning: CacheTuning = .shipping) {
		self.tuning = tuning
	}

	/// The cache lookup, matching MapDataCache.data(near:radiusMeters:options:fetch:).
	/// Order matters and is preserved: fresh entry, then in-flight (absent here),
	/// then stale entry, then fetch.
	mutating func request(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		now: TimeInterval
	) -> Outcome {
		if entries.contains(where: {
			canReuse($0, for: coordinate, radiusMeters: radiusMeters, now: now)
		}) {
			return .freshHit
		}

		if entries.contains(where: {
			canReuseStale($0, for: coordinate, radiusMeters: radiusMeters, now: now)
		}) {
			return .staleHit
		}

		store(
			Entry(
				center: coordinate,
				radiusMeters: radiusMeters,
				storedAt: now,
				data: MapDataSetStub()
			)
		)
		return .fetch
	}

	/// Matches MapDataCache.store: drop same-area entries, insert newest first,
	/// then trim from the tail so the oldest entries are evicted.
	private mutating func store(_ entry: Entry) {
		let survivors = entries.filter {
			!sameArea(
				center: $0.center,
				radiusMeters: $0.radiusMeters,
				as: entry.center,
				requestedRadius: entry.radiusMeters
			)
		}
		entries = survivors
		entries.insert(entry, at: 0)
		if entries.count > tuning.maxEntries {
			entries.removeLast(entries.count - tuning.maxEntries)
		}
	}

	private func canReuse(
		_ entry: Entry,
		for coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		now: TimeInterval
	) -> Bool {
		guard now - entry.storedAt <= tuning.timeToLive else {
			return false
		}
		return sameArea(
			center: entry.center,
			radiusMeters: entry.radiusMeters,
			as: coordinate,
			requestedRadius: radiusMeters
		)
	}

	/// A stale entry must still cover the requested area. A smaller cached area
	/// cannot be treated as if it had been fetched with the larger radius.
	private func canReuseStale(
		_ entry: Entry,
		for coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		now: TimeInterval
	) -> Bool {
		guard now - entry.storedAt <= tuning.staleTimeToLive else {
			return false
		}
		return sameArea(
			center: entry.center,
			radiusMeters: entry.radiusMeters,
			as: coordinate,
			requestedRadius: radiusMeters
		)
	}

	/// Matches MapDataCache.sameArea exactly.
	///
	/// Two independent ways to reuse an entry:
	///   1. The requested circle sits entirely inside the cached circle.
	///   2. The radii match and the centers are within reuseDistanceMeters.
	///
	/// Rule 2 is the one that carries a stationary user, and the one that
	/// collapses the moment you start moving.
	private func sameArea(
		center: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		as coordinate: CLLocationCoordinate2D,
		requestedRadius: CLLocationDistance
	) -> Bool {
		let distanceFromCenter = metersBetween(from: center, to: coordinate)
		let requestedAreaIsCovered = distanceFromCenter + requestedRadius <= radiusMeters
		let centersAreClose = distanceFromCenter <= tuning.reuseDistanceMeters
		return requestedAreaIsCovered
			|| (abs(radiusMeters - requestedRadius) < 1 && centersAreClose)
	}
}

/// Stand-in for MapDataSet. The simulation only counts fetches, so the payload
/// is irrelevant — but keeping a type here preserves the shape of the original.
struct MapDataSetStub {}

// MARK: - Geometry

func metersBetween(
	from start: CLLocationCoordinate2D,
	to end: CLLocationCoordinate2D
) -> CLLocationDistance {
	CLLocation(latitude: start.latitude, longitude: start.longitude)
		.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
}

/// Moves a coordinate `meters` along `bearingDegrees`, using the standard
/// great-circle destination formula. Accurate well past the scale of a bus trip.
func projected(
	from origin: CLLocationCoordinate2D,
	bearingDegrees: Double,
	meters: CLLocationDistance
) -> CLLocationCoordinate2D {
	let earthRadius: Double = 6_372_797.6
	let angularDistance = meters / earthRadius
	let bearing = bearingDegrees * .pi / 180
	let latitude = origin.latitude * .pi / 180
	let longitude = origin.longitude * .pi / 180

	let destinationLatitude = asin(
		sin(latitude) * cos(angularDistance)
			+ cos(latitude) * sin(angularDistance) * cos(bearing)
	)
	let destinationLongitude = longitude + atan2(
		sin(bearing) * sin(angularDistance) * cos(latitude),
		cos(angularDistance) - sin(latitude) * sin(destinationLatitude)
	)

	return CLLocationCoordinate2D(
		latitude: destinationLatitude * 180 / .pi,
		longitude: destinationLongitude * 180 / .pi
	)
}
