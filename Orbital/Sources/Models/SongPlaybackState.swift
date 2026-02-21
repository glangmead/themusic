//
//  SongPlaybackState.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

/// Per-track info exposed to the UI: the track name, its spec, and its compiled preset.
/// `trackSpec` is nil for MIDI tracks (their note data comes from the file).
struct TrackInfo: Identifiable {
  let id: Int
  let patternName: String
  var trackSpec: ProceduralTrackSyntax?
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
  private(set) var isLoading = false
  /// Set when loading fails; shown as an alert to the user.
  var loadError: String?
  private var playbackTask: Task<Void, Never>? = nil
  /// Compiled pattern ready for playback.
  private var compiledPattern: MusicPattern?

  private(set) var tracks: [TrackInfo] = []

  /// The stored PatternSyntax, kept so we can rebuild after user edits.
  private var patternSpec: PatternSyntax?

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
  func loadTracks() async throws {
    guard compiledPattern == nil else { return }

    // If tracks already exist (from a previous load), recompile from in-memory
    // patternSpec to preserve user edits across stop/play cycles.
    if !tracks.isEmpty {
      if engine != nil { try await recompileFromSpec() }
      return
    }

    let spec = Bundle.main.decode(
      PatternSyntax.self,
      from: song.patternFileName,
      subdirectory: "patterns"
    )

    if let engine {
      let (pattern, infos) = try await spec.compile(engine: engine)
      compiledPattern = pattern
      tracks = infos.enumerated().map { i, info in
        TrackInfo(
          id: i,
          patternName: info.patternName,
          trackSpec: info.trackSpec,
          presetSpec: info.presetSpec,
          spatialPreset: info.spatialPreset
        )
      }
    } else {
      // UI-only: build TrackInfo without audio nodes
      let infos = spec.compileTrackInfoOnly()
      tracks = infos.enumerated().map { i, info in
        TrackInfo(
          id: i,
          patternName: info.patternName,
          trackSpec: info.trackSpec,
          presetSpec: info.presetSpec,
          spatialPreset: info.spatialPreset
        )
      }
    }

    patternSpec = spec
  }

  /// Recompile from the stored in-memory spec (preserves user edits).
  private func recompileFromSpec() async throws {
    guard let engine, let spec = patternSpec else { return }
    let (pattern, infos) = try await spec.compile(engine: engine)
    compiledPattern = pattern
    tracks = infos.enumerated().map { i, info in
      TrackInfo(
        id: i,
        patternName: info.patternName,
        trackSpec: info.trackSpec,
        presetSpec: info.presetSpec,
        spatialPreset: info.spatialPreset
      )
    }
  }

  /// Replace the procedural track spec for a given track. Takes effect on next play().
  func replaceTrack(trackId: Int, newTrackSpec: ProceduralTrackSyntax) {
    guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
    tracks[idx].trackSpec = newTrackSpec
    updatePatternSpec(forTrackAt: idx, newTrackSpec: newTrackSpec)
    compiledPattern = nil
  }

  /// Update the ProceduralTrackSyntax at the given index in the stored PatternSyntax.
  private func updatePatternSpec(forTrackAt trackIdx: Int, newTrackSpec: ProceduralTrackSyntax) {
    guard let spec = patternSpec, var procedural = spec.proceduralTracks else { return }
    guard trackIdx >= 0 && trackIdx < procedural.count else { return }
    procedural[trackIdx] = newTrackSpec
    patternSpec = PatternSyntax(
      name: spec.name,
      proceduralTracks: procedural,
      midiTracks: nil
    )
  }

  /// Stop and immediately restart playback (applies any pending edits).
  func restart() {
    stop()
    play()
  }

  func play() {
    guard !isPlaying, !isLoading, let engine else { return }

    // Stop the engine while we build the audio graph to avoid render errors
    // from partially-connected nodes in a live graph.
    engine.audioEngine.stop()

    loadError = nil
    isLoading = true

    // Use a Task so the main run loop can process UI updates (spinner)
    // while the expensive SoundFont loading happens on background threads.
    playbackTask = Task {
      do {
        try await loadTracks()
      } catch {
        for track in tracks {
          track.spatialPreset.detachNodes()
        }
        tracks = []
        compiledPattern = nil
        loadError = error.localizedDescription
        isLoading = false
        return
      }

      try? engine.start()
      isLoading = false
      isPlaying = true

      await compiledPattern?.play()
    }
  }

  func pause() {
    guard isPlaying, !isPaused else { return }
    if let pattern = compiledPattern {
      Task { await pattern.setPaused(true) }
    }
    isPaused = true
  }

  func resume() {
    guard isPlaying, isPaused else { return }
    if let pattern = compiledPattern {
      Task { await pattern.setPaused(false) }
    }
    isPaused = false
  }

  /// Replace the preset for a given track, reloading its audio nodes in place.
  func replacePreset(trackId: Int, newPresetSpec: PresetSyntax) {
    guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
    tracks[idx].presetSpec = newPresetSpec
    tracks[idx].spatialPreset.reload(presetSpec: newPresetSpec)
  }

  func stop() {
    playbackTask?.cancel()
    playbackTask = nil
    // Stop the engine before detaching to avoid crashes from mutating
    // the node graph while the render thread is pulling audio.
    engine?.audioEngine.stop()
    for track in tracks {
      track.spatialPreset.detachNodes()
    }
    compiledPattern = nil
    isLoading = false
    isPlaying = false
    isPaused = false
  }
}
