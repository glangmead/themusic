//
//  HierarpGenerators.swift
//  Orbital
//
//  Phrase generators for the Hierarp subsystem. A generator produces a raw
//  HierarpPhrase with no chord-context awareness — it's pure shape.
//

import Foundation

protocol HierarpGenerator {
  func generate() -> HierarpPhrase
}

/// Literal phrase: a parallel pair of chord-tone indices and durations.
/// Zips them into a sequence of .chordTone steps. Example:
///   ArpGenerator(indices: [0, 2, -1, 1], durations: [1, 1, 1, 3])
/// is the Guitar Rift melody.
struct ArpGenerator: HierarpGenerator {
  let indices: [Int]
  let durations: [Double]

  func generate() -> HierarpPhrase {
    let count = min(indices.count, durations.count)
    let steps: [HierarpStep] = (0..<count).map { i in
      .chordTone(indices[i], durationBeats: durations[i])
    }
    return HierarpPhrase(steps: steps)
  }
}
