//
//  WatchCuratedCrossings.swift
//  Intersector Watch App
//
//  Created by Marco Salsiccia on 7/24/26.
//

import Foundation

/// Hand-verified pedestrian crossings that the map data cannot distinguish from an
/// ordinary intersection on its own. Watch copy of the iPhone `CuratedCrossings`
/// table — the Watch target is self-contained and does not share source files with
/// the phone, so the entries must be kept in sync by hand. See the iPhone
/// `CuratedCrossings` for the full rationale (Riverside Drive split blocks, etc.).
///
/// When crossings are enabled, a junction matching an entry is announced as a
/// crossing ("Crossing {road} at {cross street}") and the duplicate plain-intersection
/// announcement at that spot is suppressed. Adding a verified crossing is a one-line
/// addition here and in the iPhone table.
enum WatchCuratedCrossings {
	struct Entry: Equatable {
		let road: String
		let crossStreet: String
	}

	/// Keep in sync with the iPhone `CuratedCrossings.entries`.
	static let entries: [Entry] = [
		Entry(road: "Riverside Drive", crossStreet: "West 94th Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 99th Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 100th Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 101st Street"),
		Entry(road: "Riverside Drive", crossStreet: "West 103rd Street")
	]

	static func entry(forJunctionNamed names: Set<String>) -> Entry? {
		let normalized = Set(names.map { $0.lowercased() })
		return entries.first { entry in
			normalized.contains(entry.road.lowercased())
				&& normalized.contains(entry.crossStreet.lowercased())
		}
	}

	static func title(for entry: Entry) -> String {
		"Crossing \(entry.road) at \(entry.crossStreet)"
	}
}
