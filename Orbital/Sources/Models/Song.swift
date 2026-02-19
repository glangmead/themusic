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
    Song(
      name: "Duet Arpeggios",
      patternFileNames: ["duet_arpeggios.json"]
    ),
  ]

  /// Playback states keyed by Song.id, created lazily by SongCells.
  var playbackStates: [UUID: SongPlaybackState] = [:]

  func playbackState(for song: Song, engine: SpatialAudioEngine) -> SongPlaybackState {
    if let existing = playbackStates[song.id] { return existing }
    let state = SongPlaybackState(song: song, engine: engine)
    playbackStates[song.id] = state
    return state
  }

  /// True when any song is currently playing (includes paused).
  var anySongPlaying: Bool {
    playbackStates.values.contains { $0.isPlaying }
  }

  func pauseAll() {
    for state in playbackStates.values where state.isPlaying && !state.isPaused {
      state.pause()
    }
  }

  func resumeAll() {
    for state in playbackStates.values where state.isPlaying && state.isPaused {
      state.resume()
    }
  }

  func stopAll() {
    for state in playbackStates.values where state.isPlaying {
      state.stop()
    }
  }

  /// True when all playing songs are paused.
  var allPaused: Bool {
    let playing = playbackStates.values.filter { $0.isPlaying }
    return !playing.isEmpty && playing.allSatisfy { $0.isPaused }
  }
}
