//
//  SplitMix64.swift
//  Orbital
//
//  Deterministic 64-bit PRNG used as a stream generator and as a sub-seed
//  splitter. Same algorithm Java's SplittableRandom uses internally.
//  Reference: Steele, Lea, Flood — "Fast Splittable Pseudorandom Number
//  Generators" (OOPSLA 2014).
//

import Foundation

struct SplitMix64: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
