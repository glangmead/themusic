//
//  SongRNGDeterminismTests.swift
//  OrbitalTests
//
//  Verifies that compile-time random pad construction is deterministic when
//  driven from the same SongRNG seed.
//

import Testing
import Foundation
@testable import Orbital

@Suite("SongRNG determinism", .serialized)
struct SongRNGDeterminismTests {
  /// Encode just the randomness-derived fields of a PresetSyntax. The `name`
  /// field is intentionally excluded because `makeRandomPadPreset` embeds a
  /// per-app-launch incrementing audition counter from UserDefaults — that's
  /// a non-deterministic side-effect, not part of the seed-driven content.
  private func encodeDeterministicParts(_ preset: PresetSyntax) -> Data? {
    // Compare the rose (4 random fields), effects (fixed), and padTemplate
    // (the bulk of random content).
    struct DeterministicView: Codable {
      let rose: RoseSyntax
      let effects: EffectsSyntax
      let padTemplate: PadTemplateSyntax?
    }
    let view = DeterministicView(rose: preset.rose, effects: preset.effects, padTemplate: preset.padTemplate)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(view)
  }

  @Test("Same seed produces identical random pad content")
  func sameSeedSamePad() async {
    let seed: UInt64 = 0xDEAD_BEEF_CAFE_BABE

    let preset1 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      makeRandomPadPreset(gmProgram: 0, characteristicDuration: 1.0)
    }
    let preset2 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      makeRandomPadPreset(gmProgram: 0, characteristicDuration: 1.0)
    }

    let data1 = encodeDeterministicParts(preset1)
    let data2 = encodeDeterministicParts(preset2)
    #expect(data1 != nil)
    #expect(data1 == data2)
  }

  @Test("Different seeds produce different random pad content")
  func differentSeedsDifferentPad() async {
    let preset1 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: 1))) {
      makeRandomPadPreset(gmProgram: 0, characteristicDuration: 1.0)
    }
    let preset2 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: 999_999))) {
      makeRandomPadPreset(gmProgram: 0, characteristicDuration: 1.0)
    }

    let data1 = encodeDeterministicParts(preset1)
    let data2 = encodeDeterministicParts(preset2)
    #expect(data1 != nil)
    #expect(data2 != nil)
    #expect(data1 != data2)
  }

  @Test("FloatSampler exponential is deterministic under SongRNG")
  func floatSamplerDeterministic() async {
    let seed: UInt64 = 0xCAFE_BABE
    let values1 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var out: [CoreFloat] = []
      let sampler = FloatSampler(min: 0.01, max: 5.0, dist: .exponential)
      for _ in 0..<20 { out.append(sampler.next() ?? 0) }
      return out
    }
    let values2 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var out: [CoreFloat] = []
      let sampler = FloatSampler(min: 0.01, max: 5.0, dist: .exponential)
      for _ in 0..<20 { out.append(sampler.next() ?? 0) }
      return out
    }
    #expect(values1 == values2)
  }

  @Test("RandomIterator is deterministic under SongRNG install scope")
  func randomIteratorDeterministic() async {
    let collection = ["a", "b", "c", "d", "e"]
    let seed: UInt64 = 0xFEED_FACE
    let picks1 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var iter = RandomIterator(of: collection)
      var out: [String] = []
      for _ in 0..<20 { if let v = iter.next() { out.append(v) } }
      return out
    }
    let picks2 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var iter = RandomIterator(of: collection)
      var out: [String] = []
      for _ in 0..<20 { if let v = iter.next() { out.append(v) } }
      return out
    }
    #expect(picks1 == picks2)
    #expect(picks1.count == 20)
  }

  @Test("CyclicShuffledIterator is deterministic under SongRNG install scope")
  func cyclicShuffledDeterministic() async {
    let collection = [1, 2, 3, 4, 5]
    let seed: UInt64 = 0xBEEF_CAFE
    let seq1 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var iter = CyclicShuffledIterator(cycling: collection)
      var out: [Int] = []
      for _ in 0..<15 { if let v = iter.next() { out.append(v) } }
      return out
    }
    let seq2 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var iter = CyclicShuffledIterator(cycling: collection)
      var out: [Int] = []
      for _ in 0..<15 { if let v = iter.next() { out.append(v) } }
      return out
    }
    #expect(seq1 == seq2)
  }

  @Test("FragmentPoolIterator is deterministic under SongRNG install scope")
  func fragmentPoolDeterministic() async {
    let fragments = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    let seed: UInt64 = 0x1234_5678
    let seq1 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var iter = FragmentPoolIterator(fragments: fragments)
      var out: [Int] = []
      for _ in 0..<20 { if let v = iter.next() { out.append(v) } }
      return out
    }
    let seq2 = await SongRNG.$box.withValue(SongRNGBox(SplitMix64(seed: seed))) {
      var iter = FragmentPoolIterator(fragments: fragments)
      var out: [Int] = []
      for _ in 0..<20 { if let v = iter.next() { out.append(v) } }
      return out
    }
    #expect(seq1 == seq2)
  }

  @Test("Default SongRNG box is system random (non-deterministic)")
  func defaultBoxIsRandom() {
    // Outside any withValue install scope, two FloatSamplers seeded with the
    // same parameters should produce different sequences (because they pull
    // from SystemRandomNumberGenerator). Use enough draws to make collision
    // statistically negligible.
    let sampler = FloatSampler(min: 0.0, max: 1.0, dist: .uniform)
    var seq1: [CoreFloat] = []
    var seq2: [CoreFloat] = []
    for _ in 0..<10 { seq1.append(sampler.next() ?? 0) }
    for _ in 0..<10 { seq2.append(sampler.next() ?? 0) }
    #expect(seq1 != seq2)
  }
}
