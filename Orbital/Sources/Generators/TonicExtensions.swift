//
//  TonicExtensions.swift
//  Orbital
//
//  Extensions on Tonic framework types for roman numeral notation and interval mapping.
//  Extracted from QuadHierarchy.swift.
//

import Foundation
import Tonic

// MARK: - Tonic extensions

private let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

/// Figured bass figures for inversions of triads and seventh chords.
/// For triads:  root → "", 1st → ⁶, 2nd → ⁶₄
/// For sevenths: root → ⁷, 1st → ⁶₅, 2nd → ⁴₃, 3rd → ⁴₂
private let triadFigures = ["", "⁶", "⁶₄"]
private let seventhFigures = ["⁷", "⁶₅", "⁴₃", "⁴₂"]

extension Tonic.Chord {
  /// Returns (qualityMark, figures) for the chord type, where `figures` is the
  /// array of figured-bass symbols indexed by inversion (nil for extended chords).
  private func qualityAndFigures() -> (String, [String]?) {
    switch type {
    case .major, .minor:        return ("", triadFigures)
    case .dim:                  return ("°", triadFigures)
    case .aug:                  return ("⁺", triadFigures)
    case .dom7, .min7:          return ("", seventhFigures)
    case .maj7, .min_maj7:      return ("M", seventhFigures)
    case .halfDim7:             return ("ø", seventhFigures)
    case .dim7:                 return ("°", seventhFigures)
    case .min6:                 return ("", ["⁶"])
    default:
      let desc = type.description
      let hasMinorThird = type.intervals.contains(.m3)
      if hasMinorThird, desc.hasPrefix("m"), !desc.hasPrefix("maj") {
        return (String(desc.dropFirst()), nil)
      }
      return (desc, nil)
    }
  }

  /// Roman numeral notation for this chord in the given key, e.g. "ii", "V⁶₅", "viiø⁷".
  /// The `inversion` parameter supplies the current voicing (0 = root position).
  /// Returns nil if the chord root doesn't fall on a scale degree.
  func romanNumeralNotation(in key: Key, inversion: Int = 0) -> String? {
    let keyRootPC = Int(key.root.canonicalNote.noteNumber) % 12
    let chordRootPC = Int(root.canonicalNote.noteNumber) % 12
    let semitoneDistance = ((chordRootPC - keyRootPC) % 12 + 12) % 12

    let scaleIntervals = key.scale.intervals
    guard let degree = scaleIntervals.firstIndex(where: { $0.semitones == semitoneDistance }),
          degree < romanNumerals.count else {
      return nil
    }

    let hasMinorThird = type.intervals.contains(.m3)
    let numeral = hasMinorThird
      ? romanNumerals[degree].lowercased()
      : romanNumerals[degree]

    let chordSize = type.intervals.count + 1
    let inv = ((inversion % chordSize) + chordSize) % chordSize
    let (qualityMark, figures) = qualityAndFigures()
    let extensionFigure = figures.flatMap { inv < $0.count ? $0[inv] : nil } ?? ""

    return numeral + qualityMark + extensionFigure
  }
}

// MARK: - Interval helpers

extension Tonic.Interval {
  /// Canonical mapping from semitone count (0–11) to Interval.
  /// Picks the most standard enharmonic spelling for each pitch class.
  static let semitonesMap: [Int: Tonic.Interval] = [
    0: .P1,
    1: .m2,
    2: .M2,
    3: .m3,
    4: .M3,
    5: .P4,
    6: .A4,
    7: .P5,
    8: .m6,
    9: .M6,
    10: .m7,
    11: .M7
  ]
}
