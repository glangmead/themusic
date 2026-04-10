//
//  ArrowPRNG.swift
//  Orbital
//
//  Lock-free per-Arrow-node PRNG. Each random-consuming Arrow node owns one
//  by value (no allocations on the audio thread). Seeded once on the main
//  actor before the engine starts via `Arrow11.applyRandomSeed`, then mutated
//  only by the render callback that owns the node.
//
//  Algorithm: xorshift128+. ~4 ops per `next()`, no branches. Initialized
//  via SplitMix64 warmup so a "simple" seed (e.g. 0) produces high-quality
//  initial state.
//

import Foundation

struct Xorshift128Plus {
  var s0: UInt64
  var s1: UInt64

  init(seed: UInt64) {
    var splitter = SplitMix64(seed: seed)
    self.s0 = splitter.next()
    self.s1 = splitter.next()
    // Both halves are guaranteed non-zero by SplitMix64 starting from any seed.
  }

  mutating func next() -> UInt64 {
    var x = s0
    let y = s1
    s0 = y
    x ^= x << 23
    s1 = x ^ y ^ (x >> 17) ^ (y >> 26)
    return s1 &+ y
  }

  /// Uniform draw in `[lower, upper)` (note: half-open at the top, mirroring
  /// `Double.random(in: range)` behavior for closed ranges where the upper
  /// bound is unreachable in practice).
  mutating func nextFloat(in range: ClosedRange<CoreFloat>) -> CoreFloat {
    // 53 bits of mantissa precision in [0, 1).
    let u = CoreFloat(next() >> 11) * (1.0 / CoreFloat(1 << 53))
    return range.lowerBound + u * (range.upperBound - range.lowerBound)
  }
}
