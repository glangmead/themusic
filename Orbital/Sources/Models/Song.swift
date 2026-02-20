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

  /// The currently playing (or paused) song's state, if any.
  var currentPlaybackState: SongPlaybackState?

  func playbackState(for song: Song, engine: SpatialAudioEngine) -> SongPlaybackState {
    if let existing = playbackStates[song.id] { return existing }
    let state = SongPlaybackState(song: song, engine: engine)
    playbackStates[song.id] = state
    return state
  }

  /// Start playing a song, stopping any currently playing song first.
  /// If the tapped song is already the current song, toggle pause/resume.
  func play(_ song: Song, engine: SpatialAudioEngine) {
    let state = playbackState(for: song, engine: engine)
    if state === currentPlaybackState {
      state.togglePlayback()
      return
    }
    currentPlaybackState?.stop()
    currentPlaybackState = state
    state.togglePlayback()
  }

  /// True when the current song is playing (includes paused).
  var anySongPlaying: Bool {
    currentPlaybackState?.isPlaying == true
  }

  /// True when the current song is paused.
  var allPaused: Bool {
    currentPlaybackState?.isPaused == true
  }

  /// The name of the currently playing song, if any.
  var currentSongName: String? {
    guard let state = currentPlaybackState, state.isPlaying else { return nil }
    return state.song.name
  }

  func pauseAll() {
    currentPlaybackState?.pause()
  }

  func resumeAll() {
    currentPlaybackState?.resume()
  }

  func stopAll() {
    currentPlaybackState?.stop()
    currentPlaybackState = nil
  }
}
