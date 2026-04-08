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
struct MidiTracksSyntax: Codable {
  let filename: String
  let loop: Bool?
  let bpm: Double?
  /// Maximum silence (seconds) between notes. Gaps exceeding this are
  /// compressed so dead air never lasts longer than this value.
  /// nil disables compression (preserves original timing).
  let maxSilence: Double?
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
    resourceBaseURL: URL? = nil
  ) async throws -> CompileResult {
    guard let url = NoteGeneratorSyntax.midiFileURL(filename: midi.filename, resourceBaseURL: resourceBaseURL) else {
      throw PatternCompileError.midiFileNotFound(midi.filename)
    }

    let loopVal = midi.loop ?? true
    let rawSeqs = MidiEventSequence.allTracks(url: url, loop: loopVal, bpmOverride: midi.bpm)

    let allSeqs: [(trackIndex: Int, trackName: String, sequence: MidiEventSequence)]
    if let maxSilence = midi.maxSilence {
      let rawSequences = rawSeqs.map(\.sequence)
      let compressed = MidiEventSequence.compressingSilencesGlobally(rawSequences, maxSilence: CoreFloat(maxSilence))
      allSeqs = zip(rawSeqs, compressed).map { ($0.0.trackIndex, $0.0.trackName, $0.1) }
    } else {
      allSeqs = rawSeqs
    }

    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []
    var spatialPresets: [SpatialPreset] = []

    // When fewer track entries are defined than MIDI tracks, the last entry is reused for the
    // remaining tracks. In that case, reduce voices so a single-entry spec applied to many
    // MIDI tracks doesn't overwhelm the audio engine.
    let isFallbackMode = !midi.tracks.isEmpty && allSeqs.count > midi.tracks.count
    for (i, entry) in allSeqs.enumerated() {
      let trackEntry = i < midi.tracks.count ? midi.tracks[i] : midi.tracks[0]
      let presetSpec = resolvePresetSpec(filename: trackEntry.presetFilename, gmProgram: entry.sequence.program, characteristicDuration: entry.sequence.medianSustain(), resourceBaseURL: resourceBaseURL)
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

/// Timbral constraints for generating a random pad from a GM instrument family.
/// All ranges are used to pick a random value within the family's characteristic space.
private struct GMPadProfile {
  let shapes: [BasicOscillator.OscShape]  // oscillator shapes appropriate for this family
  let wavetableNames: [String]            // built-in WavetableLibrary table names for this family
  let smoothRange: ClosedRange<CoreFloat>  // controls amp attack/release via lerp(0.5, 8.0, smooth)
  let filterCutoffRange: ClosedRange<CoreFloat>  // filterCutoffLow: brightness floor
  let gritRange: ClosedRange<CoreFloat>
  let vibratoWeight: Double  // probability of enabling vibrato (0–1)
}

private func gmPadProfile(for program: Int?) -> GMPadProfile {
  guard let program else { return .default }
  switch program {
  case 0...7:   return .piano
  case 8...15:  return .chromPerc
  case 16...23: return .organ
  case 24...31: return .guitar
  case 32...39: return .bass
  case 40...47: return .strings
  case 48...55: return .ensemble
  case 56...63: return .brass
  case 64...71: return .reed
  case 72...79: return .pipe
  case 80...87: return .synthLead
  case 88...95: return .synthPad
  default:      return .default
  }
}

private extension GMPadProfile {
  // Slower attack = higher smooth value (smooth drives lerp(0.5, 8.0, smooth) for ampAttack)
  // swiftlint:disable line_length comma
  static let `default` = GMPadProfile(shapes: [.sine, .triangle, .sawtooth, .square], wavetableNames: ["fm_bell", "fm_electric", "fm_metallic", "fm_shallow", "fm_deep", "bright", "warm", "organ", "hollow"], smoothRange: 0.2...0.8,  filterCutoffRange: 60...140,  gritRange: 0.0...0.2,  vibratoWeight: 0.4)
  static let piano     = GMPadProfile(shapes: [.triangle, .square],                   wavetableNames: ["fm_electric", "fm_shallow", "bright", "warm"],                                                         smoothRange: 0.15...0.45, filterCutoffRange: 80...200,  gritRange: 0.0...0.15, vibratoWeight: 0.1)
  static let chromPerc = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["fm_bell", "fm_metallic", "bright"],                                                                    smoothRange: 0.2...0.5,   filterCutoffRange: 100...300, gritRange: 0.0...0.08, vibratoWeight: 0.0)
  static let organ     = GMPadProfile(shapes: [.square, .sawtooth],                   wavetableNames: ["organ", "hollow", "bright"],                                                                           smoothRange: 0.0...0.25,  filterCutoffRange: 60...150,  gritRange: 0.0...0.1,  vibratoWeight: 0.5)
  static let guitar    = GMPadProfile(shapes: [.triangle, .sawtooth],                 wavetableNames: ["fm_shallow", "warm", "bright"],                                                                        smoothRange: 0.15...0.45, filterCutoffRange: 60...150,  gritRange: 0.0...0.2,  vibratoWeight: 0.25)
  static let bass      = GMPadProfile(shapes: [.sawtooth, .square],                   wavetableNames: ["fm_deep", "warm"],                                                                                    smoothRange: 0.1...0.35,  filterCutoffRange: 40...100,  gritRange: 0.0...0.2,  vibratoWeight: 0.1)
  static let strings   = GMPadProfile(shapes: [.sawtooth, .triangle],                 wavetableNames: ["warm", "hollow", "fm_shallow"],                                                                        smoothRange: 0.4...0.85,  filterCutoffRange: 60...140,  gritRange: 0.0...0.08, vibratoWeight: 0.75)
  static let ensemble  = GMPadProfile(shapes: [.triangle, .sine],                     wavetableNames: ["warm", "hollow", "bright"],                                                                            smoothRange: 0.5...0.9,   filterCutoffRange: 55...120,  gritRange: 0.0...0.05, vibratoWeight: 0.6)
  static let brass     = GMPadProfile(shapes: [.sawtooth, .square],                   wavetableNames: ["bright", "fm_deep", "fm_metallic"],                                                                    smoothRange: 0.2...0.55,  filterCutoffRange: 80...200,  gritRange: 0.0...0.2,  vibratoWeight: 0.3)
  static let reed      = GMPadProfile(shapes: [.square, .triangle],                   wavetableNames: ["hollow", "warm", "fm_shallow"],                                                                        smoothRange: 0.2...0.5,   filterCutoffRange: 70...180,  gritRange: 0.0...0.1,  vibratoWeight: 0.35)
  static let pipe      = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["hollow", "fm_shallow", "bright"],                                                                      smoothRange: 0.2...0.5,   filterCutoffRange: 80...200,  gritRange: 0.0...0.05, vibratoWeight: 0.3)
  static let synthLead = GMPadProfile(shapes: [.sine, .triangle, .sawtooth, .square], wavetableNames: ["fm_bell", "fm_electric", "fm_metallic", "fm_shallow", "fm_deep", "bright", "hollow"],                 smoothRange: 0.1...0.5,   filterCutoffRange: 60...200,  gritRange: 0.0...0.3,  vibratoWeight: 0.4)
  static let synthPad  = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["warm", "hollow", "fm_shallow", "fm_deep", "fm_bell"],                                                 smoothRange: 0.6...1.0,   filterCutoffRange: 50...110,  gritRange: 0.0...0.05, vibratoWeight: 0.6)
  // swiftlint:enable line_length comma
}

/// Picks a random oscillator descriptor appropriate for the given profile.
/// 50% chance of a standard shape from the profile; 50% chance of a wavetable (profile built-ins
/// + any curated tables pre-loaded into WavetableLibrary.userTables).
private func randomOscDescriptor(profile: GMPadProfile, octave: CoreFloat) -> PadOscDescriptor {
  let wavetablePool = profile.wavetableNames + WavetableLibrary.curatedTableNames
  if !wavetablePool.isEmpty && Bool.random() {
    return PadOscDescriptor(kind: .wavetable, shape: nil, file: wavetablePool.randomElement()!,
                            detuneCents: .random(in: -12...12), octave: octave)
  }
  return PadOscDescriptor(kind: .standard, shape: profile.shapes.randomElement()!, file: nil,
                          detuneCents: .random(in: -12...12), octave: octave)
}

/// Generates a fresh random pad preset, constrained to the timbre space of the given GM program.
/// When characteristicDuration is provided (median note sustain in seconds), ampAttack and
/// ampRelease are derived from it so short-note tracks feel snappy and long-note tracks bloom slowly.
func makeRandomPadPreset(gmProgram: Int? = nil, characteristicDuration: CoreFloat? = nil) -> PresetSyntax {
  let profile = gmPadProfile(for: gmProgram)
  let sliders = PadSliders(
    smooth: .random(in: profile.smoothRange),
    bite: .random(in: 0...1),
    motion: .random(in: 0...1),
    width: .random(in: 0...1),
    grit: .random(in: profile.gritRange)
  )
  // Derive amp envelope from median note duration when available.
  // attack ≈ 20% of median sustain (50 ms – 4 s); release ≈ 30% (100 ms – 5 s).
  let ampAttack: CoreFloat? = characteristicDuration.map { clamp($0 * 0.2, min: 0.05, max: 4.0) }
  let ampRelease: CoreFloat? = characteristicDuration.map { clamp($0 * 0.3, min: 0.10, max: 5.0) }
  let template = PadTemplateSyntax(
    name: "Random Pad",
    oscillators: [
      randomOscDescriptor(profile: profile, octave: 0),
      randomOscDescriptor(profile: profile, octave: [-1, 0, 1].randomElement()!)
    ],
    crossfade: [.noiseSmoothStep, .lfo].randomElement()!,
    crossfadeRate: nil,
    vibratoEnabled: Double.random(in: 0...1) < profile.vibratoWeight,
    vibratoRate: nil,
    vibratoDepth: .random(in: 0.0001...0.001),
    ampAttack: ampAttack, ampDecay: 0.1, ampSustain: 1.0, ampRelease: ampRelease,
    filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
    filterEnvAttack: .random(in: 0.02...0.2),
    filterEnvDecay: .random(in: 0.2...0.8),
    filterEnvSustain: .random(in: 0.5...0.95),
    filterEnvRelease: .random(in: 0.2...0.8),
    filterCutoffLow: .random(in: profile.filterCutoffRange),
    mood: .custom, sliders: sliders
  )
  return PresetSyntax(
    name: "Random Pad",
    arrow: nil, samplerFilenames: nil, samplerProgram: nil, samplerBank: nil, library: nil,
    rose: RoseSyntax(amp: 0, leafFactor: 3, freq: 0.2, phase: 0),
    effects: EffectsSyntax(reverbPreset: 4, reverbWetDryMix: 100,
                           delayTime: 0, delayFeedback: 0, delayLowPassCutoff: 0, delayWetDryMix: 0),
    padTemplate: template,
    padSynth: nil
  )
}

/// Resolves a preset filename to a PresetSyntax.
/// nil or "randomPad" → fresh random pad preset; any other string → load from the presets bundle directory.
func resolvePresetSpec(filename: String?, gmProgram: Int? = nil, characteristicDuration: CoreFloat? = nil, resourceBaseURL: URL?) -> PresetSyntax {
  guard let filename, filename != "randomPad" else {
    return makeRandomPadPreset(gmProgram: gmProgram, characteristicDuration: characteristicDuration)
  }
  return decodeJSON(PresetSyntax.self, from: filename + ".json", subdirectory: "presets", resourceBaseURL: resourceBaseURL)
}
