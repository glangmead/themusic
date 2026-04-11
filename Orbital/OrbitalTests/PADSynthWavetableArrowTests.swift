//
//  PADSynthWavetableArrowTests.swift
//  OrbitalTests
//

import Foundation
import Testing
@testable import Orbital

@Suite(.serialized)
struct PADSynthWavetableArrowTests {
  private func defaultParams() -> PADSynthSyntax {
    PADSynthSyntax(
      baseShape: .oneOverNSquared,
      tilt: 0.0,
      bandwidthCents: 50.0,
      bwScale: 1.0,
      profileShape: .gaussian,
      stretch: 1.0,
      selectedInstrument: nil,
      envelopeCoefficients: nil
    )
  }

  @Test func generatesNonEmptyWavetable() throws {
    let table = PADSynthWavetableCompiler.generateTable(params: defaultParams())
    // PADSynth tables are intentionally much longer than basic-oscillator wavetables —
    // PADSynthEngine.wavetableSize (262_144) vs WavetableLibrary.tableSize (2_048).
    // The long table is required by the PADsynth algorithm so the per-bin random phases
    // produce a perceivable bandwidth-spread tone instead of pitched aliasing.
    #expect(table.count == PADSynthEngine.wavetableSize)
    let hasNonZero = table.contains { abs($0) > 1e-10 }
    #expect(hasNonZero)
  }

  @Test func differentInstrumentsProduceDifferentWavetables() {
    let custom = PADSynthWavetableCompiler.generateTable(params: defaultParams())

    let oboeParams = PADSynthSyntax(
      baseShape: .oneOverNSquared, tilt: 0.0, bandwidthCents: 50.0,
      bwScale: 1.0, profileShape: .gaussian, stretch: 1.0,
      selectedInstrument: "oboe", envelopeCoefficients: nil
    )
    let oboe = PADSynthWavetableCompiler.generateTable(params: oboeParams)

    let trumpetParams = PADSynthSyntax(
      baseShape: .oneOverNSquared, tilt: 0.0, bandwidthCents: 50.0,
      bwScale: 1.0, profileShape: .gaussian, stretch: 1.0,
      selectedInstrument: "trumpet_C", envelopeCoefficients: nil
    )
    let trumpet = PADSynthWavetableCompiler.generateTable(params: trumpetParams)

    // All three should be non-empty
    #expect(custom.contains { abs($0) > 1e-10 })
    #expect(oboe.contains { abs($0) > 1e-10 })
    #expect(trumpet.contains { abs($0) > 1e-10 })

    // At least one sample should differ between each pair
    let customVsOboe = zip(custom, oboe).contains { abs($0 - $1) > 1e-6 }
    let customVsTrumpet = zip(custom, trumpet).contains { abs($0 - $1) > 1e-6 }
    let oboeVsTrumpet = zip(oboe, trumpet).contains { abs($0 - $1) > 1e-6 }
    #expect(customVsOboe, "Custom and oboe wavetables should differ")
    #expect(customVsTrumpet, "Custom and trumpet wavetables should differ")
    #expect(oboeVsTrumpet, "Oboe and trumpet wavetables should differ")
  }

  @Test func replacingPadSynthParamsUpdatesArrow() {
    let original = PADSynthSyntax(
      baseShape: .oneOverNSquared, tilt: 0.0, bandwidthCents: 50.0,
      bwScale: 1.0, profileShape: .gaussian, stretch: 1.0,
      selectedInstrument: nil, envelopeCoefficients: nil
    )
    let updated = PADSynthSyntax(
      baseShape: .oneOverNSquared, tilt: 0.0, bandwidthCents: 50.0,
      bwScale: 1.0, profileShape: .gaussian, stretch: 1.0,
      selectedInstrument: "oboe", envelopeCoefficients: nil
    )
    let arrow: ArrowSyntax = .compose(arrows: [
      .prod(of: [
        .const(name: "overallAmp", val: 1.0),
        .padSynthWavetable(name: "osc1", params: original, width: .const(name: "w", val: 1))
      ])
    ])
    let replaced = arrow.replacingPadSynthParams(updated)
    // Verify the padSynthWavetable node has the new params
    if case .compose(let children) = replaced,
       case .prod(let prodChildren) = children[0],
       case .padSynthWavetable(_, let params, _) = prodChildren[1] {
      #expect(params.selectedInstrument == "oboe")
    } else {
      Issue.record("Arrow structure changed unexpectedly")
    }
  }

  /// Build the same arrow tree as padsynth_bell.json but with configurable padSynth params.
  private func bellArrow(instrument: String?) -> ArrowSyntax {
    let padParams = PADSynthSyntax(
      baseShape: .oneOverNSquared, tilt: 0.0, bandwidthCents: 80.0,
      bwScale: 1.2, profileShape: .gaussian, stretch: 1.15,
      selectedInstrument: instrument, envelopeCoefficients: nil
    )
    return .compose(arrows: [
      .prod(of: [
        .const(name: "overallAmp", val: 1.0),
        .compose(arrows: [
          .prod(of: [
            .const(name: "freq", val: 300),
            .identity
          ]),
          .padSynthWavetable(name: "osc1", params: padParams, width: .const(name: "osc1Width", val: 1))
        ]),
        .envelope(name: "ampEnv", attack: 0.01, decay: 0.5, sustain: 0.8, release: 0.5, scale: 1)
      ]),
      .lowPassFilter(
        name: "filter",
        cutoff: .const(name: "cutoff", val: 20000),
        resonance: .const(name: "resonance", val: 0.5)
      )
    ])
  }

  @Test func differentInstrumentsProduceDifferentAudio() {
    let customArrow = bellArrow(instrument: nil)
    let tubaArrow = bellArrow(instrument: "tuba")

    let customPreset = Preset(arrowSyntax: customArrow, numVoices: 1, initEffects: false)
    let tubaPreset = Preset(arrowSyntax: tubaArrow, numVoices: 1, initEffects: false)

    let note = MidiNote(note: 60, velocity: 100)
    customPreset.noteOn(note)
    tubaPreset.noteOn(note)

    guard let customSound = customPreset.sound?.wrappedArrow,
          let tubaSound = tubaPreset.sound?.wrappedArrow else {
      Issue.record("No sound arrow on preset")
      return
    }

    let customOutput = renderArrow(customSound, sampleCount: 4410)
    let tubaOutput = renderArrow(tubaSound, sampleCount: 4410)

    let customRMS = rms(customOutput)
    let tubaRMS = rms(tubaOutput)

    // Both should produce non-silent audio
    #expect(customRMS > 0.001, "Custom should produce audio")
    #expect(tubaRMS > 0.001, "Tuba should produce audio")

    // The outputs should differ
    let diffRMS = rms(zip(customOutput, tubaOutput).map { $0 - $1 })
    #expect(diffRMS > 0.001, "Custom and tuba audio should differ (diffRMS=\(diffRMS))")
  }

  @Test func arrowSyntaxRoundTrip() throws {
    let syntax: ArrowSyntax = .padSynthWavetable(
      name: "testOsc",
      params: defaultParams(),
      width: .const(name: "w", val: 1)
    )
    let data = try JSONEncoder().encode(syntax)
    let decoded = try JSONDecoder().decode(ArrowSyntax.self, from: data)
    #expect(decoded == syntax)
  }
}
