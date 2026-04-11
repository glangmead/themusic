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
  let takesStore: TakesStore?

  private(set) var phase: PlaybackPhase = .idle
  /// Set when loading fails; shown as an alert to the user.
  var loadError: String?
  private var playbackTask: Task<Void, Never>?
  private var annotationTask: Task<Void, Never>?
  private var chordLabelTask: Task<Void, Never>?

  // MARK: - Shareable song seed lifecycle

  /// The 64-bit seed in effect for the currently loaded compiled state.
  /// Set on every play() (either decoded from `pendingSeedString` or freshly
  /// generated). Cleared on stop().
  private(set) var currentSeed: UInt64?

  /// Crockford base32 encoding of currentSeed for display/copy/paste UI.
  var currentSeedString: String? { currentSeed.map(SeedCodec.encode) }

  /// True iff this song has any randomness consumers (random pad,
  /// generator pattern, ArrowRandom, NoiseSmoothStep, etc.).
  /// Drives whether the seed UI is shown.
  /// Computed after compile in play().
  private(set) var hasRandomness: Bool = false

  /// In-flight take entry id for the active play, if any.
  private var currentTakeEntryID: UUID?
  /// Wall-clock anchor for the most recent resume; nil while paused or stopped.
  private var lastResumeAnchor: Date?
  /// Cumulative played seconds across pause/resume cycles within one play session.
  private var accumulatedPlayedSeconds: Double = 0

  /// Seed string supplied by the UI for the next play. Cleared after consumption.
  private var pendingSeedString: String?

  /// UI calls this before `play()` to request a specific take. Pass nil to
  /// roll a fresh seed on the next play.
  func setPendingSeed(_ seedString: String?) {
    self.pendingSeedString = seedString
  }

  // MARK: - Event log

  /// Rolling log of event annotations, most recent last. Capped at maxLogEntries.
  private(set) var eventLog: [EventAnnotation] = []
  private static let maxLogEntries = 500

  // MARK: - Chord label

  /// The most recently emitted chord change label from the score's harmony timeline.
  /// Nil when no score pattern is playing or it has no chord events with labels.
  private(set) var currentChordLabel: String?

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

  init(song: SongRef, engine: SpatialAudioEngine, resourceBaseURL: URL? = nil, takesStore: TakesStore? = nil) {
    self.song = song
    self.engine = engine
    self.resourceBaseURL = resourceBaseURL
    self.takesStore = takesStore
  }

  /// UI-only init: loads track info (patterns, presets, spatial data) without an audio engine.
  /// Playback controls are disabled in this mode.
  init(song: SongRef) {
    self.song = song
    self.engine = nil
    self.resourceBaseURL = nil
    self.takesStore = nil
  }

  /// Init for the standalone Create tab — pre-seeds a generator pattern so
  /// loadTracks() skips file loading and compiles directly from the spec.
  init(generatorPattern: GeneratorSyntax, engine: SpatialAudioEngine, takesStore: TakesStore? = nil) {
    self.song = SongRef(patternFileName: PatternFilename.filename(from: "Create"))
    self.engine = engine
    self.resourceBaseURL = nil
    self.takesStore = takesStore
    patternSpec = PatternSyntax(generatorTracks: generatorPattern)
  }

  /// Init for the Classics browser — pre-seeds a PatternSyntax built from catalog data.
  /// loadTracks() skips JSON file loading and compiles directly from the spec.
  init(patternSyntax: PatternSyntax, displayName: String, subtitle: String? = nil,
       engine: SpatialAudioEngine, resourceBaseURL: URL? = nil, takesStore: TakesStore? = nil) {
    self.song = SongRef(subtitle: subtitle, patternFileName: PatternFilename.filename(from: displayName))
    self.engine = engine
    self.resourceBaseURL = resourceBaseURL
    self.takesStore = takesStore
    self.patternSpec = patternSyntax
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

    // If patternSpec was pre-seeded (e.g. Create tab generator init), skip file loading.
    if patternSpec != nil {
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
      let result = try await spec.compile(engine: engine, resourceBaseURL: resourceBaseURL, songSeed: currentSeed)
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
    let result = try await spec.compile(engine: engine, resourceBaseURL: resourceBaseURL, songSeed: currentSeed)
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

    // Force a recompile under the seed scope. Without this, a previously
    // populated runtime would short-circuit loadTracks() and the per-node
    // PRNG seeds would never apply.
    teardownRuntime()

    let seedString = pendingSeedString
    pendingSeedString = nil
    let seed: UInt64 = seedString.flatMap(SeedCodec.decode) ?? SeedCodec.random()
    currentSeed = seed
    accumulatedPlayedSeconds = 0
    currentTakeEntryID = nil

    loadError = nil
    phase = .loading
    eventLog = []
    currentChordLabel = nil

    playbackTask = Task {
      do {
        try await engine.withQuiescedGraph {
          try await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
            try await self.loadTracks()
            // Apply per-node random seeds to every voice graph in every spatial preset.
            if let runtime = self.runtime {
              for sp in runtime.spatialPresets {
                sp.resetRandomSeeds(songSeed: seed)
              }
            }
            // Detect randomness presence for UI gating.
            self.hasRandomness = self.computeHasRandomness()
          }
        }
      } catch {
        self.teardownRuntime()
        loadError = error.localizedDescription
        phase = .idle
        return
      }

      phase = .playing

      // Record the take in the registry, if there's randomness to record.
      if hasRandomness, let store = takesStore {
        currentTakeEntryID = store.recordStart(songId: song.id, seed: SeedCodec.encode(seed))
        lastResumeAnchor = Date()
      }

      // Subscribe to annotation streams for the event log.
      if let pattern = runtime?.compiledPattern {
        let streams = await pattern.getAnnotationStreams()
        // Spawn a plain fire-and-forget Task per stream instead of wrapping
        // them in `withTaskGroup`. The task-group + `@MainActor in` closure
        // pattern trips a Swift 6 region-based isolation checker bug. Each
        // child task is stored so `stop()` can cancel it individually.
        var childTasks: [Task<Void, Never>] = []
        for stream in streams {
          let task = Task { @MainActor in
            for await annotation in stream {
              self.eventLog.append(annotation)
              if self.eventLog.count > Self.maxLogEntries {
                self.eventLog.removeFirst(self.eventLog.count - Self.maxLogEntries)
              }
            }
          }
          childTasks.append(task)
        }
        annotationTask = Task { @MainActor in
          for t in childTasks { await t.value }
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
    if let anchor = lastResumeAnchor {
      accumulatedPlayedSeconds += Date().timeIntervalSince(anchor)
      lastResumeAnchor = nil
    }
    if let id = currentTakeEntryID, let store = takesStore {
      store.updatePlayedSeconds(id: id, accumulatedPlayedSeconds)
    }
    if let pattern = runtime?.compiledPattern {
      Task { await pattern.setPaused(true) }
    }
    phase = .paused
  }

  func resume() {
    guard phase == .paused else { return }
    lastResumeAnchor = Date()
    if let pattern = runtime?.compiledPattern {
      Task { await pattern.setPaused(false) }
    }
    phase = .playing
  }

  /// True if anything about this song's playback could vary from one play to
  /// the next: either the pattern uses runtime random emitters/iterators
  /// (table patterns with random functions, generator patterns), or any
  /// SpatialPreset has Arrow-level randomness (random pad, NoiseSmoothStep,
  /// ArrowRandom, etc.).
  private func computeHasRandomness() -> Bool {
    if patternSpec?.hasRuntimeRandomness == true { return true }
    guard let runtime else { return false }
    return runtime.spatialPresets.contains { $0.hasArrowRandomness }
  }

  /// Replace the preset for a given track, reloading its audio nodes in place.
  func replacePreset(trackId: Int, newPresetSpec: PresetSyntax) {
    guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
    tracks[idx].presetSpec = newPresetSpec
    runtime?.spatialPresets[trackId].reload(presetSpec: newPresetSpec)
  }

  func stop() {
    if let anchor = lastResumeAnchor {
      accumulatedPlayedSeconds += Date().timeIntervalSince(anchor)
      lastResumeAnchor = nil
    }
    if let id = currentTakeEntryID, let store = takesStore {
      store.recordStop(id: id, playedSeconds: accumulatedPlayedSeconds)
    }
    currentTakeEntryID = nil
    accumulatedPlayedSeconds = 0
    currentSeed = nil
    hasRandomness = false

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
    patternSpec = PatternSyntax(tableTracks: newTable)
    runtime = nil
  }

  // MARK: - MIDI pattern accessors

  /// The MIDI tracks syntax, if this is a MIDI-based pattern.
  var midiPattern: MidiTracksSyntax? {
    patternSpec?.midiTracks
  }

  /// Replace the MIDI tracks definition. Takes effect on next play().
  func replaceMidiPattern(_ newMidi: MidiTracksSyntax) {
    patternSpec = PatternSyntax(midiTracks: newMidi)
    runtime = nil
  }

  // MARK: - Generator pattern accessors

  /// The generator syntax, if this is a generator-based pattern.
  var generatorPattern: GeneratorSyntax? {
    patternSpec?.generatorTracks
  }

  /// Replace the generator definition and hot-reload. Takes effect on next play().
  func replaceGeneratorPattern(_ newGen: GeneratorSyntax) {
    patternSpec = PatternSyntax(generatorTracks: newGen)
    runtime = nil
  }
}
