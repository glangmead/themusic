//
//  Song.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

struct Song: Identifiable {
  let id = UUID()
  let name: String
  let patternFileNames: [String] // e.g. ["aurora_arpeggio.json"]
}

@MainActor @Observable
class SongLibrary {
  var songs: [Song] = [
    Song(
      name: "Aurora Borealis",
      patternFileNames: ["aurora_arpeggio.json"]
    ),
    Song(
      name: "Baroque Chords",
      patternFileNames: ["baroque_chords.json"]
    ),
    Song(
      name: "Bach Invention 1",
      patternFileNames: ["bach_invention.json"]
    ),
  ]
}
