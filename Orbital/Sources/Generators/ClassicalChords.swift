//
//  ClassicalChords.swift
//  Orbital
//
//  Created by Greg Langmead on 2/27/26.
//

import Foundation

extension ChordInScale {
  init(romanNumeral: RomanNumerals) {
    switch romanNumeral {
    case .I:
      self.degrees = [0, 2, 4]
      self.inversion = 0
    case .vi:
      self.degrees = [5, 7, 9]
      self.inversion = 0
    case .IV:
      self.degrees = [3, 5, 7]
      self.inversion = 0
    case .ii:
      self.degrees = [1, 3, 5]
      self.inversion = 0
    case .V:
      self.degrees = [4, 6, 8]
      self.inversion = 0
    case .iii:
      self.degrees = [2, 4, 6]
      self.inversion = 0
    case .I6:
      self.degrees = [0, 2, 4]
      self.inversion = 1
    case .IV6:
      self.degrees = [3, 5, 7]
      self.inversion = 1
    case .ii6:
      self.degrees = [1, 3, 5]
      self.inversion = 1
    case .V6:
      self.degrees = [4, 6, 8]
      self.inversion = 1
    case .iii6:
      self.degrees = [2, 4, 6]
      self.inversion = 1
    case .vi6:
      self.degrees = [5, 7, 9]
      self.inversion = 1
    case .viio6:
      self.degrees = [6, 1, 3]
      self.inversion = 0
    case .I64:
      self.degrees = [0, 2, 4]
      self.inversion = 2
    }
  }

  /// The 14 chord types from Tymoczko's "Tonality" diagram 7.1.3,
  /// used for Baroque/Classical major-key chord progressions.
  enum RomanNumerals: Hashable {
    case I, vi, IV, ii, V, iii
    case I6, IV6, ii6, V6, iii6, vi6, viio6, I64

    /// Roman numeral display name for UI presentation.
    var displayName: String {
      switch self {
      case .I:     "I"
      case .vi:    "vi"
      case .IV:    "IV"
      case .ii:    "ii"
      case .V:     "V"
      case .iii:   "iii"
      case .I6:    "I6"
      case .IV6:   "IV6"
      case .ii6:   "ii6"
      case .V6:    "V6"
      case .iii6:  "iii6"
      case .vi6:   "vi6"
      case .viio6: "viio6"
      case .I64:   "I64"
      }
    }

    /// Probabilistic state transitions according to Tymoczko diagram 7.1.3 of Tonality.
    static func stateTransitionsBaroqueClassicalMajor(_ start: RomanNumerals) -> [(RomanNumerals, CoreFloat)] {
      switch start {
      case .I:
        return [            (.vi, 0.07), (.IV, 0.21), (.ii, 0.14), (.viio6, 0.05), (.V, 0.50), (.I64, 0.05)]
      case .vi:
        return [                          (.IV, 0.13), (.ii, 0.41), (.viio6, 0.06), (.V, 0.28), (.I6, 0.12) ]
      case .IV:
        return [(.I, 0.35), (.ii, 0.16), (.viio6, 0.10), (.V, 0.40), (.IV6, 0.10)]
      case .ii:
        return [            (.vi, 0.05), (.viio6, 0.20), (.V, 0.70), (.I64, 0.05)]
      case .viio6:
        return [(.I, 0.85), (.vi, 0.02), (.IV, 0.03), (.V, 0.10)]
      case .V:
        return [(.I, 0.88), (.vi, 0.05), (.IV6, 0.05), (.ii, 0.01)]
      case .V6:
        return [                                                                      (.V, 0.8), (.I6, 0.2)  ]
      case .I6:
        return [(.I, 0.50), (.vi, 0.07/2), (.IV, 0.11), (.ii, 0.07), (.viio6, 0.025), (.V, 0.25)              ]
      case .IV6:
        return [(.I, 0.17), (.IV, 0.65), (.ii, 0.08), (.viio6, 0.05), (.V, 0.4/2)             ]
      case .ii6:
        return [                                        (.ii, 0.10), (.viio6, 0.10), (.V6, 0.8)              ]
      case .I64:
        return [                                                                      (.V, 1.0)               ]
      case .iii:
        return [                                                                      (.V, 0.5), (.I6, 0.5)  ]
      case .iii6:
        return [                                                                      (.V, 0.5), (.I64, 0.5) ]
      case .vi6:
        return [                                                                      (.V, 0.5), (.I64, 0.5) ]
      }
    }

    /// Weighted random draw using exponential variates.
    static func weightedDraw<A>(items: [(A, CoreFloat)]) -> A? {
      func exp2<B>(_ item: (B, CoreFloat)) -> (B, CoreFloat) {
        (item.0, -1.0 * log(CoreFloat.random(in: 0...1)) / item.1)
      }
      return items.map({ exp2($0) }).min(by: { $0.1 < $1.1 })?.0
    }
  }

}
