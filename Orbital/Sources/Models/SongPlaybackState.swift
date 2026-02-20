//
//  SongPlaybackState.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

/// Per-track info exposed to the UI: the pattern name, its spec, and its compiled preset.
struct TrackInfo: Identifiable {
  let id: Int
  let patternName: String
  var patternSpec: PatternSyntax
  var presetSpec: PresetSyntax
  let spatialPreset: SpatialPreset
}

/// Shared playback state for a song, passed through the Orbital navigation stack
/// so that drill-down views (preset list, preset editor) can show play/pause controls.
@MainActor @Observable
class SongPlaybackState {
  let song: Song
  let engine: SpatialAudioEngine?

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

  /// UI-only init: loads track info (patterns, presets, spatial data) without an audio engine.
  /// Playback controls are disabled in this mode.
  init(song: Song) {
    self.song = song
    self.engine = nil
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
  /// When no engine is available, builds UI-only track info (no audio nodes).
  func loadTracks() {
    guard compiledPatterns.isEmpty else { return }

    // If tracks already exist (from a previous load), recompile from in-memory
    // patternSpecs to preserve user edits across stop/play cycles.
    if !tracks.isEmpty {
      if engine != nil { recompileFromTracks() }
      return
    }

    var compiled: [(MusicPattern, SpatialPreset)] = []
    var trackInfos: [TrackInfo] = []
    var nextTrackId = 0

    for patternFileName in song.patternFileNames {
      let patternFile = Bundle.main.decode(
        PatternFile.self,
        from: patternFileName,
        subdirectory: "patterns"
      )

      for patternSpec in patternFile.patterns {
        let presetFileName = patternSpec.presetFilename + ".json"
        let presetSpec = Bundle.main.decode(
          PresetSyntax.self,
          from: presetFileName,
          subdirectory: "presets"
        )

        if let engine {
          // Full compilation with audio engine
          if let multiTracks = patternSpec.compileMultiTrack(presetSpec: presetSpec, engine: engine) {
            for entry in multiTracks {
              compiled.append((entry.pattern, entry.spatialPreset))
              trackInfos.append(TrackInfo(
                id: nextTrackId,
                patternName: entry.trackName,
                patternSpec: patternSpec,
                presetSpec: entry.spatialPreset.presetSpec,
                spatialPreset: entry.spatialPreset
              ))
              nextTrackId += 1
            }
          } else {
            let (pattern, sp) = patternSpec.compile(
              presetSpec: presetSpec,
              engine: engine
            )
            compiled.append((pattern, sp))
            trackInfos.append(TrackInfo(
              id: nextTrackId,
              patternName: patternSpec.name,
              patternSpec: patternSpec,
              presetSpec: presetSpec,
              spatialPreset: sp
            ))
            nextTrackId += 1
          }
        } else {
          // UI-only: build TrackInfo with lightweight SpatialPreset (no audio nodes)
          let sp = SpatialPreset(presetSpec: presetSpec, numVoices: patternSpec.numVoices ?? 12)
          trackInfos.append(TrackInfo(
            id: nextTrackId,
            patternName: patternSpec.name,
            patternSpec: patternSpec,
            presetSpec: presetSpec,
            spatialPreset: sp
          ))
          nextTrackId += 1
        }
      }
    }

    tracks = trackInfos
    compiledPatterns = compiled
  }

  /// Recompile patterns from the existing in-memory tracks (preserves user edits).
  private func recompileFromTracks() {
    guard let engine else { return }
    var compiled: [(MusicPattern, SpatialPreset)] = []
    for track in tracks {
      let presetFileName = track.patternSpec.presetFilename + ".json"
      let presetSpec = Bundle.main.decode(
        PresetSyntax.self,
        from: presetFileName,
        subdirectory: "presets"
      )
      let (pattern, sp) = track.patternSpec.compile(
        presetSpec: presetSpec,
        engine: engine
      )
      compiled.append((pattern, sp))
    }
    compiledPatterns = compiled
  }

  /// Replace the pattern spec for a given track. Takes effect on next play().
  func replacePattern(trackId: Int, newPatternSpec: PatternSyntax) {
    guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
    tracks[idx].patternSpec = newPatternSpec
    compiledPatterns = []  // Force recompilation on next play()
  }

  /// Stop and immediately restart playback (applies any pending edits).
  func restart() {
    stop()
    play()
  }

  /// Patterns compiled by loadTracks(), consumed by play().
  private var compiledPatterns: [(MusicPattern, SpatialPreset)] = []

  func play() {
    guard !isPlaying, let engine else { return }

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
    Task { await mp?.detachNodes() }
    compiledPatterns = []
    isPlaying = false
    isPaused = false
  }
}
