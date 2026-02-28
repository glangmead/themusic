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
struct MidiTrackEntry: Codable {
  let presetFilename: String
  let numVoices: Int?
  let modulators: [ModulatorSyntax]?
}

/// Multi-track MIDI specification. A single MIDI file that auto-expands
/// into one track per nonempty MIDI track at compile time.
struct MidiTracksSyntax: Codable {
  let filename: String
  let loop: Bool?
  let tracks: [MidiTrackEntry]
}

// MARK: - PatternSyntax

/// Top-level Codable specification for a generative music pattern.
/// A pattern has a name and exactly one of:
/// - `midiTracks`: plays a MIDI file
/// - `tableTracks`: generative table with stochastic emitters
/// - `scoreTracks`: score-based absolute-beat sequencing
struct PatternSyntax: Codable {
  let name: String
  let midiTracks: MidiTracksSyntax?
  let tableTracks: TablePatternSyntax?
  let scoreTracks: ScorePatternSyntax?

  /// Result of compiling a pattern: separates document data from live audio state.
  struct CompileResult {
    let pattern: MusicPattern
    let trackInfos: [TrackInfo]
    let spatialPresets: [SpatialPreset]
  }

  /// Compile all tracks into a single MusicPattern.
  func compile(engine: SpatialAudioEngine, clock: any Clock<Duration> = ContinuousClock(), resourceBaseURL: URL? = nil) async throws -> CompileResult {
    if let midi = midiTracks {
      return try await compileMidiTracks(midi, engine: engine, clock: clock, resourceBaseURL: resourceBaseURL)
    } else if let table = tableTracks {
      return try await TablePatternCompiler.compile(table, engine: engine, clock: clock, resourceBaseURL: resourceBaseURL)
    } else if let score = scoreTracks {
      return try await ScorePatternCompiler.compile(score, engine: engine, clock: clock, resourceBaseURL: resourceBaseURL)
    } else {
      fatalError("PatternSyntax '\(name)' has no tracks")
    }
  }

  /// Compile without an engine — produces TrackInfo for UI-only display.
  /// No audio nodes or SpatialPresets are created.
  func compileTrackInfoOnly(resourceBaseURL: URL? = nil) -> [TrackInfo] {
    if let midi = midiTracks {
      return midi.tracks.enumerated().map { (i, entry) in
        let presetFileName = entry.presetFilename + ".json"
        let presetSpec = decodeJSON(PresetSyntax.self, from: presetFileName, subdirectory: "presets", resourceBaseURL: resourceBaseURL)
        return TrackInfo(id: i, patternName: "Track \(i)", presetSpec: presetSpec)
      }
    } else if let table = tableTracks {
      return TablePatternCompiler.compileTrackInfoOnly(table, resourceBaseURL: resourceBaseURL)
    } else if let score = scoreTracks {
      return ScorePatternCompiler.compileTrackInfoOnly(score, resourceBaseURL: resourceBaseURL)
    }
    return []
  }

  // MARK: - Private compilation helpers

  private func compileMidiTracks(
    _ midi: MidiTracksSyntax,
    engine: SpatialAudioEngine,
    clock: any Clock<Duration>,
    resourceBaseURL: URL? = nil
  ) async throws -> CompileResult {
    guard let url = NoteGeneratorSyntax.midiFileURL(filename: midi.filename, resourceBaseURL: resourceBaseURL) else {
      fatalError("MIDI file not found: \(midi.filename)")
    }

    let loopVal = midi.loop ?? true
    let allSeqs = MidiEventSequence.allTracks(url: url, loop: loopVal)

    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []
    var spatialPresets: [SpatialPreset] = []

    for (i, entry) in allSeqs.enumerated() {
      let trackEntry = i < midi.tracks.count ? midi.tracks[i] : midi.tracks[0]
      let presetFileName = trackEntry.presetFilename + ".json"
      let presetSpec = decodeJSON(PresetSyntax.self, from: presetFileName, subdirectory: "presets", resourceBaseURL: resourceBaseURL)
      let voices = trackEntry.numVoices ?? 12
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

    let pattern = MusicPattern(tracks: musicTracks, clock: clock)
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

