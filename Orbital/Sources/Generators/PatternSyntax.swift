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
/// presetFilename: nil or "randomPad" generates a fresh random pad preset at compile time.
struct MidiTrackEntry: Codable {
  let presetFilename: String?
  let numVoices: Int?
  let modulators: [ModulatorSyntax]?
}

/// Multi-track MIDI specification. A single MIDI file that auto-expands
/// into one track per nonempty MIDI track at compile time.
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
struct PatternSyntax: Codable {
  let name: String
  let midiTracks: MidiTracksSyntax?
  let tableTracks: TablePatternSyntax?
  let scoreTracks: ScorePatternSyntax?
  let generatorTracks: GeneratorSyntax?

  init(
    name: String,
    midiTracks: MidiTracksSyntax? = nil,
    tableTracks: TablePatternSyntax? = nil,
    scoreTracks: ScorePatternSyntax? = nil,
    generatorTracks: GeneratorSyntax? = nil
  ) {
    self.name = name
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

  /// Compile all tracks into a single MusicPattern.
  func compile(engine: SpatialAudioEngine, clock: any Clock<Duration> = ContinuousClock(), resourceBaseURL: URL? = nil) async throws -> CompileResult {
    if let midi = midiTracks {
      return try await compileMidiTracks(midi, engine: engine, clock: clock, resourceBaseURL: resourceBaseURL)
    } else if let table = tableTracks {
      return try await TablePatternCompiler.compile(table, engine: engine, clock: clock, resourceBaseURL: resourceBaseURL)
    } else if let score = scoreTracks {
      return try await ScorePatternCompiler.compile(score, engine: engine, clock: clock, resourceBaseURL: resourceBaseURL)
    } else if let gen = generatorTracks {
      let score = GeneratorEngine.generate(gen)
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
        let presetSpec = resolvePresetSpec(filename: entry.presetFilename, resourceBaseURL: resourceBaseURL)
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
    resourceBaseURL: URL? = nil
  ) async throws -> CompileResult {
    guard let url = NoteGeneratorSyntax.midiFileURL(filename: midi.filename, resourceBaseURL: resourceBaseURL) else {
      fatalError("MIDI file not found: \(midi.filename)")
    }

    let loopVal = midi.loop ?? true
    let allSeqs = MidiEventSequence.allTracks(url: url, loop: loopVal, bpmOverride: midi.bpm)

    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []
    var spatialPresets: [SpatialPreset] = []

    for (i, entry) in allSeqs.enumerated() {
      let trackEntry = i < midi.tracks.count ? midi.tracks[i] : midi.tracks[0]
      let presetSpec = resolvePresetSpec(filename: trackEntry.presetFilename, resourceBaseURL: resourceBaseURL)
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

// MARK: - Random pad helpers

/// Generates a fresh random pad preset using standard oscillators.
/// Called when presetFilename is nil or "randomPad" in a pattern track.
func makeRandomPadPreset() -> PresetSyntax {
  let shapes: [BasicOscillator.OscShape] = [.sine, .triangle, .sawtooth, .square]
  let sliders = PadSliders(
    smooth: .random(in: 0...1),
    bite: .random(in: 0...1),
    motion: .random(in: 0...1),
    width: .random(in: 0...1),
    grit: .random(in: 0...0.3)
  )
  let template = PadTemplateSyntax(
    name: "Random Pad",
    oscillators: [
      PadOscDescriptor(kind: .standard, shape: shapes.randomElement()!, file: nil,
                       detuneCents: .random(in: -12...12), octave: 0),
      PadOscDescriptor(kind: .standard, shape: shapes.randomElement()!, file: nil,
                       detuneCents: .random(in: -12...12), octave: [-1, 0, 1].randomElement()!)
    ],
    crossfade: [.noiseSmoothStep, .lfo].randomElement()!,
    crossfadeRate: nil,
    vibratoEnabled: Bool.random(),
    vibratoRate: nil,
    vibratoDepth: .random(in: 0.0001...0.001),
    ampAttack: nil, ampDecay: 0.1, ampSustain: 1.0, ampRelease: nil,
    filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
    filterEnvAttack: .random(in: 0.02...0.2),
    filterEnvDecay: .random(in: 0.2...0.8),
    filterEnvSustain: .random(in: 0.5...0.95),
    filterEnvRelease: .random(in: 0.2...0.8),
    filterCutoffLow: .random(in: 50...120),
    mood: .custom, sliders: sliders
  )
  return PresetSyntax(
    name: "Random Pad",
    arrow: nil, samplerFilenames: nil, samplerProgram: nil, samplerBank: nil, library: nil,
    rose: RoseSyntax(amp: 0, leafFactor: 3, freq: 0.2, phase: 0),
    effects: EffectsSyntax(reverbPreset: 4, reverbWetDryMix: 30,
                           delayTime: 0, delayFeedback: 0, delayLowPassCutoff: 0, delayWetDryMix: 0),
    padTemplate: template
  )
}

/// Resolves a preset filename to a PresetSyntax.
/// nil or "randomPad" → fresh random pad preset; any other string → load from the presets bundle directory.
func resolvePresetSpec(filename: String?, resourceBaseURL: URL?) -> PresetSyntax {
  guard let filename, filename != "randomPad" else {
    return makeRandomPadPreset()
  }
  return decodeJSON(PresetSyntax.self, from: filename + ".json", subdirectory: "presets", resourceBaseURL: resourceBaseURL)
}
