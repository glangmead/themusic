//
//  PADSynthWavetableArrow.swift
//  Orbital
//
//  Generates a wavetable from PADsynth parameters at compile time
//  and wraps it in a standard WavetableOscillator.
//

import Foundation

enum PADSynthWavetableCompiler {
  /// Reference pitch for wavetable generation (middle C).
  /// The phase accumulator handles actual pitch tracking.
  static let referencePitch: CoreFloat = 261.63

  /// Generate the full PADsynth wavetable (262 144 samples, power-of-2).
  /// Keeping the full table preserves the long, evolving texture that
  /// makes PADsynth sound smooth rather than buzzy.
  static func generateTable(params: PADSynthSyntax) -> [CoreFloat] {
    let sharcHarmonics = PADSynthEngine.resolveSharcHarmonics(
      instrumentId: params.selectedInstrument,
      midiNote: 60 // middle C
    )
    let snapshot = PADSynthEngine.ParamSnapshot(
      baseShape: params.baseShape,
      tilt: params.tilt,
      bandwidthCents: params.bandwidthCents,
      bwScale: params.bwScale,
      profileShape: params.profileShape,
      stretch: params.stretch,
      envelopeCoefficients: params.envelopeCoefficients,
      sharcHarmonics: sharcHarmonics
    )
    return PADSynthEngine.generateWavetableStatic(
      fundamentalHz: referencePitch,
      params: snapshot
    )
  }
}
