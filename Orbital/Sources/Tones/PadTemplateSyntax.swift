//
//  PadTemplateSyntax.swift
//  Orbital
//
//  Codable high-level description of a pad sound.
//  PadTemplateCompiler.compile(_:) converts this into an ArrowSyntax.
//

import Foundation

// MARK: - Oscillator Descriptor

enum PadOscKind: String, Codable {
  case standard
  case wavetable
  case padSynth
}

struct PadOscDescriptor: Codable {
  let kind: PadOscKind
  /// Standard kind only — the waveform shape. Defaults to .sine when absent.
  let shape: BasicOscillator.OscShape?
  /// Wavetable kind only — built-in table name or curated_wavetables filename (without path).
  let file: String?
  /// padSynth kind only — PADsynth algorithm parameters (SHARC instrument, bandwidth, etc.).
  let padSynthParams: PADSynthSyntax?
  /// Detuning in cents, e.g. -7, 0, 7. Defaults to 0 when absent.
  let detuneCents: CoreFloat?
  /// Octave offset, e.g. 0, -1. Defaults to 0 when absent.
  let octave: CoreFloat?
}

// MARK: - Crossfade Kind

enum PadCrossfadeKind: String, Codable {
  case noiseSmoothStep
  case lfo
  case `static`
}

// MARK: - PadTemplateSyntax

struct PadTemplateSyntax: Codable {
  let name: String

  // Oscillators (1–3)
  let oscillators: [PadOscDescriptor]

  // Crossfade
  let crossfade: PadCrossfadeKind
  /// Crossfade or noise rate in Hz. Ignored when crossfade is .static.
  let crossfadeRate: CoreFloat

  // Vibrato
  let vibratoEnabled: Bool
  /// Vibrato LFO rate in Hz. Ignored when vibratoEnabled is false.
  let vibratoRate: CoreFloat
  /// Vibrato pitch depth multiplier. Typical range 0.0001–0.001.
  let vibratoDepth: CoreFloat

  // Amp envelope
  let ampAttack: CoreFloat
  let ampDecay: CoreFloat
  let ampSustain: CoreFloat
  let ampRelease: CoreFloat

  // Filter
  /// Multiplier applied to note frequency to set filter cutoff ceiling.
  let filterCutoffMultiplier: CoreFloat
  /// Filter resonance (Q). Typical range 0.3–1.5.
  let filterResonance: CoreFloat
  /// Non-null enables a filter cutoff LFO at this Hz rate.
  let filterLFORate: CoreFloat?
  let filterEnvAttack: CoreFloat
  let filterEnvDecay: CoreFloat
  let filterEnvSustain: CoreFloat
  let filterEnvRelease: CoreFloat
  /// Low-frequency Hz floor for the filter cutoff sum node.
  let filterCutoffLow: CoreFloat

  // Chorus
  let chorusCentRadius: Int
  let chorusNumVoices: Int

  /// Bit crusher amount (0 = bypass). Typical range 0–1.
  let gritAmount: CoreFloat

  // Custom decoder for backwards compatibility with JSON that has null/missing fields.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    oscillators = try c.decode([PadOscDescriptor].self, forKey: .oscillators)
    crossfade = try c.decode(PadCrossfadeKind.self, forKey: .crossfade)
    crossfadeRate = try c.decodeIfPresent(CoreFloat.self, forKey: .crossfadeRate) ?? 0
    vibratoEnabled = try c.decode(Bool.self, forKey: .vibratoEnabled)
    vibratoRate = try c.decodeIfPresent(CoreFloat.self, forKey: .vibratoRate) ?? 3.0
    vibratoDepth = try c.decode(CoreFloat.self, forKey: .vibratoDepth)
    ampAttack = try c.decodeIfPresent(CoreFloat.self, forKey: .ampAttack) ?? 2.0
    ampDecay = try c.decode(CoreFloat.self, forKey: .ampDecay)
    ampSustain = try c.decode(CoreFloat.self, forKey: .ampSustain)
    ampRelease = try c.decodeIfPresent(CoreFloat.self, forKey: .ampRelease) ?? 2.0
    filterCutoffMultiplier = try c.decodeIfPresent(CoreFloat.self, forKey: .filterCutoffMultiplier) ?? 3.0
    filterResonance = try c.decodeIfPresent(CoreFloat.self, forKey: .filterResonance) ?? 0.3
    filterLFORate = try c.decodeIfPresent(CoreFloat.self, forKey: .filterLFORate)
    filterEnvAttack = try c.decode(CoreFloat.self, forKey: .filterEnvAttack)
    filterEnvDecay = try c.decode(CoreFloat.self, forKey: .filterEnvDecay)
    filterEnvSustain = try c.decode(CoreFloat.self, forKey: .filterEnvSustain)
    filterEnvRelease = try c.decode(CoreFloat.self, forKey: .filterEnvRelease)
    filterCutoffLow = try c.decode(CoreFloat.self, forKey: .filterCutoffLow)
    chorusCentRadius = try c.decodeIfPresent(Int.self, forKey: .chorusCentRadius) ?? 15
    chorusNumVoices = try c.decodeIfPresent(Int.self, forKey: .chorusNumVoices) ?? 2
    gritAmount = try c.decodeIfPresent(CoreFloat.self, forKey: .gritAmount) ?? 0
  }

  init(
    name: String,
    oscillators: [PadOscDescriptor],
    crossfade: PadCrossfadeKind,
    crossfadeRate: CoreFloat,
    vibratoEnabled: Bool,
    vibratoRate: CoreFloat,
    vibratoDepth: CoreFloat,
    ampAttack: CoreFloat,
    ampDecay: CoreFloat,
    ampSustain: CoreFloat,
    ampRelease: CoreFloat,
    filterCutoffMultiplier: CoreFloat,
    filterResonance: CoreFloat,
    filterLFORate: CoreFloat? = nil,
    filterEnvAttack: CoreFloat,
    filterEnvDecay: CoreFloat,
    filterEnvSustain: CoreFloat,
    filterEnvRelease: CoreFloat,
    filterCutoffLow: CoreFloat,
    chorusCentRadius: Int,
    chorusNumVoices: Int,
    gritAmount: CoreFloat = 0
  ) {
    self.name = name
    self.oscillators = oscillators
    self.crossfade = crossfade
    self.crossfadeRate = crossfadeRate
    self.vibratoEnabled = vibratoEnabled
    self.vibratoRate = vibratoRate
    self.vibratoDepth = vibratoDepth
    self.ampAttack = ampAttack
    self.ampDecay = ampDecay
    self.ampSustain = ampSustain
    self.ampRelease = ampRelease
    self.filterCutoffMultiplier = filterCutoffMultiplier
    self.filterResonance = filterResonance
    self.filterLFORate = filterLFORate
    self.filterEnvAttack = filterEnvAttack
    self.filterEnvDecay = filterEnvDecay
    self.filterEnvSustain = filterEnvSustain
    self.filterEnvRelease = filterEnvRelease
    self.filterCutoffLow = filterCutoffLow
    self.chorusCentRadius = chorusCentRadius
    self.chorusNumVoices = chorusNumVoices
    self.gritAmount = gritAmount
  }
}
