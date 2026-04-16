//
//  RandomPadPreset.swift
//  Orbital
//
//  Random pad preset generation, constrained by General MIDI program profiles.
//  makeRandomPadPreset() -> PresetSyntax
//

import Foundation

// MARK: - PadConstraint

/// Hard tightening rules a GM profile may impose on the random pad generator.
/// Flag cases override randomization; parametric cases supply a clamp or
/// fixed value. Ceiling/Max cases clamp a sampled value; the plain "value"
/// cases force it outright (ignoring any random sample or derivation).
private enum PadConstraint {
  case noDetune
  case subOctaveSine
  case noVibrato
  case noFilterLFO
  case noCrossfadeLFO
  case noSpatialMotion
  case ampAttackCeiling(CoreFloat)
  case filterCutoffMaxMultiplier(CoreFloat)
  case ampAttackValue(CoreFloat)
  case ampDecayValue(CoreFloat)
  case ampSustainValue(CoreFloat)
  case chorus(cents: Int, voices: Int)
  case padSynthStretch(CoreFloat)
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
  var ampAttackValue: CoreFloat? {
    for c in self { if case .ampAttackValue(let v) = c { return v } }
    return nil
  }
  var ampDecayValue: CoreFloat? {
    for c in self { if case .ampDecayValue(let v) = c { return v } }
    return nil
  }
  var ampSustainValue: CoreFloat? {
    for c in self { if case .ampSustainValue(let v) = c { return v } }
    return nil
  }
  var chorusOverride: (cents: Int, voices: Int)? {
    for c in self { if case .chorus(let cents, let voices) = c { return (cents, voices) } }
    return nil
  }
  var padSynthStretch: CoreFloat? {
    for c in self { if case .padSynthStretch(let v) = c { return v } }
    return nil
  }
}

// MARK: - GMPadProfile

/// Timbral constraints for generating a random pad from a GM instrument family.
/// All ranges are used to pick a random value within the family's characteristic space.
private struct GMPadProfile {
  let shapes: [BasicOscillator.OscShape]  // oscillator shapes appropriate for this family
  let wavetableNames: [String]            // built-in WavetableLibrary table names for this family
  let ampAttackRange: ClosedRange<CoreFloat>  // amp attack in seconds (fallback when characteristicDuration is nil)
  let filterCutoffRange: ClosedRange<CoreFloat>  // filterCutoffLow: brightness floor
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
  /// Opt-in constraint bundle for plucked- or struck-string melody lines.
  /// Applied only when a caller explicitly asks for it (currently the
  /// generator's arpeggio track); no GM family triggers it automatically,
  /// because most SHARC pools are bowed or blown samples where a 0.5 ms
  /// attack exposes ugly transients. Captures the impulse-excited string
  /// model: instantaneous onset, short intrinsic decay, slight inharmonic
  /// stretch, narrow chorus emulating multi-string / course detuning.
  static let pluckedOrStruck: [PadConstraint] = [
    .ampAttackValue(0.0005),
    .ampDecayValue(0.5),
    .ampSustainValue(0.0),
    .chorus(cents: 5, voices: 3),
    .padSynthStretch(1.01)
  ]

  // ampAttackRange: pre-computed seconds (previously derived via lerp(0.5, 8.0, smoothRange)).
  // Also used for ampRelease when characteristicDuration is nil.
  // swiftlint:disable line_length comma
  static let `default` = GMPadProfile(shapes: [.triangle, .sawtooth, .square], wavetableNames: ["fm_bell", "fm_electric", "fm_metallic", "fm_shallow", "fm_deep", "bright", "warm", "organ", "hollow"], ampAttackRange: 2.0...6.5,   filterCutoffRange: 60...140,  vibratoWeight: 0.4,  constraints: [])
  static let piano     = GMPadProfile(shapes: [.triangle, .square],                   wavetableNames: ["fm_electric", "fm_shallow", "bright", "warm"],                                                         ampAttackRange: 1.625...3.875, filterCutoffRange: 80...200,  vibratoWeight: 0.1,  constraints: [])
  static let chromPerc = GMPadProfile(shapes: [.sine, .triangle],                     wavetableNames: ["fm_bell", "fm_metallic", "bright"],                                                                    ampAttackRange: 2.0...4.25,  filterCutoffRange: 100...300, vibratoWeight: 0.0,  constraints: [])
  static let organ     = GMPadProfile(shapes: [.square, .sawtooth],                   wavetableNames: ["organ", "hollow", "bright"],                                                                           ampAttackRange: 0.5...2.375, filterCutoffRange: 60...150,  vibratoWeight: 0.5,  constraints: [])
  static let guitar    = GMPadProfile(shapes: [.triangle, .sawtooth],                 wavetableNames: ["fm_shallow", "warm", "bright"],                                                                        ampAttackRange: 1.625...3.875, filterCutoffRange: 60...150,  vibratoWeight: 0.25, constraints: [])
  // Note: bass deliberately OMITS pluckedOrStruck. Its SHARC sample pool is
  // bowed contrabass (CB, CB_martele, CB_muted) and contrabassoon — none of
  // which are actually plucked/struck. A 0.5 ms attack on a hammered-bow
  // sample exposes the raw transient and sounds brittle. The profile-derived
  // attack smooths the bow/reed onset into a usable bass tone.
  static let bass      = GMPadProfile(
    shapes: [.sawtooth, .square],
    wavetableNames: ["fm_deep", "warm"],
    ampAttackRange: 1.25...3.125,
    filterCutoffRange: 50...80,
    vibratoWeight: 0.0,
    constraints: [
      .subOctaveSine,
      .noDetune,
      .noVibrato,
      .noFilterLFO,
      .noCrossfadeLFO,
      .chorus(cents: 0, voices: 1),
      .noSpatialMotion,
      .filterCutoffMaxMultiplier(16.0)
    ]
  )
  static let strings   = GMPadProfile(shapes: [.sawtooth, .triangle],                 wavetableNames: ["warm", "hollow", "fm_shallow"],                                                                        ampAttackRange: 3.5...6.875, filterCutoffRange: 60...140,  vibratoWeight: 0.75, constraints: [])
  static let ensemble  = GMPadProfile(shapes: [.sawtooth, .square],                     wavetableNames: ["warm", "hollow", "bright"],                                                                            ampAttackRange: 4.25...7.25, filterCutoffRange: 55...120,  vibratoWeight: 0.6,  constraints: [])
  static let brass     = GMPadProfile(shapes: [.sawtooth],                   wavetableNames: ["bright", "fm_deep", "fm_metallic"],                                                                    ampAttackRange: 2.0...4.625, filterCutoffRange: 80...200,  vibratoWeight: 0.3,  constraints: [])
  static let reed      = GMPadProfile(shapes: [.square, .triangle],                   wavetableNames: ["hollow", "warm", "fm_shallow"],                                                                        ampAttackRange: 2.0...4.25,  filterCutoffRange: 70...180,  vibratoWeight: 0.35, constraints: [])
  static let pipe      = GMPadProfile(shapes: [.square, .triangle, .sawtooth],                     wavetableNames: ["hollow", "fm_shallow", "bright"],                                                                      ampAttackRange: 2.0...4.25,  filterCutoffRange: 80...200,  vibratoWeight: 0.3,  constraints: [])
  static let synthLead = GMPadProfile(shapes: [.triangle, .sawtooth, .square], wavetableNames: ["fm_bell", "fm_electric", "fm_metallic", "fm_shallow", "fm_deep", "bright", "hollow"],                 ampAttackRange: 1.25...4.25, filterCutoffRange: 60...200,  vibratoWeight: 0.4,  constraints: [])
  static let synthPad  = GMPadProfile(shapes: [.sawtooth, .square ],                     wavetableNames: ["warm", "hollow", "fm_shallow", "fm_deep", "fm_bell"],                                                 ampAttackRange: 5.0...8.0,   filterCutoffRange: 50...110,  vibratoWeight: 0.6,  constraints: [])
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

// MARK: - Oscillator descriptor helpers

/// Builds a padSynth oscillator descriptor with a SHARC instrument and default PADsynth params.
/// When `stretchOverride` is non-nil, that value replaces the default stretch=1 (e.g. 1.01
/// for plucked/struck strings to capture the slight inharmonicity of real strings).
private func randomPadSynthOscDescriptor(gmProgram: Int?, octave: CoreFloat,
                                         forbidDetune: Bool = true,
                                         stretchOverride: CoreFloat? = nil) -> PadOscDescriptor {
  let instrument = randomSharcInstrument(for: gmProgram)
  let params = PADSynthSyntax(
    baseShape: .oneOverNSquared, tilt: 0, bandwidthCents: 50, bwScale: 1,
    profileShape: .gaussian, stretch: stretchOverride ?? 1,
    selectedInstrument: instrument, envelopeCoefficients: nil
  )
  let detune: CoreFloat = forbidDetune ? 0 : SongRNG.float(in: -12...12)
  return PadOscDescriptor(kind: .padSynth, shape: nil, file: nil, padSynthParams: params,
                          detuneCents: detune, octave: octave)
}

/// Picks a random basic oscillator descriptor from the profile's standard shapes.
private func randomOscDescriptor(profile: GMPadProfile, octave: CoreFloat,
                                 forbidDetune: Bool = true) -> PadOscDescriptor {
  let detune: CoreFloat = forbidDetune ? 0 : SongRNG.float(in: -12...12)
  return PadOscDescriptor(kind: .standard, shape: SongRNG.pick(profile.shapes) ?? .square, file: nil,
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

// MARK: - Audition persistence

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

// MARK: - Diagnostic output

private func printRandomPadDiagnostic(gmProgram: Int?, characteristicDuration: CoreFloat?,
                                      template: PadTemplateSyntax, rose: RoseSyntax) {
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
  print("""
    ┌─ Random Pad ──────────────────────────────
    │ profile: \(profileName)  (GM \(gmStr), duration \(durStr))
    │ osc1: \(oscDesc(template.oscillators[0]))
    │ osc2: \(oscDesc(template.oscillators[1]))
    │ crossfade: \(template.crossfade)  rate=\(String(format: "%.4f", template.crossfadeRate)) Hz
    │ vibrato: \(template.vibratoEnabled ? "on" : "off")  depth=\(template.vibratoDepth)
    │ filter LFO: \(template.filterLFORate.map { String(format: "%.4f", $0) } ?? "off") Hz
    │ amp env: atk=\(String(format: "%.3f", template.ampAttack))  dec=\(template.ampDecay)  sus=\(template.ampSustain)  rel=\(String(format: "%.3f", template.ampRelease))
    │ filt env: atk=\(template.filterEnvAttack)  dec=\(template.filterEnvDecay)  sus=\(template.filterEnvSustain)  rel=\(template.filterEnvRelease)
    │ filt: cutoffLow=\(template.filterCutoffLow) Hz  mult=\(String(format: "%.2f", template.filterCutoffMultiplier))  resonance=\(String(format: "%.2f", template.filterResonance))
    │ chorus: radius=\(template.chorusCentRadius)¢  voices=\(template.chorusNumVoices)
    │ rose: amp=\(String(format: "%.2f", rose.amp))  freq=\(String(format: "%.4f", rose.freq)) Hz  k=\(Int(rose.leafFactor))
    └───────────────────────────────────────────
    """)
}

// MARK: - makeRandomPadPreset

// swiftlint:disable function_body_length
/// Generates a fresh random pad preset, constrained to the timbre space of the given GM program.
/// When characteristicDuration is provided (median note sustain in seconds), ampAttack and
/// ampRelease are derived from it so short-note tracks feel snappy and long-note tracks bloom slowly.
/// When `pluckedOrStruck` is true, layer the impulse-excited-string constraint bundle on top of
/// the GM profile's constraints (fast attack, short decay, narrow chorus, slight stretch).
func makeRandomPadPreset(gmProgram: Int? = nil, characteristicDuration: CoreFloat? = nil,
                         pluckedOrStruck: Bool = false) -> PresetSyntax {
  let profile = gmPadProfile(for: gmProgram)
  let constraints: [PadConstraint] =
    pluckedOrStruck ? profile.constraints + GMPadProfile.pluckedOrStruck : profile.constraints
  // Derive amp envelope from median note duration when available.
  // attack ≈ 20% of median sustain (50 ms – 4 s); release ≈ 30% (100 ms – 5 s).
  // Falls back to profile's ampAttackRange when no duration is given.
  // .ampAttackCeiling clamps the result for profiles that need a fast edge;
  // .ampAttackValue forces a specific attack outright (e.g. plucked strings).
  var ampAttack: CoreFloat = characteristicDuration.map { clamp($0 * 0.2, min: 0.05, max: 4.0) }
    ?? SongRNG.float(in: profile.ampAttackRange)
  if let ceiling = constraints.ampAttackCeiling {
    ampAttack = Swift.min(ampAttack, ceiling)
  }
  if let forced = constraints.ampAttackValue {
    ampAttack = forced
  }
  let ampRelease: CoreFloat = characteristicDuration.map { clamp($0 * 0.3, min: 0.10, max: 5.0) }
    ?? SongRNG.float(in: profile.ampAttackRange)
  let ampDecay: CoreFloat = constraints.ampDecayValue ?? 0.1

  // Osc 1: padSynth (SHARC). Always present.
  var osc1 = randomPadSynthOscDescriptor(
    gmProgram: gmProgram,
    octave: 0,
    stretchOverride: constraints.padSynthStretch
  )

  // Osc 2: forced sub-octave sine, or random standard oscillator.
  var osc2: PadOscDescriptor
  if constraints.requiresSubOctaveSine {
    osc2 = PadOscDescriptor(
      kind: .standard, shape: .sine, file: nil, padSynthParams: nil,
      detuneCents: 0, octave: -1
    )
  } else {
    let osc2Octave: CoreFloat = SongRNG.pick([-1, 0, 1] as [CoreFloat]) ?? 0
    osc2 = randomOscDescriptor(
      profile: profile, octave: osc2Octave
    )
  }

  // Crossfade: hard-disabled or LFO.
  let crossfade: PadCrossfadeKind
  let crossfadeRate: CoreFloat
  if constraints.forbidsCrossfadeLFO {
    crossfade = .static
    crossfadeRate = 0
  } else {
    crossfade = .lfo
    crossfadeRate = FloatSampler(min: 0.01, max: 0.1, dist: .exponential).next()!
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
    ampAttack: ampAttack, ampDecay: ampDecay,
    ampSustain: constraints.ampSustainValue ?? 1.0, ampRelease: ampRelease,
    filterCutoffMultiplier: constraints.filterCutoffMaxMultiplier ?? SongRNG.float(in: 2.0...4.0),
    filterResonance: 1.7,
    filterLFORate: filterLFORate,
    filterEnvAttack: SongRNG.float(in: 1...4),
    filterEnvDecay: SongRNG.float(in: 1...4),
    filterEnvSustain: SongRNG.float(in: 0.5...0.95),
    filterEnvRelease: SongRNG.float(in: 1...4),
    filterCutoffLow: SongRNG.float(in: profile.filterCutoffRange),
    chorusCentRadius: constraints.chorusOverride?.cents ?? Int(SongRNG.float(in: 5...30)),
    chorusNumVoices: constraints.chorusOverride?.voices ?? 5
  )
  let effects = EffectsSyntax(reverbPreset: 8, reverbWetDryMix: 50,
                              delayTime: 0, delayFeedback: 0, delayLowPassCutoff: 0, delayWetDryMix: 0)
  let leafFactorPick: Int = SongRNG.pick([2, 3, 5, 7]) ?? 3
  let roseAmp: CoreFloat =
    constraints.forbidsSpatialMotion
      ? 0
      : FloatSampler(min: 4, max: 8, dist: .exponential).next()!
  let rose = RoseSyntax(
    amp: roseAmp,
    leafFactor: CoreFloat(leafFactorPick),
    freq: FloatSampler(min: 0.1, max: 0.2, dist: .exponential).next()!,
    phase: SongRNG.float(in: 0...(CoreFloat.pi * 2))
  )
  printRandomPadDiagnostic(gmProgram: gmProgram, characteristicDuration: characteristicDuration,
                           template: template, rose: rose)
  return PresetSyntax(
    name: "Random Pad",
    arrow: nil, samplerFilenames: nil, samplerProgram: nil, samplerBank: nil, library: nil,
    rose: rose, effects: effects, padTemplate: template, padSynth: nil
  )
}
// swiftlint:enable function_body_length
