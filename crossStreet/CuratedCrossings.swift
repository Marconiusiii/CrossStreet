//
//  CuratedCrossings.swift
//  Intersector
//
//  Created by Marco Salsiccia on 7/24/26.
//

import Foundation

/// Hand-verified pedestrian crossings that the map data cannot distinguish from an
/// ordinary intersection on its own.
///
/// Some real crossings sit exactly where a cross street meets a road, so they look
/// identical in the data to a plain junction (the Riverside Drive "split" blocks in
/// Manhattan are the motivating case: a signalized crossing carries a pedestrian
/// across the main roadway and the park median to reach the service road, but the
/// only thing in the data at that spot is a normal-looking junction node). The
/// automatic mid-block rule deliberately will not surface these, because doing so
/// generally would add crossing verbosity to every ordinary intersection.
///
/// Instead we curate them by hand. Each entry names the road the pedestrian crosses
/// and the cross street at that junction. When crossings are enabled, a matching
/// junction is announced as a crossing ("Crossing {road} at {cross street}") and the
/// duplicate plain-intersection announcement at that spot is suppressed everywhere.
///
/// Adding a new verified crossing is a one-line addition to `entries`.
enum CuratedCrossings {
	/// A single curated crossing: the road being crossed and the cross street it
	/// meets. Matching is case-insensitive and order-independent on the pair of
	/// names, but the wording always reads "{road} at {crossStreet}".
	struct Entry: Equatable {
		let road: String
		let crossStreet: String
	}

	/// The verified crossings. Seeded with the confirmed Riverside Drive blocks.
	/// Add more here once a tester has confirmed them on the ground.
	static let entries: [Entry] = [
		Entry(road: "Riverside Drive", crossStreet: "West 94th Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 99th Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 100th Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 101st Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 103rd Street")
	]

	/// Returns the curated entry for a junction carrying exactly these street names,
	/// if one exists. `names` is the set of street names meeting at the junction.
	static func entry(forJunctionNamed names: Set<String>) -> Entry? {
		let normalized = Set(names.map { $0.lowercased() })
		return entries.first { entry in
			normalized.contains(entry.road.lowercased())
				&& normalized.contains(entry.crossStreet.lowercased())
		}
	}

	/// The spoken title for a curated crossing, e.g. "Crossing Riverside Drive at
	/// West 99th Street".
	static func title(for entry: Entry) -> String {
		"Crossing \(entry.road) at \(entry.crossStreet)"
	}
}
