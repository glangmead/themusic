//
//  HierarpTransformers.swift
//  Orbital
//
//  Phrase transformers: pure index-space operations on a HierarpPhrase.
//  No chord context, no timeline. Produce a new phrase from an existing one.
//

import Foundation

protocol HierarpTransformer {
  func transform(_ phrase: HierarpPhrase) -> HierarpPhrase
}

/// Negate chord-tone leaps relative to the phrase's first chord tone.
/// Pivot is the first chord-tone index; each subsequent chordTone index `i`
/// becomes `pivot - (i - pivot)`. Scale-tone steps and rests pass through
/// unchanged (scale-tone inversion would need a different pivot convention).
///   [0, 2, -1, 1] → [0, -2, 1, -1]
///   [2, 3, 4, 5]  → [2, 1, 0, -1]
struct InvertTransformer: HierarpTransformer {
  func transform(_ phrase: HierarpPhrase) -> HierarpPhrase {
    var pivot: Int?
    let newSteps: [HierarpStep] = phrase.steps.map { step in
      switch step {
      case .chordTone(let idx, let dur):
        if let p = pivot {
          return .chordTone(p - (idx - p), durationBeats: dur)
        } else {
          pivot = idx
          return .chordTone(idx, durationBeats: dur)
        }
      case .scaleTone, .rest:
        return step
      }
    }
    return HierarpPhrase(steps: newSteps)
  }
}
