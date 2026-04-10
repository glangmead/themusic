//
//  SeedCodec.swift
//  Orbital
//
//  Encode/decode 50-bit song seeds as 10-character Crockford base32 strings.
//  Crockford base32 excludes I/L/O/U so seeds are unambiguous to type.
//  Decoding is case-insensitive and tolerates whitespace, hyphens, and the
//  excluded characters via fall-back mappings.
//

import Foundation

enum SeedCodec {
  /// Crockford base32 alphabet: 0-9, A-Z minus I, L, O, U.
  /// 32 chars × 5 bits = 50 bits per 10-char seed.
  private static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

  private static let alphabetIndex: [Character: UInt64] = {
    var dict: [Character: UInt64] = [:]
    for (i, c) in alphabet.enumerated() {
      dict[c] = UInt64(i)
    }
    // Crockford confusion-tolerance: map excluded chars to their visual cousins.
    if let one = dict["1"] {
      dict["I"] = one
      dict["L"] = one
    }
    if let zero = dict["0"] {
      dict["O"] = zero
    }
    if let v = dict["V"] {
      dict["U"] = v
    }
    return dict
  }()

  static let seedBitWidth: Int = 50
  static let seedStringLength: Int = 10
  private static let seedMask: UInt64 = (1 << 50) - 1

  /// Encode a 50-bit seed (UInt64 with high 14 bits ignored) as a 10-char string.
  static func encode(_ seed: UInt64) -> String {
    var s = seed & seedMask
    var chars: [Character] = []
    chars.reserveCapacity(seedStringLength)
    for _ in 0..<seedStringLength {
      chars.append(alphabet[Int(s & 0x1F)])
      s >>= 5
    }
    return String(chars.reversed())
  }

  /// Decode a 10-char user-typed string. Tolerates lowercase, whitespace,
  /// hyphens, and Crockford confusion characters. Returns nil for invalid input.
  static func decode(_ raw: String) -> UInt64? {
    let cleaned = raw
      .uppercased()
      .filter { !$0.isWhitespace && $0 != "-" }
    guard cleaned.count == seedStringLength else { return nil }
    var result: UInt64 = 0
    for c in cleaned {
      guard let v = alphabetIndex[c] else { return nil }
      result = (result << 5) | v
    }
    return result
  }

  /// Fresh random 50-bit seed from the system RNG. Used when the user has not
  /// pasted an explicit seed.
  static func random() -> UInt64 {
    UInt64.random(in: 0...seedMask)
  }
}
