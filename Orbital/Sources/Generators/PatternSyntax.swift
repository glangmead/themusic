//
//  PatternSyntax.swift
//  Orbital
//
//  Codable serialization layer for MusicPattern.
//  PatternSyntax -> compile() -> MusicPattern
//  Parallels PresetSyntax -> compile() -> Preset.
//

import Foundation
import Tonic

// MARK: - Errors

enum PatternCompileError: LocalizedError {
  case midiFileNotFound(String)

  var errorDescription: String? {
    switch self {
    case .midiFileNotFound(let filename): "MIDI file not found: \(filename)"
    }
  }
}

// MARK: - ModulatorSyntax

/// A parameter modulator: targets a named constant in the preset and drives it with an arrow.
struct ModulatorSyntax: Codable {
  let target: String
  let arrow: ArrowSyntax

  func compile() -> (String, Arrow11) {
    (target, arrow.compile())
  }
}

// MARK: - MidiTracksSyntax

/// Per-track configuration for a MIDI pattern (preset + voice count).
/// presetFilename: nil or "randomPad" generates a fresh random pad preset at compile time.
struct MidiTrackEntry: Codable {
  let presetFilename: String?
  let numVoices: Int?
  let modulators: [ModulatorSyntax]?
}

/// Multi-track MIDI specification. A single MIDI file that auto-expands
/// into one track per nonempty MIDI track at compile time.
///
/// Silence and singleton compression are configured globally via
/// `AppConfig.shared` (shortenSilencesEnabled / shortenSingletonsEnabled
/// plus the two max-duration knobs) and applied at compile time.
struct MidiTracksSyntax: Codable {
  let filename: String
  let loop: Bool?
  let bpm: Double?
  let tracks: [MidiTrackEntry]
}

// MARK: - PatternSyntax

/// Top-level Codable specification for a generative music pattern.
/// A pattern has a name and exactly one of:
/// - `midiTracks`: plays a MIDI file
/// - `tableTracks`: generative table with stochastic emitters
/// - `scoreTracks`: score-based absolute-beat sequencing
/// - `generatorTracks`: high-level generator params compiled to scoreTracks at runtime
///
struct PatternSyntax: Codable, Sendable {
  let midiTracks: MidiTracksSyntax?
  let tableTracks: TablePatternSyntax?
  let scoreTracks: ScorePatternSyntax?
  let generatorTracks: GeneratorSyntax?

  init(
    midiTracks: MidiTracksSyntax? = nil,
    tableTracks: TablePatternSyntax? = nil,
    scoreTracks: ScorePatternSyntax? = nil,
    generatorTracks: GeneratorSyntax? = nil
  ) {
    self.midiTracks = midiTracks
    self.tableTracks = tableTracks
    self.scoreTracks = scoreTracks
    self.generatorTracks = generatorTracks
  }

  /// Result of compiling a pattern: separates document data from live audio state.
  struct CompileResult {
    let pattern: MusicPattern
    let trackInfos: [TrackInfo]
    let spatialPresets: [SpatialPreset]
  }

  /// True if this pattern uses *runtime* randomness in its note/chord/timing
  /// generation (independent of any random pad presets). Drives the Takes UI
  /// gating in SongDocument.computeHasRandomness().
  ///
  /// - Generator patterns: always true (the generator engine itself uses RNG).
  /// - Table patterns: true if any emitter uses a random function
  ///   (`randFloat`, `exponentialRandFloat`, `randInt`, `shuffle`, `random`,
  ///   `fragmentPool`).
  /// - Score patterns: false (note data is fully specified).
  /// - MIDI patterns: false (MIDI events are fully specified).
  var hasRuntimeRandomness: Bool {
    if generatorTracks != nil { return true }
    if let table = tableTracks {
      for row in table.emitters {
        switch row.function {
        case .randFloat, .exponentialRandFloat, .randInt,
             .shuffle, .random, .fragmentPool:
          return true
        case .cyclic, .sum, .reciprocal, .indexPicker:
          continue
        }
      }
    }
    return false
  }

  /// Compile all tracks into a single MusicPattern.
  /// `songSeed` is propagated into the resulting MusicPattern so its play()
  /// loop can install per-track sub-seeded RNG boxes for shareable seeds.
  func compile(engine: SpatialAudioEngine, clock: any Clock<Duration> = ContinuousClock(),
               resourceBaseURL: URL? = nil, songSeed: UInt64? = nil) async throws -> CompileResult {
    if let midi = midiTracks {
      return try await compileMidiTracks(midi, engine: engine, clock: clock,
                                         resourceBaseURL: resourceBaseURL, songSeed: songSeed)
    } else if let table = tableTracks {
      return try await TablePatternCompiler.compile(table, engine: engine, clock: clock,
                                                    resourceBaseURL: resourceBaseURL, songSeed: songSeed)
    } else if let score = scoreTracks {
      return try await ScorePatternCompiler.compile(score, engine: engine, clock: clock,
                                                    resourceBaseURL: resourceBaseURL, songSeed: songSeed)
    } else if let gen = generatorTracks {
      let score = GeneratorEngine.generate(gen)
      return try await ScorePatternCompiler.compile(score, engine: engine, clock: clock,
                                                    resourceBaseURL: resourceBaseURL, songSeed: songSeed)
    } else {
      fatalError("PatternSyntax has no tracks")
    }
  }

  /// Compile without an engine — produces TrackInfo for UI-only display.
  /// No audio nodes or SpatialPresets are created.
  func compileTrackInfoOnly(resourceBaseURL: URL? = nil) -> [TrackInfo] {
    if let midi = midiTracks {
      return midi.tracks.enumerated().map { (i, entry) in
        let presetSpec = resolvePresetSpec(filename: entry.presetFilename, gmProgram: nil, resourceBaseURL: resourceBaseURL)
        return TrackInfo(id: i, patternName: "Track \(i)", presetSpec: presetSpec)
      }
    } else if let table = tableTracks {
      return TablePatternCompiler.compileTrackInfoOnly(table, resourceBaseURL: resourceBaseURL)
    } else if let score = scoreTracks {
      return ScorePatternCompiler.compileTrackInfoOnly(score, resourceBaseURL: resourceBaseURL)
    } else if let gen = generatorTracks {
      let score = GeneratorEngine.generate(gen)
      return ScorePatternCompiler.compileTrackInfoOnly(score, resourceBaseURL: resourceBaseURL)
    }
    return []
  }

  // MARK: - Private compilation helpers

  private func compileMidiTracks(
    _ midi: MidiTracksSyntax,
    engine: SpatialAudioEngine,
    clock: any Clock<Duration>,
    resourceBaseURL: URL? = nil,
    songSeed: UInt64? = nil
  ) async throws -> CompileResult {
    guard let url = NoteGeneratorSyntax.midiFileURL(filename: midi.filename, resourceBaseURL: resourceBaseURL) else {
      throw PatternCompileError.midiFileNotFound(midi.filename)
    }

    let loopVal = midi.loop ?? true
    let rawSeqs = MidiEventSequence.allTracks(url: url, loop: loopVal, bpmOverride: midi.bpm)

    let maxSilence: CoreFloat? = AppConfigRuntime.shortenSilencesEnabled
      ? CoreFloat(AppConfigRuntime.maxSilenceSeconds) : nil
    let maxSingleton: CoreFloat? = AppConfigRuntime.shortenSingletonsEnabled
      ? CoreFloat(AppConfigRuntime.maxSingletonSeconds) : nil

    let allSeqs: [(trackIndex: Int, trackName: String, sequence: MidiEventSequence)]
    if maxSilence != nil || maxSingleton != nil {
      let rawSequences = rawSeqs.map(\.sequence)
      let compressed = MidiEventSequence.compressingQuietSectionsGlobally(
        rawSequences, maxSilence: maxSilence, maxSingleton: maxSingleton)
      allSeqs = zip(rawSeqs, compressed).map { ($0.0.trackIndex, $0.0.trackName, $0.1) }
    } else {
      allSeqs = rawSeqs
    }

    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []
    var spatialPresets: [SpatialPreset] = []

    // When fewer track entries are defined than MIDI tracks, the first entry is reused for the
    // remaining tracks. In that case, reduce voices so a single-entry spec applied to many
    // MIDI tracks doesn't overwhelm the audio engine with many SpatialPreset voices.
    let isFallbackMode = !midi.tracks.isEmpty && allSeqs.count > midi.tracks.count
    for (i, entry) in allSeqs.enumerated() {
      let trackEntry = i < midi.tracks.count ? midi.tracks[i] : midi.tracks[0]
      let presetSpec = resolvePresetSpec(
        filename: trackEntry.presetFilename,
        gmProgram: entry.sequence.program,
        characteristicDuration: entry.sequence.medianSustain(),
        resourceBaseURL: resourceBaseURL
      )
      let voices = isFallbackMode ? 2 : (trackEntry.numVoices ?? 12)
      let sp = try await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: voices, resourceBaseURL: resourceBaseURL)

      let modulatorDict = Self.compileModulators(trackEntry.modulators)
      let iters = entry.sequence.makeIterators(loop: loopVal)
      let trackName = entry.trackName.isEmpty ? "Track \(entry.trackIndex)" : entry.trackName

      musicTracks.append(MusicPattern.Track(
        spatialPreset: sp,
        modulators: modulatorDict,
        notes: iters.notes,
        sustains: iters.sustains,
        gaps: iters.gaps,
        name: trackName,
        emitterShadows: [:]
      ))

      trackInfos.append(TrackInfo(id: i, patternName: trackName, presetSpec: presetSpec))
      spatialPresets.append(sp)
    }

    let pattern = MusicPattern(tracks: musicTracks, clock: clock, songSeed: songSeed)
    return CompileResult(pattern: pattern, trackInfos: trackInfos, spatialPresets: spatialPresets)
  }

  private static func compileModulators(_ modulators: [ModulatorSyntax]?) -> [String: Arrow11] {
    guard let mods = modulators else { return [:] }
    return Dictionary(
      mods.map { $0.compile() },
      uniquingKeysWith: { first, _ in first }
    )
  }
}

/// Resolves a preset filename to a PresetSyntax.
/// nil or "randomPad" → fresh random pad preset; any other string → load from the presets bundle directory.
/// `pluckedOrStruck` opts into the impulse-excited-string constraint bundle for random pads only;
/// it has no effect when `filename` names a hand-authored preset (which should carry its own envelope).
func resolvePresetSpec(filename: String?, gmProgram: Int? = nil, characteristicDuration: CoreFloat? = nil,
                       pluckedOrStruck: Bool = false, resourceBaseURL: URL?) -> PresetSyntax {
  guard let filename, filename != "randomPad" else {
    return makeRandomPadPreset(
      gmProgram: gmProgram,
      characteristicDuration: characteristicDuration,
      pluckedOrStruck: pluckedOrStruck
    )
  }
  return decodeJSON(PresetSyntax.self, from: filename + ".json", subdirectory: "presets", resourceBaseURL: resourceBaseURL)
}
