//
//  SongDocument.swift (was SongPlaybackState.swift)
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

/// Live audio state that exists only while a song is loaded for playback.
/// Created during `loadTracks()`, destroyed on `stop()`.
struct RuntimeSong {
  let compiledPattern: MusicPattern
  let spatialPresets: [SpatialPreset]

  var noteHandler: NoteHandler? { spatialPresets.first }
}

/// Document model for a song: owns editable track metadata, pattern specs,
/// and live playback state. Passed through the SwiftUI environment so that
/// drill-down views (preset list, preset editor, spatial form) can read and
/// edit the song and control playback.
@MainActor @Observable
class SongDocument {
  enum PlaybackPhase {
    case idle
    case loading
    case playing
    case paused
  }

  let song: SongRef
  let engine: SpatialAudioEngine?
  let resourceBaseURL: URL?

  private(set) var phase: PlaybackPhase = .idle
  /// Set when loading fails; shown as an alert to the user.
  var loadError: String?
  private var playbackTask: Task<Void, Never>? = nil
  private var annotationTask: Task<Void, Never>? = nil
  private var chordLabelTask: Task<Void, Never>? = nil

  // MARK: - Event log

  /// Rolling log of event annotations, most recent last. Capped at maxLogEntries.
  private(set) var eventLog: [EventAnnotation] = []
  private static let maxLogEntries = 500

  // MARK: - Chord label

  /// The most recently emitted chord change label from the score's harmony timeline.
  /// Nil when no score pattern is playing or it has no chord events with labels.
  private(set) var currentChordLabel: String? = nil

  // MARK: - Document state (survives stop/play cycles)

  /// Track metadata for UI display and editing.
  private(set) var tracks: [TrackInfo] = []
  /// The stored PatternSyntax, kept so we can rebuild after user edits.
  private var patternSpec: PatternSyntax?

  // MARK: - Runtime state (exists only while loaded)

  /// Live audio objects; nil when idle.
  private(set) var runtime: RuntimeSong?

  // MARK: - Convenience accessors

  var isPlaying: Bool { phase == .playing || phase == .paused }
  var isPaused: Bool { phase == .paused }
  var isLoading: Bool { phase == .loading }

  /// The active note handler for this song's playback (first track, for visualizer).
  var noteHandler: NoteHandler? { runtime?.noteHandler }

  /// Spatial preset for a given track, if loaded.
  func spatialPreset(forTrack trackId: Int) -> SpatialPreset? {
    guard let runtime, trackId >= 0, trackId < runtime.spatialPresets.count else { return nil }
    return runtime.spatialPresets[trackId]
  }

  init(song: SongRef, engine: SpatialAudioEngine, resourceBaseURL: URL? = nil) {
    self.song = song
    self.engine = engine
    self.resourceBaseURL = resourceBaseURL
  }

  /// UI-only init: loads track info (patterns, presets, spatial data) without an audio engine.
  /// Playback controls are disabled in this mode.
  init(song: SongRef) {
    self.song = song
    self.engine = nil
    self.resourceBaseURL = nil
  }

  func togglePlayback() {
    switch phase {
    case .playing: pause()
    case .paused:  resume()
    case .idle:    play()
    case .loading: break
    }
  }

  /// Build track info and compiled patterns without starting playback.
  /// Called automatically by `play()`, but can also be called early so the
  /// preset list is populated before the user hits play.
  /// When no engine is available, builds UI-only track info (no audio nodes).
  func loadTracks() async throws {
    guard runtime == nil else { return }

    // If tracks already exist (from a previous load), recompile from in-memory
    // patternSpec to preserve user edits across stop/play cycles.
    if !tracks.isEmpty {
      if engine != nil { try await recompileFromSpec() }
      return
    }

    let spec = decodeJSON(
      PatternSyntax.self,
      from: song.patternFileName,
      subdirectory: "patterns",
      resourceBaseURL: resourceBaseURL
    )

    if let engine {
      let result = try await spec.compile(engine: engine, resourceBaseURL: resourceBaseURL)
      runtime = RuntimeSong(
        compiledPattern: result.pattern,
        spatialPresets: result.spatialPresets
      )
      tracks = result.trackInfos
    } else {
      // UI-only: build TrackInfo without audio nodes
      tracks = spec.compileTrackInfoOnly(resourceBaseURL: resourceBaseURL)
    }

    patternSpec = spec
  }

  /// Recompile from the stored in-memory spec (preserves user edits).
  private func recompileFromSpec() async throws {
    guard let engine, let spec = patternSpec else { return }
    let result = try await spec.compile(engine: engine, resourceBaseURL: resourceBaseURL)
    runtime = RuntimeSong(
      compiledPattern: result.pattern,
      spatialPresets: result.spatialPresets
    )
    tracks = result.trackInfos
  }

  /// Stop and immediately restart playback (applies any pending edits).
  func restart() {
    stop()
    play()
  }

  func play() {
    guard phase == .idle, let engine else { return }

    loadError = nil
    phase = .loading
    eventLog = []
    currentChordLabel = nil

    playbackTask = Task {
      do {
        try await engine.withQuiescedGraph {
          try await self.loadTracks()
        }
      } catch {
        self.teardownRuntime()
        loadError = error.localizedDescription
        phase = .idle
        return
      }

      phase = .playing

      // Subscribe to annotation streams for the event log.
      if let pattern = runtime?.compiledPattern {
        let streams = await pattern.getAnnotationStreams()
        annotationTask = Task {
          await withTaskGroup(of: Void.self) { group in
            for stream in streams {
              group.addTask { @MainActor in
                for await annotation in stream {
                  self.eventLog.append(annotation)
                  if self.eventLog.count > Self.maxLogEntries {
                    self.eventLog.removeFirst(self.eventLog.count - Self.maxLogEntries)
                  }
                }
              }
            }
          }
        }

        // Chord label stream gets its own task so it's observed directly by SwiftUI
        // without going through the task group's intermediate layer.
        let chordStream = await pattern.getChordLabelStream()
        chordLabelTask = Task { @MainActor in
          for await label in chordStream {
            self.currentChordLabel = label
          }
        }
      }

      await runtime?.compiledPattern.play()
    }
  }

  func pause() {
    guard phase == .playing else { return }
    if let pattern = runtime?.compiledPattern {
      Task { await pattern.setPaused(true) }
    }
    phase = .paused
  }

  func resume() {
    guard phase == .paused else { return }
    if let pattern = runtime?.compiledPattern {
      Task { await pattern.setPaused(false) }
    }
    phase = .playing
  }

  /// Replace the preset for a given track, reloading its audio nodes in place.
  func replacePreset(trackId: Int, newPresetSpec: PresetSyntax) {
    guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
    tracks[idx].presetSpec = newPresetSpec
    runtime?.spatialPresets[trackId].reload(presetSpec: newPresetSpec)
  }

  func stop() {
    playbackTask?.cancel()
    playbackTask = nil
    annotationTask?.cancel()
    annotationTask = nil
    chordLabelTask?.cancel()
    chordLabelTask = nil
    engine?.stop()
    teardownRuntime()
    phase = .idle
  }

  private func teardownRuntime() {
    if let runtime {
      for sp in runtime.spatialPresets {
        sp.detachNodes()
      }
    }
    runtime = nil
  }

  // MARK: - Table pattern access

  /// Whether the pattern uses the table-based definition.
  var hasTablePattern: Bool {
    patternSpec?.tableTracks != nil
  }

  /// The table pattern syntax, if this is a table-based pattern.
  var tablePattern: TablePatternSyntax? {
    patternSpec?.tableTracks
  }

  /// Replace the table pattern definition. Takes effect on next play().
  func replaceTablePattern(_ newTable: TablePatternSyntax) {
    guard let spec = patternSpec else { return }
    patternSpec = PatternSyntax(
      name: spec.name,
      midiTracks: nil,
      tableTracks: newTable,
      scoreTracks: nil
    )
    runtime = nil
  }
}
