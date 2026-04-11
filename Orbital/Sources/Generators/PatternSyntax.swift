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
///
/// `@unchecked Sendable`: PatternSyntax and its constituent *Syntax types are
/// immutable Codable value types (all fields are `let`). They are safely
/// shared across isolation domains (main actor UI → nonisolated compile).
/// The underlying structs aren't marked Sendable individually to avoid a
/// cascade through every syntax type; we assert the promise at this boundary.
struct PatternSyntax: Codable, @unchecked Sendable {
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

// MARK: - Random pad helpers

/// Hard tightening rules a GM profile may impose on the random pad generator.
/// Flag cases override randomization; parametric cases supply a clamp value.
private enum PadConstraint {
  case noDetune
  case subOctaveSine
  case noVibrato
  case noFilterLFO
  case noCrossfadeLFO
  case noSpatialMotion
  case ampAttackCeiling(CoreFloat)
  case filterCutoffMaxMultiplier(CoreFloat)
}

private extension Array where Element == PadConstraint {
  var requiresSubOctaveSine: Bool {
    contains { if case .subOctaveSine = $0 { return true } else { return false } }
  }
  var forbidsDetune: Bool {
    contains { if case .noDetune = $0 { return true } else { return false } }
  }
  var forbidsVibrato: Bool {
    contains { if case .noVibrato = $0 { return true } else { return false } }
  }
  var forbidsFilterLFO: Bool {
    contains { if case .noFilterLFO = $0 { return true } else { return false } }
  }
  var forbidsCrossfadeLFO: Bool {
    contains { if case .noCrossfadeLFO = $0 { return true } else { return false } }
  }
  var forbidsSpatialMotion: Bool {
    contains { if case .noSpatialMotion = $0 { return true } else { return false } }
  }
  var ampAttackCeiling: CoreFloat? {
    for c in self { if case .ampAttackCeiling(let v) = c { return v } }
    return nil
  }
  var filterCutoffMaxMultiplier: CoreFloat? {
    for c in self { if case .filterCutoffMaxMultiplier(let v) = c { return v } }
    return nil
  }
}

/// Timbral constraints for generating a random pad from a GM instrument family.
/// All ranges are used to pick a random value within the family's characteristic space.
private struct GMPadProfile {
  let shapes: [BasicOscillator.OscShape]  // oscillator shapes appropriate for this family
  let wavetableNames: [String]            // built-in WavetableLibrary table names for this family
  let smoothRange: ClosedRange<CoreFloat>  // controls amp attack/release via lerp(0.5, 8.0, smooth)
  let filterCutoffRange: ClosedRange<CoreFloat>  // filterCutoffLow: brightness floor
  let gritRange: ClosedRange<CoreFloat>
  let vibratoWeight: Double  // probability of enabling vibrato (0–1)
  let constraints: [PadConstraint]
}

private func gmPadProfileName(for program: Int?) -> String {
  guard let program else { return "default" }
  switch program {
  case 0...7:   return "piano"
  case 8...15:  return "chromPerc"
  case 16...23: return "organ"
  case 24...31: return "guitar"
  case 32...39: return "bass"
  case 40...47: return "strings"
  case 48...55: return "ensemble"
  case 56...63: return "brass"
  case 64...71: return "reed"
  case 72...79: return "pipe"
  case 80...87: return "synthLead"
  case 88...95: return "synthPad"
  default:      return "default"
  }
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
  static let `default` = GMPadProfile(shapes: [.sine, .triangle, .sawtooth, .square], wavetableNames: ["fm_bell", "fm_electric", "fm_metallic", "fm_shallow", "fm_deep", "bright", "warm", "organ", "hollow"], smoothRange: 0.2...0.8,  filterCutoffRange: 60...140,  gritRange: 0.0...0.0,  vibratoWeight: 0.4,  constraints: [])
  static let piano     = GMPadProfile(shapes: [.triangle, .square],                   wavetableNames: ["fm_electric", "fm_shallow", "bright", "warm"],                                                         smoothRange: 0.15...0.45, filterCutoffRange: 80...200,  gritRange: 0.0...0.0,  vibratoWeight: 0.1,  constraints: [])
  static let chromPerc = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["fm_bell", "fm_metallic", "bright"],                                                                    smoothRange: 0.2...0.5,   filterCutoffRange: 100...300, gritRange: 0.0...0.0,  vibratoWeight: 0.0,  constraints: [])
  static let organ     = GMPadProfile(shapes: [.square, .sawtooth],                   wavetableNames: ["organ", "hollow", "bright"],                                                                           smoothRange: 0.0...0.25,  filterCutoffRange: 60...150,  gritRange: 0.0...0.0,  vibratoWeight: 0.5,  constraints: [])
  static let guitar    = GMPadProfile(shapes: [.triangle, .sawtooth],                 wavetableNames: ["fm_shallow", "warm", "bright"],                                                                        smoothRange: 0.15...0.45, filterCutoffRange: 60...150,  gritRange: 0.0...0.0,  vibratoWeight: 0.25, constraints: [])
  static let bass      = GMPadProfile(
    shapes: [.sawtooth, .square],
    wavetableNames: ["fm_deep", "warm"],
    smoothRange: 0.1...0.35,
    filterCutoffRange: 50...80,
    gritRange: 0.0...0.0,
    vibratoWeight: 0.0,
    constraints: [
      .subOctaveSine,
      .noDetune,
      .noVibrato,
      .noFilterLFO,
      .noCrossfadeLFO,
      .noSpatialMotion,
      .ampAttackCeiling(0.030),
      .filterCutoffMaxMultiplier(16.0)
    ]
  )
  static let strings   = GMPadProfile(shapes: [.sawtooth, .triangle],                 wavetableNames: ["warm", "hollow", "fm_shallow"],                                                                        smoothRange: 0.4...0.85,  filterCutoffRange: 60...140,  gritRange: 0.0...0.0,  vibratoWeight: 0.75, constraints: [])
  static let ensemble  = GMPadProfile(shapes: [.triangle, .sine],                     wavetableNames: ["warm", "hollow", "bright"],                                                                            smoothRange: 0.5...0.9,   filterCutoffRange: 55...120,  gritRange: 0.0...0.0,  vibratoWeight: 0.6,  constraints: [])
  static let brass     = GMPadProfile(shapes: [.sawtooth, .square],                   wavetableNames: ["bright", "fm_deep", "fm_metallic"],                                                                    smoothRange: 0.2...0.55,  filterCutoffRange: 80...200,  gritRange: 0.0...0.0,  vibratoWeight: 0.3,  constraints: [])
  static let reed      = GMPadProfile(shapes: [.square, .triangle],                   wavetableNames: ["hollow", "warm", "fm_shallow"],                                                                        smoothRange: 0.2...0.5,   filterCutoffRange: 70...180,  gritRange: 0.0...0.0,  vibratoWeight: 0.35, constraints: [])
  static let pipe      = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["hollow", "fm_shallow", "bright"],                                                                      smoothRange: 0.2...0.5,   filterCutoffRange: 80...200,  gritRange: 0.0...0.0,  vibratoWeight: 0.3,  constraints: [])
  static let synthLead = GMPadProfile(shapes: [.sine, .triangle, .sawtooth, .square], wavetableNames: ["fm_bell", "fm_electric", "fm_metallic", "fm_shallow", "fm_deep", "bright", "hollow"],                 smoothRange: 0.1...0.5,   filterCutoffRange: 60...200,  gritRange: 0.0...0.0,  vibratoWeight: 0.4,  constraints: [])
  static let synthPad  = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["warm", "hollow", "fm_shallow", "fm_deep", "fm_bell"],                                                 smoothRange: 0.6...1.0,   filterCutoffRange: 50...110,  gritRange: 0.0...0.0,  vibratoWeight: 0.6,  constraints: [])
  // swiftlint:enable line_length comma
}

// MARK: - GM → SHARC instrument mapping

// swiftlint:disable colon
private let gmSharcInstruments: [ClosedRange<Int>: [String]] = [
  0...7:   ["amy_piano_steinway"],
  8...15:  ["amy_piano_steinway"],
  16...23: ["amy_piano_steinway"],
  24...31: ["amy_piano_steinway"],
  32...39: ["CB", "CB_martele", "CB_muted", "contrabassoon"],
  40...47: ["violin_vibrato", "violin_martele", "viola_vibrato", "viola_martele",
            "cello_vibrato", "cello_martele", "CB", "violinensemb"],
  48...55: ["violinensemb", "vowel_aah", "vowel_ah", "vowel_ooh", "vowel_ee"],
  56...63: ["French_horn", "French_horn_muted", "C_trumpet", "C_trumpet_muted",
            "Bach_trumpet", "trombone", "trombone_muted", "tuba", "alto_trombone", "bass_trombone"],
  64...71: ["Bb_clarinet", "bass_clarinet", "Eb_clarinet", "contrabass_clarinet",
            "oboe", "English_horn", "bassoon", "contrabassoon"],
  72...79: ["flute_vibrato", "altoflute_vibrato", "bassflute_vibrato", "piccolo",
            "oboe", "English_horn"],
  80...87: ["Bb_clarinet", "C_trumpet", "violin_vibrato", "flute_vibrato"],
  88...95: ["violin_vibrato", "cello_vibrato", "flute_vibrato", "French_horn",
            "vowel_aah", "vowel_ooh"]
]
// swiftlint:enable colon

/// All SHARC instrument IDs, used when no GM program is specified.
private let allSharcInstruments: [String] = SharcDatabase.shared.instruments.map(\.id)

/// Picks a random SHARC instrument ID appropriate for the given GM program.
private func randomSharcInstrument(for gmProgram: Int?) -> String {
  if let gm = gmProgram {
    for (range, instruments) in gmSharcInstruments where range.contains(gm) {
      return SongRNG.pick(instruments) ?? instruments[0]
    }
  }
  return SongRNG.pick(allSharcInstruments) ?? allSharcInstruments[0]
}

/// Builds a padSynth oscillator descriptor with a SHARC instrument and default PADsynth params.
private func randomPadSynthOscDescriptor(gmProgram: Int?, octave: CoreFloat,
                                         forbidDetune: Bool = false) -> PadOscDescriptor {
  let instrument = randomSharcInstrument(for: gmProgram)
  let params = PADSynthSyntax(
    baseShape: .oneOverNSquared, tilt: 0, bandwidthCents: 50, bwScale: 1,
    profileShape: .gaussian, stretch: 1, selectedInstrument: instrument, envelopeCoefficients: nil
  )
  let detune: CoreFloat = forbidDetune ? 0 : SongRNG.float(in: -12...12)
  return PadOscDescriptor(kind: .padSynth, shape: nil, file: nil, padSynthParams: params,
                          detuneCents: detune, octave: octave)
}

/// Picks a random basic oscillator descriptor from the profile's standard shapes.
private func randomOscDescriptor(profile: GMPadProfile, octave: CoreFloat,
                                 forbidDetune: Bool = false) -> PadOscDescriptor {
  let detune: CoreFloat = forbidDetune ? 0 : SongRNG.float(in: -12...12)
  return PadOscDescriptor(kind: .standard, shape: SongRNG.pick(profile.shapes) ?? .sine, file: nil,
                          padSynthParams: nil, detuneCents: detune, octave: octave)
}

/// Returns a comparable identity for an oscillator: kind + shape or file name.
/// Two oscillators with the same identity sound redundant regardless of detune/octave.
private func oscIdentity(_ osc: PadOscDescriptor) -> String {
  switch osc.kind {
  case .standard:  return "std:\(osc.shape.map { "\($0)" } ?? "sine")"
  case .wavetable: return "wt:\(osc.file ?? "")"
  case .padSynth:  return "pad:\(osc.padSynthParams?.selectedInstrument ?? "formula")"
  }
}

private let auditionCounter = PersistentCounter(key: "randomPadAuditionCounter")

private final class PersistentCounter: Sendable {
  private let key: String
  private let lock = NSLock()
  init(key: String) { self.key = key }
  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    let current = UserDefaults.standard.integer(forKey: key)
    let next = current + 1
    UserDefaults.standard.set(next, forKey: key)
    return next
  }
}

private func saveRandomPadAudition(_ preset: PresetSyntax) -> (Int, String) {
  let n = auditionCounter.next()
  let filename = "random_audition_\(n).json"
  // Compile the padTemplate into an arrow so the JSON contains the full DSP graph
  // (including the filter chain), matching the format of hand-authored presets.
  let resolvedArrow: ArrowSyntax? = preset.padTemplate.map { PadTemplateCompiler.compile($0) }
  let resolved = PresetSyntax(
    name: "Random Audition \(n)",
    arrow: resolvedArrow ?? preset.arrow,
    samplerFilenames: preset.samplerFilenames,
    samplerProgram: preset.samplerProgram,
    samplerBank: preset.samplerBank,
    library: preset.library,
    rose: preset.rose,
    effects: preset.effects,
    padTemplate: nil,
    padSynth: preset.padSynth
  )
  Task { @MainActor in
    if PresetStorage.save(resolved, filename: filename) {
      print("  Saved audition preset: \(filename)")
    } else {
      print("  Failed to save audition preset: \(filename)")
    }
  }
  return (n, filename)
}

private func printRandomPadDiagnostic(gmProgram: Int?, characteristicDuration: CoreFloat?,
                                      template: PadTemplateSyntax, sliders: PadSliders, rose: RoseSyntax) {
  func oscDesc(_ osc: PadOscDescriptor) -> String {
    switch osc.kind {
    case .standard:
      let shape = osc.shape.map { "\($0)" } ?? "sine"
      return "\(shape) oct=\(osc.octave ?? 0) detune=\(osc.detuneCents ?? 0)¢"
    case .wavetable:
      return "wt(\(osc.file ?? "?")) oct=\(osc.octave ?? 0) detune=\(osc.detuneCents ?? 0)¢"
    case .padSynth:
      let inst = osc.padSynthParams?.selectedInstrument ?? "formula"
      return "padSynth(\(inst)) oct=\(osc.octave ?? 0) detune=\(osc.detuneCents ?? 0)¢"
    }
  }
  let profileName = gmPadProfileName(for: gmProgram)
  let gmStr = gmProgram.map { "\($0)" } ?? "nil"
  let durStr = characteristicDuration.map { String(format: "%.2f s", $0) } ?? "nil"
  let atkStr = template.ampAttack.map { String(format: "%.3f", $0) } ?? "slider"
  let relStr = template.ampRelease.map { String(format: "%.3f", $0) } ?? "slider"
  print("""
    ┌─ Random Pad ──────────────────────────────
    │ profile: \(profileName)  (GM \(gmStr), duration \(durStr))
    │ osc1: \(oscDesc(template.oscillators[0]))
    │ osc2: \(oscDesc(template.oscillators[1]))
    │ crossfade: \(template.crossfade)  rate=\(template.crossfadeRate.map { String(format: "%.4f", $0) } ?? "slider") Hz
    │ vibrato: \(template.vibratoEnabled ? "on" : "off")  depth=\(template.vibratoDepth)
    │ filter LFO: \(template.filterLFORate.map { String(format: "%.4f", $0) } ?? "off") Hz
    │ sliders: smooth=\(sliders.smooth)  bite=\(sliders.bite)  motion=\(sliders.motion)  width=\(sliders.width)  grit=\(sliders.grit)
    │ amp env: atk=\(atkStr)  dec=\(template.ampDecay)  sus=\(template.ampSustain)  rel=\(relStr)
    │ filt env: atk=\(template.filterEnvAttack)  dec=\(template.filterEnvDecay)  sus=\(template.filterEnvSustain)  rel=\(template.filterEnvRelease)
    │ filt cutoff low: \(template.filterCutoffLow) Hz
    │ rose: amp=\(String(format: "%.2f", rose.amp))  freq=\(String(format: "%.4f", rose.freq)) Hz  k=\(Int(rose.leafFactor))
    └───────────────────────────────────────────
    """)
}

// swiftlint:disable function_body_length
/// Generates a fresh random pad preset, constrained to the timbre space of the given GM program.
/// When characteristicDuration is provided (median note sustain in seconds), ampAttack and
/// ampRelease are derived from it so short-note tracks feel snappy and long-note tracks bloom slowly.
func makeRandomPadPreset(gmProgram: Int? = nil, characteristicDuration: CoreFloat? = nil) -> PresetSyntax {
  let profile = gmPadProfile(for: gmProgram)
  let constraints = profile.constraints
  let sliders = PadSliders(
    smooth: SongRNG.float(in: profile.smoothRange),
    bite: SongRNG.float(in: 0...1),
    motion: 0,
    width: SongRNG.float(in: 0...1),
    grit: SongRNG.float(in: profile.gritRange)
  )
  // Derive amp envelope from median note duration when available.
  // attack ≈ 20% of median sustain (50 ms – 4 s); release ≈ 30% (100 ms – 5 s).
  // .ampAttackCeiling clamps the result for profiles that need a fast edge.
  var ampAttack: CoreFloat? = characteristicDuration.map { clamp($0 * 0.2, min: 0.05, max: 4.0) }
  if let ceiling = constraints.ampAttackCeiling {
    ampAttack = Swift.min(ampAttack ?? ceiling, ceiling)
  }
  let ampRelease: CoreFloat? = characteristicDuration.map { clamp($0 * 0.3, min: 0.10, max: 5.0) }

  // Osc 1: padSynth (SHARC). Always present.
  let osc1 = randomPadSynthOscDescriptor(
    gmProgram: gmProgram,
    octave: 0,
    forbidDetune: constraints.forbidsDetune
  )

  // Osc 2: forced sub-octave sine, or random standard oscillator.
  let osc2: PadOscDescriptor
  if constraints.requiresSubOctaveSine {
    osc2 = PadOscDescriptor(
      kind: .standard, shape: .sine, file: nil, padSynthParams: nil,
      detuneCents: 0, octave: -1
    )
  } else {
    let osc2Octave: CoreFloat = SongRNG.pick([-1, 0, 1] as [CoreFloat]) ?? 0
    osc2 = randomOscDescriptor(
      profile: profile, octave: osc2Octave,
      forbidDetune: constraints.forbidsDetune
    )
  }

  // Crossfade: hard-disabled or LFO.
  let crossfade: PadCrossfadeKind
  let crossfadeRate: CoreFloat?
  if constraints.forbidsCrossfadeLFO {
    crossfade = .static
    crossfadeRate = nil
  } else {
    crossfade = .lfo
    crossfadeRate = FloatSampler(min: 0.01, max: 0.1, dist: .exponential).next()
  }

  // Vibrato: hard-disabled or sampled by vibratoWeight (was previously hardcoded true).
  let vibratoEnabled: Bool
  if constraints.forbidsVibrato {
    vibratoEnabled = false
  } else {
    vibratoEnabled = Double.random(in: 0...1, using: &SongRNG.box.rng) < profile.vibratoWeight
  }

  // Filter LFO: hard-disabled or sampled.
  let filterLFORate: CoreFloat? =
    constraints.forbidsFilterLFO
      ? nil
      : FloatSampler(min: 0.02, max: 0.2, dist: .exponential).next()

  let template = PadTemplateSyntax(
    name: "Random Pad",
    oscillators: [osc1, osc2],
    crossfade: crossfade,
    crossfadeRate: crossfadeRate,
    vibratoEnabled: vibratoEnabled,
    vibratoRate: FloatSampler(min: 1.0, max: 6.0, dist: .exponential).next()!,
    vibratoDepth: FloatSampler(min: 0.0001, max: 0.001, dist: .exponential).next()!,
    ampAttack: ampAttack, ampDecay: 0.1, ampSustain: 1.0, ampRelease: ampRelease,
    filterCutoffMultiplier: constraints.filterCutoffMaxMultiplier, filterResonance: nil,
    filterLFORate: filterLFORate,
    filterEnvAttack: SongRNG.float(in: 0.02...0.2),
    filterEnvDecay: SongRNG.float(in: 0.2...0.8),
    filterEnvSustain: SongRNG.float(in: 0.5...0.95),
    filterEnvRelease: SongRNG.float(in: 0.2...0.8),
    filterCutoffLow: SongRNG.float(in: profile.filterCutoffRange),
    mood: .custom, sliders: sliders
  )
  let effects = EffectsSyntax(reverbPreset: 8, reverbWetDryMix: 50,
                              delayTime: 0, delayFeedback: 0, delayLowPassCutoff: 0, delayWetDryMix: 0)
  let leafFactorPick: Int = SongRNG.pick([2, 3, 5, 7]) ?? 3
  let roseAmp: CoreFloat =
    constraints.forbidsSpatialMotion
      ? 0
      : FloatSampler(min: 0.5, max: 5.0, dist: .exponential).next()!
  let rose = RoseSyntax(
    amp: roseAmp,
    leafFactor: CoreFloat(leafFactorPick),
    freq: FloatSampler(min: 0.01, max: 0.1, dist: .exponential).next()!,
    phase: SongRNG.float(in: 0...(CoreFloat.pi * 2))
  )
  printRandomPadDiagnostic(gmProgram: gmProgram, characteristicDuration: characteristicDuration,
                           template: template, sliders: sliders, rose: rose)
  return PresetSyntax(
    name: "Random Pad",
    arrow: nil, samplerFilenames: nil, samplerProgram: nil, samplerBank: nil, library: nil,
    rose: rose, effects: effects, padTemplate: template, padSynth: nil
  )
}
// swiftlint:enable function_body_length

/// Resolves a preset filename to a PresetSyntax.
/// nil or "randomPad" → fresh random pad preset; any other string → load from the presets bundle directory.
func resolvePresetSpec(filename: String?, gmProgram: Int? = nil, characteristicDuration: CoreFloat? = nil, resourceBaseURL: URL?) -> PresetSyntax {
  guard let filename, filename != "randomPad" else {
    return makeRandomPadPreset(gmProgram: gmProgram, characteristicDuration: characteristicDuration)
  }
  return decodeJSON(PresetSyntax.self, from: filename + ".json", subdirectory: "presets", resourceBaseURL: resourceBaseURL)
}
