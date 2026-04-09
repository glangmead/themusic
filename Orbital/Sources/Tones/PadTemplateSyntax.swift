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

// MARK: - Mood

enum PadMood: String, Codable {
  case cosmic
  case dark
  case warm
  case ethereal
  case gritty
  case custom
}

// MARK: - Abstract Sliders

struct PadSliders: Codable, Equatable {
  /// Smoothness: controls attack/release and chorus width. 0=sharp/short, 1=silky/long.
  var smooth: CoreFloat
  /// Bite: controls filter cutoff multiplier. 0=dark/closed, 1=bright/open.
  var bite: CoreFloat
  /// Motion: global modulation base rate. 0=glacial, 1=fast.
  var motion: CoreFloat
  /// Width: chorus cent radius and voice count. 0=mono, 1=wide.
  var width: CoreFloat
  /// Grit: filter resonance. 0=clean, 1=aggressive.
  var grit: CoreFloat
  /// Index into the combined oscillator choice list (standard shapes + curated wavetables) for osc 1.
  var osc1Index: Int
  /// Index into the combined oscillator choice list for osc 2.
  var osc2Index: Int

  // Explicit init so callers can omit osc indices (default to sine/triangle).
  init(smooth: CoreFloat, bite: CoreFloat, motion: CoreFloat, width: CoreFloat, grit: CoreFloat,
       osc1Index: Int = 0, osc2Index: Int = 1) {
    self.smooth = smooth
    self.bite = bite
    self.motion = motion
    self.width = width
    self.grit = grit
    self.osc1Index = osc1Index
    self.osc2Index = osc2Index
  }

  // Custom decode so existing JSON presets that lack osc indices still load.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    smooth = try c.decode(CoreFloat.self, forKey: .smooth)
    bite = try c.decode(CoreFloat.self, forKey: .bite)
    motion = try c.decode(CoreFloat.self, forKey: .motion)
    width = try c.decode(CoreFloat.self, forKey: .width)
    grit = try c.decode(CoreFloat.self, forKey: .grit)
    osc1Index = try c.decodeIfPresent(Int.self, forKey: .osc1Index) ?? 0
    osc2Index = try c.decodeIfPresent(Int.self, forKey: .osc2Index) ?? 1
  }

  // sine=0, triangle=1, sawtooth=2, square=3 in the combined oscillator choice list.
  static let cosmicDefaults = PadSliders(smooth: 0.8, bite: 0.2, motion: 0.3, width: 0.7, grit: 0.1, osc1Index: 0, osc2Index: 1)
  static let darkDefaults = PadSliders(smooth: 0.7, bite: 0.6, motion: 0.2, width: 0.4, grit: 0.4, osc1Index: 2, osc2Index: 3)
  static let warmDefaults = PadSliders(smooth: 0.6, bite: 0.4, motion: 0.25, width: 0.5, grit: 0.15, osc1Index: 1, osc2Index: 2)
  static let etherealDefaults = PadSliders(smooth: 0.9, bite: 0.1, motion: 0.4, width: 0.8, grit: 0.05, osc1Index: 0, osc2Index: 0)
  static let grittyDefaults = PadSliders(smooth: 0.3, bite: 0.8, motion: 0.5, width: 0.3, grit: 0.9, osc1Index: 2, osc2Index: 3)
}

// MARK: - PadTemplateSyntax

struct PadTemplateSyntax: Codable {
  let name: String

  // Oscillators (1–3)
  let oscillators: [PadOscDescriptor]

  // Crossfade
  let crossfade: PadCrossfadeKind
  /// Overrides slider-derived crossfade/noise rate when non-null.
  let crossfadeRate: CoreFloat?

  // Vibrato
  let vibratoEnabled: Bool
  /// Overrides slider-derived vibrato rate when non-null.
  let vibratoRate: CoreFloat?
  /// Vibrato pitch depth multiplier. Typical range 0.0001–0.001.
  let vibratoDepth: CoreFloat

  // Amp envelope
  /// Overrides slider-derived attack when non-null.
  let ampAttack: CoreFloat?
  let ampDecay: CoreFloat
  let ampSustain: CoreFloat
  /// Overrides slider-derived release when non-null.
  let ampRelease: CoreFloat?

  // Filter
  /// Overrides slider-derived cutoff multiplier when non-null.
  let filterCutoffMultiplier: CoreFloat?
  /// Overrides slider-derived resonance when non-null.
  let filterResonance: CoreFloat?
  /// Non-null enables a filter cutoff LFO at this Hz rate.
  let filterLFORate: CoreFloat?
  let filterEnvAttack: CoreFloat
  let filterEnvDecay: CoreFloat
  let filterEnvSustain: CoreFloat
  let filterEnvRelease: CoreFloat
  /// Low-frequency Hz floor for the filter cutoff sum node.
  let filterCutoffLow: CoreFloat

  // Mood and abstract sliders
  let mood: PadMood
  /// When non-null, overrides all mood-derived slider defaults.
  let sliders: PadSliders?
}
