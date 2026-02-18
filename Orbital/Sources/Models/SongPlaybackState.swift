//
//  SongPlaybackState.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

/// Per-track info exposed to the UI: the pattern name and its compiled preset.
struct TrackInfo: Identifiable {
  let id: Int
  let patternName: String
  var presetSpec: PresetSyntax
  let spatialPreset: SpatialPreset
}

/// Shared playback state for a song, passed through the Orbital navigation stack
/// so that drill-down views (preset list, preset editor) can show play/pause controls.
@MainActor @Observable
class SongPlaybackState {
  let song: Song
  let engine: SpatialAudioEngine

  private(set) var isPlaying = false
  private(set) var isPaused = false
  private var playbackTask: Task<Void, Never>? = nil
  private var musicPatterns: MusicPatterns? = nil
  private(set) var tracks: [TrackInfo] = []

  /// The active note handler for this song's playback (first track, for visualizer).
  var noteHandler: NoteHandler? { tracks.first?.spatialPreset }

  init(song: Song, engine: SpatialAudioEngine) {
    self.song = song
    self.engine = engine
  }

  func togglePlayback() {
    if isPlaying && !isPaused {
      pause()
    } else if isPlaying && isPaused {
      resume()
    } else {
      play()
    }
  }

  /// Build track info and compiled patterns without starting playback.
  /// Called automatically by `play()`, but can also be called early so the
  /// preset list is populated before the user hits play.
  func loadTracks() {
    guard tracks.isEmpty else { return }

    var compiled: [(MusicPattern, SpatialPreset)] = []
    var trackInfos: [TrackInfo] = []
    var nextTrackId = 0

    for patternFileName in song.patternFileNames {
      let patternSpec = Bundle.main.decode(
        PatternSyntax.self,
        from: patternFileName,
        subdirectory: "patterns"
      )
      let presetFileName = patternSpec.presetFilename + ".json"
      let presetSpec = Bundle.main.decode(
        PresetSyntax.self,
        from: presetFileName,
        subdirectory: "presets"
      )

      // Try multi-track MIDI expansion first
      if let multiTracks = patternSpec.compileMultiTrack(presetSpec: presetSpec, engine: engine) {
        for entry in multiTracks {
          compiled.append((entry.pattern, entry.spatialPreset))
          trackInfos.append(TrackInfo(
            id: nextTrackId,
            patternName: entry.trackName,
            presetSpec: entry.spatialPreset.presetSpec,
            spatialPreset: entry.spatialPreset
          ))
          nextTrackId += 1
        }
      } else {
        // Single-track pattern (generative or MIDI with specific track)
        let (pattern, sp) = patternSpec.compile(
          presetSpec: presetSpec,
          engine: engine
        )
        compiled.append((pattern, sp))
        trackInfos.append(TrackInfo(
          id: nextTrackId,
          patternName: patternSpec.name,
          presetSpec: presetSpec,
          spatialPreset: sp
        ))
        nextTrackId += 1
      }
    }

    tracks = trackInfos
    compiledPatterns = compiled
  }

  /// Patterns compiled by loadTracks(), consumed by play().
  private var compiledPatterns: [(MusicPattern, SpatialPreset)] = []

  func play() {
    guard !isPlaying else { return }

    loadTracks()

    let mp = MusicPatterns()
    musicPatterns = mp

    let compiled = compiledPatterns

    if !engine.audioEngine.isRunning {
      try! engine.start()
    }
    isPlaying = true
    playbackTask = Task.detached {
      await mp.addPatterns(compiled)
      await mp.playAll()
    }
  }

  func pause() {
    guard isPlaying, !isPaused else { return }
    let mp = musicPatterns
    Task { await mp?.pause() }
    isPaused = true
  }

  func resume() {
    guard isPlaying, isPaused else { return }
    let mp = musicPatterns
    Task { await mp?.resume() }
    isPaused = false
  }

  /// Replace the preset for a given track, reloading its audio nodes in place.
  func replacePreset(trackId: Int, newPresetSpec: PresetSyntax) {
    guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
    tracks[idx].presetSpec = newPresetSpec
    tracks[idx].spatialPreset.reload(presetSpec: newPresetSpec)
  }

  func stop() {
    let mp = musicPatterns
    playbackTask?.cancel()
    playbackTask = nil
    musicPatterns = nil
    Task { await mp?.cleanup() }
    tracks = []
    compiledPatterns = []
    isPlaying = false
    isPaused = false
  }
}
