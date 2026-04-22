//
//  HierarpEmbellishers.swift
//  Orbital
//
//  Phrase embellishers: decorate a phrase while preserving its skeleton.
//  Take a HierarpChordContext so they can query the active chord at each
//  step's beat; this keeps phrases pure (no baked-in chord) while letting
//  embellishers make harmonically-informed decisions.
//

import Foundation
import Tonic

protocol HierarpEmbellisher {
  /// Return a decorated phrase. `startBeat` is the beat at which the first
  /// step begins; embellishers walk the step list accumulating beat offsets
  /// and querying the context at each step's beat.
  func apply(
    _ phrase: HierarpPhrase,
    context: HierarpChordContext,
    startBeat: Double
  ) -> HierarpPhrase
}

/// No-op embellisher. Useful as a default and for the round-1 demo.
struct IdentityEmbellisher: HierarpEmbellisher {
  func apply(
    _ phrase: HierarpPhrase,
    context: HierarpChordContext,
    startBeat: Double
  ) -> HierarpPhrase {
    phrase
  }
}

/// Insert a scale-tone passing note between two consecutive chord-tone steps
/// whose voiced scale degrees differ by exactly two (one scale tone between
/// them). The first step's duration is halved; the inserted .scaleTone takes
/// the other half; the second step is unchanged. Pairs that straddle a chord
/// boundary (active chord differs at the two step onsets) are left alone.
struct PassingTonesEmbellisher: HierarpEmbellisher {
  func apply(
    _ phrase: HierarpPhrase,
    context: HierarpChordContext,
    startBeat: Double
  ) -> HierarpPhrase {
    var result: [HierarpStep] = []
    result.reserveCapacity(phrase.steps.count)

    var beat = startBeat
    var idx = 0
    while idx < phrase.steps.count {
      let step = phrase.steps[idx]
      let next = idx + 1 < phrase.steps.count ? phrase.steps[idx + 1] : nil

      if let passing = passingInsertion(from: step, to: next, at: beat, context: context) {
        result.append(passing.halvedFirst)
        result.append(passing.insertedScaleTone)
      } else {
        result.append(step)
      }

      beat += step.durationBeats
      idx += 1
    }

    return HierarpPhrase(steps: result)
  }

  // MARK: - Detection

  private struct PassingInsertion {
    let halvedFirst: HierarpStep
    let insertedScaleTone: HierarpStep
  }

  private func passingInsertion(
    from step: HierarpStep,
    to nextStep: HierarpStep?,
    at beat: Double,
    context: HierarpChordContext
  ) -> PassingInsertion? {
    guard case .chordTone(let idxA, let durA) = step,
          let nextStep,
          case .chordTone(let idxB, _) = nextStep else { return nil }

    let stateA = context.state(at: beat)
    let stateB = context.state(at: beat + durA)
    // Straddling chord boundary: leave alone.
    guard stateA.chord.degrees == stateB.chord.degrees,
          stateA.chord.inversion == stateB.chord.inversion,
          stateA.chord.perturbations == stateB.chord.perturbations else { return nil }

    let chord = stateA.chord
    let scaleSize = stateA.key.scale.intervals.count
    guard scaleSize > 0 else { return nil }

    guard let absA = absoluteScaleDegree(chordToneIndex: idxA, chord: chord, scaleSize: scaleSize),
          let absB = absoluteScaleDegree(chordToneIndex: idxB, chord: chord, scaleSize: scaleSize)
    else { return nil }

    let diff = absB - absA
    guard abs(diff) == 2 else { return nil }

    let midDegree = absA + diff / 2
    let halfDur = durA / 2
    return PassingInsertion(
      halvedFirst: .chordTone(idxA, durationBeats: halfDur),
      insertedScaleTone: .scaleTone(midDegree, durationBeats: halfDur)
    )
  }

  /// Convert a chord-tone index (possibly wrapping) into an absolute scale
  /// degree. Matches the octave-wrap arithmetic used by ScorePatternCompiler.
  private func absoluteScaleDegree(
    chordToneIndex idx: Int,
    chord: ChordInScale,
    scaleSize: Int
  ) -> Int? {
    let voiced = chord.voicedDegrees
    let count = voiced.count
    guard count > 0 else { return nil }
    let octaveShift = idx < 0 ? (idx + 1) / count - 1 : idx / count
    let wrapped = ((idx % count) + count) % count
    return voiced[wrapped] + octaveShift * scaleSize
  }
}
