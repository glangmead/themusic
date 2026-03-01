//
//  UIKnobPropagationTests.swift
//  OrbitalTests
//
//  Phase 3: UI knob propagation tests — knob-to-handle propagation, knob-to-sound verification
//

import Testing
import Foundation
@testable import Orbital

// MARK: - Test Helpers

/// Build a set of Presets and merged handles that mirrors what SpatialPreset + SyntacticSynth do,
/// but without AVFoundation. Returns (presets, aggregatedHandles).
private func buildTestPresetPool(
  filename: String = "5th_cluedo.json",
  presetCount: Int = 3,
  voicesPerPreset: Int = 1
) throws -> (presets: [Preset], handles: ArrowWithHandles) {
  let syntax = try loadPresetSyntax(filename)
  guard let arrowSyntax = syntax.arrow else {
    throw PresetLoadError.fileNotFound("No arrow in \(filename)")
  }

  var presets = [Preset]()
  for _ in 0..<presetCount {
    let preset = Preset(arrowSyntax: arrowSyntax, numVoices: voicesPerPreset, initEffects: false)
    presets.append(preset)
  }

  // Aggregate handles across all presets, mirroring SpatialPreset.handles
  let aggregated = ArrowWithHandles(ArrowIdentity())
  for preset in presets {
    if let h = preset.handles {
      _ = aggregated.withMergeDictsFromArrow(h)
    }
  }

  return (presets, aggregated)
}

/// Renders audio from a Preset's sound arrow (no AVFoundation needed).
private func renderPresetSound(_ preset: Preset, sampleCount: Int = 4410) -> [CoreFloat] {
  guard let sound = preset.sound else { return [] }
  return renderArrow(sound, sampleCount: sampleCount)
}

// MARK: - Handle Propagation Tests

@Suite("Knob-to-Handle Propagation", .serialized)
struct KnobToHandlePropagationTests {

  // MARK: ADSR envelope parameters

  @Test("Setting ampEnv attackTime propagates to all voices in all presets")
  func ampEnvAttackPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    let ampEnvs = handles.namedADSREnvelopes["ampEnv"]!
    let newValue: CoreFloat = 1.234

    // Simulate what SyntacticSynth.ampAttack didSet does
    ampEnvs.forEach { $0.env.attackTime = newValue }

    // Verify every voice in every preset got the new value
    for (pi, preset) in presets.enumerated() {
      for voice in preset.voices {
        for env in voice.namedADSREnvelopes["ampEnv"]! {
          #expect(env.env.attackTime == newValue,
                  "Preset \(pi) voice ampEnv attackTime should be \(newValue), got \(env.env.attackTime)")
        }
      }
    }
  }

  @Test("Setting ampEnv decayTime propagates to all voices")
  func ampEnvDecayPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    let newValue: CoreFloat = 0.567
    handles.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.decayTime = newValue }

    for preset in presets {
      for voice in preset.voices {
        for env in voice.namedADSREnvelopes["ampEnv"]! {
          #expect(env.env.decayTime == newValue)
        }
      }
    }
  }

  @Test("Setting ampEnv sustainLevel propagates to all voices")
  func ampEnvSustainPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    let newValue: CoreFloat = 0.42
    handles.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.sustainLevel = newValue }

    for preset in presets {
      for voice in preset.voices {
        for env in voice.namedADSREnvelopes["ampEnv"]! {
          #expect(env.env.sustainLevel == newValue)
        }
      }
    }
  }

  @Test("Setting ampEnv releaseTime propagates to all voices")
  func ampEnvReleasePropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    let newValue: CoreFloat = 2.5
    handles.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.releaseTime = newValue }

    for preset in presets {
      for voice in preset.voices {
        for env in voice.namedADSREnvelopes["ampEnv"]! {
          #expect(env.env.releaseTime == newValue)
        }
      }
    }
  }

  @Test("Setting filterEnv parameters propagates to all voices")
  func filterEnvPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    guard let filterEnvs = handles.namedADSREnvelopes["filterEnv"], !filterEnvs.isEmpty else {
      // Not all presets have a filterEnv — skip gracefully
      return
    }
    let newAttack: CoreFloat = 0.8
    let newDecay: CoreFloat = 0.3
    filterEnvs.forEach {
      $0.env.attackTime = newAttack
      $0.env.decayTime = newDecay
    }

    for preset in presets {
      for voice in preset.voices {
        if let envs = voice.namedADSREnvelopes["filterEnv"] {
          for env in envs {
            #expect(env.env.attackTime == newAttack)
            #expect(env.env.decayTime == newDecay)
          }
        }
      }
    }
  }

  // MARK: Const parameters

  @Test("Setting cutoff const propagates to all voices")
  func cutoffConstPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    guard let cutoffs = handles.namedConsts["cutoff"], !cutoffs.isEmpty else {
      return // preset may not have a filter
    }
    let newValue: CoreFloat = 2500.0
    cutoffs.forEach { $0.val = newValue }

    for preset in presets {
      for voice in preset.voices {
        if let consts = voice.namedConsts["cutoff"] {
          for c in consts {
            #expect(c.val == newValue)
          }
        }
      }
    }
  }

  @Test("Setting osc mix consts propagates to all voices")
  func oscMixPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    for mixName in ["osc1Mix", "osc2Mix", "osc3Mix"] {
      guard let consts = handles.namedConsts[mixName], !consts.isEmpty else { continue }
      let newValue: CoreFloat = 0.77
      consts.forEach { $0.val = newValue }

      for preset in presets {
        for voice in preset.voices {
          if let voiceConsts = voice.namedConsts[mixName] {
            for c in voiceConsts {
              #expect(c.val == newValue,
                      "\(mixName) should be \(newValue), got \(c.val)")
            }
          }
        }
      }
    }
  }

  @Test("Setting vibrato consts propagates to all voices")
  func vibratoConstsPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    for (name, newVal) in [("vibratoAmp", 5.0), ("vibratoFreq", 12.0)] as [(String, CoreFloat)] {
      guard let consts = handles.namedConsts[name], !consts.isEmpty else { continue }
      consts.forEach { $0.val = newVal }

      for preset in presets {
        for voice in preset.voices {
          if let voiceConsts = voice.namedConsts[name] {
            for c in voiceConsts {
              #expect(c.val == newVal, "\(name) should be \(newVal), got \(c.val)")
            }
          }
        }
      }
    }
  }

  // MARK: Oscillator shape

  @Test("Setting oscillator shape propagates to all voices")
  func oscShapePropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    for oscName in ["osc1", "osc2", "osc3"] {
      guard let oscs = handles.namedBasicOscs[oscName], !oscs.isEmpty else { continue }
      let newShape = BasicOscillator.OscShape.triangle
      oscs.forEach { $0.shape = newShape }

      for preset in presets {
        for voice in preset.voices {
          if let voiceOscs = voice.namedBasicOscs[oscName] {
            for osc in voiceOscs {
              #expect(osc.shape == newShape,
                      "\(oscName) shape should be triangle, got \(osc.shape)")
            }
          }
        }
      }
    }
  }

  // MARK: Choruser parameters

  @Test("Setting choruser params propagates to all voices")
  func choruserPropagates() throws {
    let (presets, handles) = try buildTestPresetPool()
    for choruserName in ["osc1Choruser", "osc2Choruser", "osc3Choruser"] {
      guard let chorusers = handles.namedChorusers[choruserName], !chorusers.isEmpty else { continue }
      let newRadius = 25
      let newVoices = 8
      chorusers.forEach {
        $0.chorusCentRadius = newRadius
        $0.chorusNumVoices = newVoices
      }

      for preset in presets {
        for voice in preset.voices {
          if let voiceChorusers = voice.namedChorusers[choruserName] {
            for ch in voiceChorusers {
              #expect(ch.chorusCentRadius == newRadius)
              #expect(ch.chorusNumVoices == newVoices)
            }
          }
        }
      }
    }
  }

  // MARK: Handle count verification

  @Test("Aggregated handle count equals presetCount × voicesPerPreset × single-voice count")
  func handleCountsScale() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    let single = syntax.arrow!.compile()
    let singleAmpEnvCount = single.namedADSREnvelopes["ampEnv"]?.count ?? 0

    let presetCount = 4
    let (_, handles) = try buildTestPresetPool(presetCount: presetCount, voicesPerPreset: 1)
    let totalAmpEnvCount = handles.namedADSREnvelopes["ampEnv"]?.count ?? 0

    #expect(totalAmpEnvCount == singleAmpEnvCount * presetCount,
            "Expected \(singleAmpEnvCount * presetCount) ampEnvs, got \(totalAmpEnvCount)")
  }
}

// MARK: - Knob-to-Sound Verification Tests

@Suite("Knob-to-Sound Verification", .serialized)
struct KnobToSoundVerificationTests {

  @Test("Changing filter cutoff changes the rendered output")
  func filterCutoffChangesSound() throws {
    // Build a simple sawtooth-through-filter arrow inline so we control the const names.
    let sawArrow: ArrowSyntax = .compose(arrows: [
      .prod(of: [
        .compose(arrows: [
          .prod(of: [.const(name: "freq", val: 300), .identity]),
          .osc(name: "osc1", shape: .sawtooth, width: .const(name: "osc1Width", val: 1))
        ]),
        .envelope(name: "ampEnv", attack: 0.01, decay: 0.1, sustain: 1.0, release: 0.1, scale: 1)
      ]),
      .lowPassFilter(
        name: "filter",
        cutoff: .const(name: "cutoffLow", val: 5000),
        resonance: .const(name: "resonance", val: 0.7)
      )
    ])

    // Build two presets with different cutoff values
    let presetHigh = Preset(arrowSyntax: sawArrow, numVoices: 1, initEffects: false)
    let presetLow = Preset(arrowSyntax: sawArrow, numVoices: 1, initEffects: false)

    // Set cutoffs via the named const
    if let consts = presetHigh.handles?.namedConsts["cutoffLow"] {
      consts.forEach { $0.val = 15000.0 }
    }
    if let consts = presetLow.handles?.namedConsts["cutoffLow"] {
      consts.forEach { $0.val = 200.0 }
    }

    // Trigger notes on both
    let note = MidiNote(note: 60, velocity: 127)
    presetHigh.noteOn(note)
    presetLow.noteOn(note)

    let bufHigh = renderPresetSound(presetHigh)
    let bufLow = renderPresetSound(presetLow)

    let rmsHigh = rms(bufHigh)
    let rmsLow = rms(bufLow)

    // Low cutoff should attenuate harmonics → lower RMS for a harmonically rich sound
    #expect(rmsHigh > 0.001, "High cutoff should produce sound, got \(rmsHigh)")
    #expect(rmsLow > 0.001, "Low cutoff should produce sound, got \(rmsLow)")

    // Check they actually differ
    var maxDiff: CoreFloat = 0
    let compareLen = min(bufHigh.count, bufLow.count)
    for i in 0..<compareLen {
      maxDiff = max(maxDiff, abs(bufHigh[i] - bufLow[i]))
    }
    #expect(maxDiff > 0.001,
            "Different cutoffs should produce different waveforms (maxDiff: \(maxDiff), rmsHigh: \(rmsHigh), rmsLow: \(rmsLow))")
  }

  @Test("Changing amp sustain level changes output amplitude during sustain")
  func ampSustainChangesAmplitude() throws {
    let syntax = try loadPresetSyntax("sine.json")
    guard let arrowSyntax = syntax.arrow else {
      Issue.record("No arrow in sine.json")
      return
    }

    let presetLoud = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)
    let presetQuiet = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)

    // Set different sustain levels via the handles
    presetLoud.handles?.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.sustainLevel = 1.0 }
    presetQuiet.handles?.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.sustainLevel = 0.2 }

    // Trigger notes
    presetLoud.noteOn(MidiNote(note: 69, velocity: 127))
    presetQuiet.noteOn(MidiNote(note: 69, velocity: 127))

    // Render enough samples to get past attack+decay into sustain
    // Use a longer render to be well into sustain
    let bufLoud = renderPresetSound(presetLoud, sampleCount: 44100)
    let bufQuiet = renderPresetSound(presetQuiet, sampleCount: 44100)

    // Measure RMS of the tail (sustain portion, last 50%)
    let tailStart = bufLoud.count / 2
    let loudTail = Array(bufLoud[tailStart...])
    let quietTail = Array(bufQuiet[tailStart...])

    let rmsLoud = rms(loudTail)
    let rmsQuiet = rms(quietTail)

    #expect(rmsLoud > rmsQuiet,
            "Sustain 1.0 tail RMS (\(rmsLoud)) should exceed sustain 0.2 tail RMS (\(rmsQuiet))")
  }

  @Test("Changing oscillator shape changes the waveform character")
  func oscShapeChangesWaveform() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    guard let arrowSyntax = syntax.arrow else {
      Issue.record("No arrow")
      return
    }

    let presetA = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)
    let presetB = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)

    // Set osc1 to sine on A, square on B
    if let oscs = presetA.handles?.namedBasicOscs["osc1"], !oscs.isEmpty {
      oscs.forEach { $0.shape = .sine }
    }
    if let oscs = presetB.handles?.namedBasicOscs["osc1"], !oscs.isEmpty {
      oscs.forEach { $0.shape = .square }
    }

    presetA.noteOn(MidiNote(note: 69, velocity: 127))
    presetB.noteOn(MidiNote(note: 69, velocity: 127))

    let bufA = renderPresetSound(presetA, sampleCount: 44100)
    let bufB = renderPresetSound(presetB, sampleCount: 44100)

    // Compare zero crossings — square wave has sharper transitions
    let zcA = zeroCrossings(bufA)
    let zcB = zeroCrossings(bufB)

    // The waveforms should differ measurably
    var maxDiff: CoreFloat = 0
    let compareLen = min(bufA.count, bufB.count)
    for i in 0..<compareLen {
      maxDiff = max(maxDiff, abs(bufA[i] - bufB[i]))
    }
    #expect(maxDiff > 0.01,
            "Different osc shapes should produce different waveforms (maxDiff: \(maxDiff), zcA: \(zcA), zcB: \(zcB))")
  }

  @Test("Changing chorus cent radius changes the output")
  func chorusCentRadiusChangesSound() throws {
    let syntax = try loadPresetSyntax("5th_cluedo.json")
    guard let arrowSyntax = syntax.arrow else {
      Issue.record("No arrow")
      return
    }

    let presetNarrow = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)
    let presetWide = Preset(arrowSyntax: arrowSyntax, numVoices: 1, initEffects: false)

    if let chorusers = presetNarrow.handles?.namedChorusers["osc1Choruser"], !chorusers.isEmpty {
      chorusers.forEach { $0.chorusCentRadius = 0 }
    }
    if let chorusers = presetWide.handles?.namedChorusers["osc1Choruser"], !chorusers.isEmpty {
      chorusers.forEach { $0.chorusCentRadius = 50 }
    }

    presetNarrow.noteOn(MidiNote(note: 69, velocity: 127))
    presetWide.noteOn(MidiNote(note: 69, velocity: 127))

    let bufNarrow = renderPresetSound(presetNarrow, sampleCount: 44100)
    let bufWide = renderPresetSound(presetWide, sampleCount: 44100)

    var maxDiff: CoreFloat = 0
    let compareLen = min(bufNarrow.count, bufWide.count)
    for i in 0..<compareLen {
      maxDiff = max(maxDiff, abs(bufNarrow[i] - bufWide[i]))
    }
    #expect(maxDiff > 0.001,
            "Different chorus cent radius should produce different waveforms (maxDiff: \(maxDiff))")
  }
}
