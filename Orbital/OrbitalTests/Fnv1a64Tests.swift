//
//  Fnv1a64Tests.swift
//  OrbitalTests
//

import Testing
@testable import Orbital

@Suite("Fnv1a64", .serialized)
struct Fnv1a64Tests {
  @Test("Empty string returns the FNV offset basis")
  func emptyString() {
    #expect(fnv1a64("") == 0xcbf2_9ce4_8422_2325)
  }

  @Test("Known answer: 'a'")
  func aChar() {
    // Reference: http://www.isthe.com/chongo/tech/comp/fnv/index.html
    #expect(fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
  }

  @Test("Known answer: 'foobar'")
  func foobar() {
    #expect(fnv1a64("foobar") == 0x8594_4171_f739_67e8)
  }

  @Test("Different inputs produce different hashes")
  func differentInputs() {
    let pairs: [(String, String)] = [
      ("foo", "bar"),
      ("ArrowRandom/[0]", "ArrowRandom/[1]"),
      ("voice0/filter/cutoffLFO", "voice1/filter/cutoffLFO")
    ]
    for (a, b) in pairs {
      #expect(fnv1a64(a) != fnv1a64(b))
    }
  }

  @Test("Same input produces same hash across calls")
  func deterministic() {
    let s = "spatial[3]/preset/voice0/filter/noiseSmoothStep"
    let h1 = fnv1a64(s)
    let h2 = fnv1a64(s)
    #expect(h1 == h2)
  }
}
