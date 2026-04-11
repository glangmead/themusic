//
//  RandomPadBassConstraintsTests.swift
//  OrbitalTests
//
//  Verifies that the .bass GM profile applies tightening constraints to
//  generated random-pad presets, and that other profiles retain their
//  pre-existing random freedom (modulo the newly-wired vibratoWeight).
//

import Testing
import Foundation
@testable import Orbital

@Suite("Random pad bass constraints", .serialized)
struct RandomPadBassConstraintsTests {
  @Test("Bass program forces sub sine, no detune, no modulation, fast attack, capped sweep")
  func bassProgramAppliesAllConstraints() async throws {
    for seed in UInt64(1)...UInt64(20) {
      let preset = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
        makeRandomPadPreset(gmProgram: 33, characteristicDuration: 1.0)
      }
      let template = try #require(preset.padTemplate)

      // Sub oscillator: standard sine, octave -1, no detune.
      #expect(template.oscillators.count >= 2)
      #expect(template.oscillators[1].kind == .standard)
      #expect(template.oscillators[1].shape == .sine)
      #expect(template.oscillators[1].octave == -1)
      #expect(template.oscillators[1].detuneCents == 0)

      // Osc 1 (padSynth): no detune.
      #expect(template.oscillators[0].detuneCents == 0)

      // No pitch wobble.
      #expect(template.vibratoEnabled == false)

      // No slow filter sweep.
      #expect(template.filterLFORate == nil)

      // No LFO crossfade.
      #expect(template.crossfade == .static)
      #expect(template.crossfadeRate == nil)

      // No spatial motion.
      #expect(preset.rose.amp == 0)

      // Attack ceiling: derived 0.2s, must be clamped to <= 0.030.
      let atk = try #require(template.ampAttack)
      #expect(atk <= 0.030)

      // Tightened filter cutoff range.
      #expect((50.0...80.0).contains(template.filterCutoffLow))

      // Filter envelope sweep cap.
      #expect(template.filterCutoffMultiplier == 16.0)
    }
  }

  @Test("Piano program retains random freedom and honors vibratoWeight")
  func pianoProgramKeepsRandomFreedom() async throws {
    var sawAnyDetune = false
    var sawAnyFilterLFO = false
    var sawVibratoTrue = false
    var sawVibratoFalse = false

    for seed in UInt64(1)...UInt64(200) {
      let preset = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
        makeRandomPadPreset(gmProgram: 0, characteristicDuration: 1.0)
      }
      let template = try #require(preset.padTemplate)

      if (template.oscillators[0].detuneCents ?? 0) != 0 { sawAnyDetune = true }
      if template.filterLFORate != nil { sawAnyFilterLFO = true }
      if template.vibratoEnabled {
        sawVibratoTrue = true
      } else {
        sawVibratoFalse = true
      }
    }

    #expect(sawAnyDetune, "piano profile should still produce nonzero detune across seeds")
    #expect(sawAnyFilterLFO, "piano profile should still produce filter LFO across seeds")
    #expect(sawVibratoTrue, "piano profile should produce vibrato sometimes (vibratoWeight=0.1)")
    #expect(sawVibratoFalse, "piano profile should suppress vibrato sometimes (vibratoWeight=0.1)")
  }
}
