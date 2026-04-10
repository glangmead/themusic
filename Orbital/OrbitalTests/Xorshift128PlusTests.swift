//
//  Xorshift128PlusTests.swift
//  OrbitalTests
//

import Testing
@testable import Orbital

@Suite("Xorshift128Plus", .serialized)
struct Xorshift128PlusTests {
  @Test("Same seed produces same sequence")
  func deterministic() {
    var a = Xorshift128Plus(seed: 0xDEAD_BEEF)
    var b = Xorshift128Plus(seed: 0xDEAD_BEEF)
    for _ in 0..<256 {
      #expect(a.next() == b.next())
    }
  }

  @Test("Different seeds diverge")
  func divergence() {
    var a = Xorshift128Plus(seed: 1)
    var b = Xorshift128Plus(seed: 2)
    var draws: [(UInt64, UInt64)] = []
    for _ in 0..<10 {
      draws.append((a.next(), b.next()))
    }
    #expect(draws.contains { $0.0 != $0.1 })
  }

  @Test("Seed 0 does not produce all-zero output (SplitMix64 warmup works)")
  func seedZeroNonzero() {
    var rng = Xorshift128Plus(seed: 0)
    var draws: [UInt64] = []
    for _ in 0..<10 {
      draws.append(rng.next())
    }
    #expect(draws.contains { $0 != 0 })
  }

  @Test("nextFloat stays in range")
  func nextFloatRange() {
    var rng = Xorshift128Plus(seed: 12345)
    for _ in 0..<10_000 {
      let v = rng.nextFloat(in: -1.0...1.0)
      #expect(v >= -1.0)
      #expect(v < 1.0) // strictly less than upper bound (half-open)
    }
  }

  @Test("nextFloat distribution mean ≈ midpoint")
  func nextFloatMean() {
    var rng = Xorshift128Plus(seed: 99)
    var sum: Double = 0
    let n = 50_000
    for _ in 0..<n {
      sum += rng.nextFloat(in: 0.0...1.0)
    }
    let mean = sum / Double(n)
    #expect(abs(mean - 0.5) < 0.01)
  }

  @Test("nextFloat in arbitrary range")
  func nextFloatRangeShift() {
    var rng = Xorshift128Plus(seed: 7)
    var sum: Double = 0
    let n = 10_000
    let lo: Double = 100
    let hi: Double = 200
    for _ in 0..<n {
      let v = rng.nextFloat(in: lo...hi)
      #expect(v >= lo)
      #expect(v < hi)
      sum += v
    }
    let mean = sum / Double(n)
    #expect(abs(mean - 150.0) < 2.0)
  }
}
