//
//  SeedCodecTests.swift
//  OrbitalTests
//

import Testing
@testable import Orbital

@Suite("SeedCodec", .serialized)
struct SeedCodecTests {
  @Test("Round-trip boundary values")
  func roundTrip() {
    let cases: [UInt64] = [
      0,
      1,
      0xDEAD_BEEF,
      0x0001_0000_0000_0000 - 1, // 2^48 - 1
      0x0003_FFFF_FFFF_FFFF      // 2^50 - 1, the max representable seed
    ]
    for value in cases {
      let encoded = SeedCodec.encode(value)
      #expect(encoded.count == 10)
      let decoded = SeedCodec.decode(encoded)
      #expect(decoded == value)
    }
  }

  @Test("Encode produces only Crockford base32 alphabet")
  func encodeAlphabet() {
    let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    for _ in 0..<200 {
      let value = UInt64.random(in: 0...((1 << 50) - 1))
      let encoded = SeedCodec.encode(value)
      for c in encoded {
        #expect(allowed.contains(c))
      }
    }
  }

  @Test("Lowercase tolerance")
  func lowercase() {
    let value: UInt64 = 0xCAFE_BABE
    let encoded = SeedCodec.encode(value)
    let lower = encoded.lowercased()
    #expect(SeedCodec.decode(lower) == value)
  }

  @Test("Crockford confusion-character tolerance: I, L, O, U")
  func confusionChars() {
    // Crockford mappings: I→1, L→1, O→0, U→V.
    // 10-char string "0000000001" decodes to 1 (last char is the lowest 5 bits).
    #expect(SeedCodec.decode("0000000001") == 1)
    // Substitute trailing 1 with I or L (visual cousins of 1).
    #expect(SeedCodec.decode("000000000I") == 1)
    #expect(SeedCodec.decode("000000000L") == 1)
    // O is a visual cousin of 0.
    #expect(SeedCodec.decode("OOOOOOOOOO") == 0)
    // U maps to V.
    let vValue = SeedCodec.decode("000000000V")
    let uValue = SeedCodec.decode("000000000U")
    #expect(vValue != nil)
    #expect(uValue == vValue)
  }

  @Test("Whitespace and hyphen tolerance")
  func whitespaceTolerance() {
    let value: UInt64 = 0xDEAD_BEEF
    let encoded = SeedCodec.encode(value)
    // Insert spaces and hyphens between characters.
    var spaced = ""
    for (i, c) in encoded.enumerated() {
      spaced.append(c)
      if i % 2 == 1 { spaced.append("-") }
      if i % 3 == 2 { spaced.append(" ") }
    }
    #expect(SeedCodec.decode(spaced) == value)
  }

  @Test("Invalid characters return nil")
  func invalidCharacter() {
    #expect(SeedCodec.decode("ZZZZZZZZZ@") == nil)
    #expect(SeedCodec.decode("!@#$%^&*()") == nil)
  }

  @Test("Wrong length returns nil")
  func wrongLength() {
    #expect(SeedCodec.decode("") == nil)
    #expect(SeedCodec.decode("ABC") == nil)
    #expect(SeedCodec.decode("ABCDEFGHIJK") == nil) // 11 chars
  }

  @Test("Random produces a value within range")
  func randomRange() {
    for _ in 0..<100 {
      let v = SeedCodec.random()
      #expect(v < (1 << 50))
    }
  }

  @Test("Random produces distinct values")
  func randomDistinct() {
    var seen = Set<UInt64>()
    for _ in 0..<100 {
      seen.insert(SeedCodec.random())
    }
    #expect(seen.count > 95) // Allow a few collisions; 50 bits is plenty.
  }
}
