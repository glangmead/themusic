//
//  PADSynthSyntaxTests.swift
//  OrbitalTests
//

import Foundation
import Testing
@testable import Orbital

@Suite(.serialized)
struct PADSynthSyntaxTests {
  @Test func roundTripDefaults() throws {
    let original = PADSynthSyntax(
      baseShape: .oneOverNSquared,
      tilt: 0.0,
      bandwidthCents: 50.0,
      bwScale: 1.0,
      profileShape: .gaussian,
      stretch: 1.0,
      selectedInstrument: nil,
      envelopeCoefficients: nil
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PADSynthSyntax.self, from: data)
    #expect(decoded == original)
  }

  @Test func decodePadSynthPresetJSON() throws {
    let json = """
    {
      "name": "PADsynth Bell",
      "rose": { "freq": 0.2, "leafFactor": 3, "phase": 0, "amp": 4 },
      "effects": {
        "reverbPreset": 4, "reverbWetDryMix": 50,
        "delayTime": 0.3, "delayFeedback": 15,
        "delayLowPassCutoff": 5000, "delayWetDryMix": 20
      },
      "padSynth": {
        "baseShape": "1/n²", "tilt": 0.0,
        "bandwidthCents": 80.0, "bwScale": 1.2,
        "profileShape": "Gaussian", "stretch": 1.15,
        "selectedInstrument": null, "envelopeCoefficients": null
      }
    }
    """
    let data = Data(json.utf8)
    let spec = try JSONDecoder().decode(PresetSyntax.self, from: data)
    #expect(spec.name == "PADsynth Bell")
    #expect(spec.padSynth != nil)
    #expect(spec.padSynth?.stretch == 1.15)
    #expect(spec.padSynth?.baseShape == .oneOverNSquared)
    #expect(spec.arrow == nil)
    #expect(spec.padTemplate == nil)
  }

  @Test func roundTripWithEnvelopeAndInstrument() throws {
    let original = PADSynthSyntax(
      baseShape: .oddHarmonics,
      tilt: -1.5,
      bandwidthCents: 120.0,
      bwScale: 1.5,
      profileShape: .detuned,
      stretch: 1.15,
      selectedInstrument: "violin_vibrato",
      envelopeCoefficients: [0.1, 0.5, -0.3, 0.02]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PADSynthSyntax.self, from: data)
    #expect(decoded == original)
  }
}
