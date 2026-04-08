//
//  PADSynthSyntax.swift
//  Orbital
//

import Foundation

/// Codable representation of PADsynth algorithm parameters,
/// stored as the `padSynth` field of a PresetSyntax JSON file.
struct PADSynthSyntax: Codable, Equatable {
  let baseShape: PADBaseShape
  let tilt: CoreFloat
  let bandwidthCents: CoreFloat
  let bwScale: CoreFloat
  let profileShape: PADProfileShape
  let stretch: CoreFloat
  /// SHARC instrument ID, or nil for formula-based harmonics.
  let selectedInstrument: String?
  /// Polynomial coefficients for drawn spectral envelope, or nil.
  let envelopeCoefficients: [CoreFloat]?
}
