//
//  Song.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

struct Song: Identifiable {
  let id = UUID()
  let name: String
  let patternFileName: String   // e.g. "aurora_arpeggio.json"
  let presetFileNames: [String] // e.g. ["auroraBorealis.json"]
}

@MainActor @Observable
class SongLibrary {
  var songs: [Song] = [
    Song(
      name: "Aurora Borealis",
      patternFileName: "aurora_arpeggio.json",
      presetFileNames: ["auroraBorealis.json"]
    )
  ]
}
