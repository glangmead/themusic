//
//  SplitMix64Tests.swift
//  OrbitalTests
//

import Testing
@testable import Orbital

@Suite("SplitMix64", .serialized)
struct SplitMix64Tests {
  @Test("Same seed produces same sequence")
  func deterministic() {
    var a = SplitMix64(seed: 0xDEAD_BEEF_CAFE_BABE)
    var b = SplitMix64(seed: 0xDEAD_BEEF_CAFE_BABE)
    for _ in 0..<100 {
      #expect(a.next() == b.next())
    }
  }

  @Test("Different seeds produce different sequences")
  func differentSeeds() {
    var a = SplitMix64(seed: 1)
    var b = SplitMix64(seed: 2)
    var draws: [(UInt64, UInt64)] = []
    for _ in 0..<10 {
      draws.append((a.next(), b.next()))
    }
    #expect(draws.contains { $0.0 != $0.1 })
  }

  @Test("Seed 0 known-answer vectors")
  func seedZeroVectors() {
    // Reference values from Vigna's canonical SplitMix64 reference at
    // https://prng.di.unimi.it/splitmix64.c starting from seed=0.
    // First two values are well-attested across implementations.
    var rng = SplitMix64(seed: 0)
    let expected: [UInt64] = [
      0xE220_A839_7B1D_CDAF,
      0x6E78_9E6A_A1B9_65F4
    ]
    for value in expected {
      #expect(rng.next() == value)
    }
  }

  @Test("Output bits look uniform on a quick chi-square sanity")
  func quickUniformitySanity() {
    var rng = SplitMix64(seed: 42)
    var bitCounts = [Int](repeating: 0, count: 64)
    let draws = 4096
    for _ in 0..<draws {
      let v = rng.next()
      for bit in 0..<64 where (v >> bit) & 1 == 1 {
        bitCounts[bit] += 1
      }
    }
    // Each bit should fire roughly half the time. Allow 10% slack.
    let half = Double(draws) / 2.0
    let slack = half * 0.10
    for count in bitCounts {
      #expect(abs(Double(count) - half) < slack)
    }
  }
}
