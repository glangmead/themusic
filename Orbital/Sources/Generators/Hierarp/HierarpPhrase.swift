//
//  HierarpPhrase.swift
//  Orbital
//
//  Pure phrase data for the Hierarp melody subsystem. A phrase is a sequence
//  of steps in hierarchy-relative space — chord-tone indices, scale-tone
//  degrees, and rests — with per-step durations. Phrases carry no chord
//  context: resolution happens at render time against a HarmonyTimeline.
//

import Foundation

/// One event inside a HierarpPhrase. All integers are hierarchy-relative:
/// chordTone indices are interpreted against the active chord's voicedDegrees
/// (wrapping at chord size), scaleTone degrees are interpreted against the
/// active key's scale (wrapping at scale size).
enum HierarpStep: Equatable {
  case chordTone(Int, durationBeats: Double)
  case scaleTone(Int, durationBeats: Double)
  case rest(durationBeats: Double)

  var durationBeats: Double {
    switch self {
    case .chordTone(_, let d), .scaleTone(_, let d), .rest(let d):
      return d
    }
  }
}

/// An ordered list of HierarpSteps. No chord context, no absolute pitches.
struct HierarpPhrase: Equatable {
  var steps: [HierarpStep]

  init(steps: [HierarpStep] = []) {
    self.steps = steps
  }

  var totalDurationBeats: Double {
    steps.reduce(0.0) { $0 + $1.durationBeats }
  }
}
