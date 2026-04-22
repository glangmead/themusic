//
//  HierarpPipeline.swift
//  Orbital
//
//  Composes a HierarpGenerator, HierarpEmbellishers, and HierarpTransformers
//  into a ScoreNoteSyntax stream. The pipeline threads a HierarpChordContext
//  to embellishers but keeps transformers purely in index space.
//
//  Rendering model: generate once, embellish once (at a fixed startBeat),
//  then emit `cycles × max(transformers.count, 1)` copies. Copy k=0 is the
//  original embellished phrase; copy k>=1 applies transformers[(k-1) % n].
//  Each copy's steps inherit the cumulative beat offset so subsequent
//  embellisher/transformer passes could be added later without retiming.
//

import Foundation

struct HierarpPipeline {
  let generator: HierarpGenerator
  let embellishers: [HierarpEmbellisher]
  let transformers: [HierarpTransformer]
  let cycles: Int

  init(
    generator: HierarpGenerator,
    embellishers: [HierarpEmbellisher] = [IdentityEmbellisher()],
    transformers: [HierarpTransformer] = [],
    cycles: Int = 1
  ) {
    self.generator = generator
    self.embellishers = embellishers
    self.transformers = transformers
    self.cycles = max(1, cycles)
  }

  /// Render into a flat list of ScoreNoteSyntax, starting at `startBeat` and
  /// stopping once total emitted duration reaches `totalBeats` (final step
  /// is truncated rather than dropped; a trailing rest fills any remainder).
  func render(
    context: HierarpChordContext,
    startBeat: Double,
    totalBeats: Double,
    octave: Int,
    velocity: Int
  ) -> [ScoreNoteSyntax] {
    let basePhrase = embellish(generator.generate(), context: context, startBeat: startBeat)
    let copies = transformerCount
    var notes: [ScoreNoteSyntax] = []
    var emitted: Double = 0.0

    outer: for cycle in 0..<cycles {
      for k in 0..<copies {
        let phrase = transformedPhrase(base: basePhrase, copyIndex: cycle * copies + k)
        for step in phrase.steps {
          let remaining = totalBeats - emitted
          if remaining <= 0 { break outer }
          let dur = min(step.durationBeats, remaining)
          notes.append(note(for: step, duration: dur, octave: octave, velocity: velocity))
          emitted += dur
        }
      }
    }

    let trailing = totalBeats - emitted
    if trailing > 0 {
      notes.append(ScoreNoteSyntax(type: .rest, durationBeats: trailing))
    }
    return notes
  }

  // MARK: - Internals

  private var transformerCount: Int { max(1, transformers.count + 1) }

  private func embellish(
    _ phrase: HierarpPhrase,
    context: HierarpChordContext,
    startBeat: Double
  ) -> HierarpPhrase {
    embellishers.reduce(phrase) { acc, emb in
      emb.apply(acc, context: context, startBeat: startBeat)
    }
  }

  /// copyIndex 0 => embellished base; copyIndex k>=1 => apply transformers[(k-1) % n].
  /// With n=0 transformers, only copyIndex 0 is used (pipeline just loops the base).
  private func transformedPhrase(base: HierarpPhrase, copyIndex: Int) -> HierarpPhrase {
    guard copyIndex > 0, !transformers.isEmpty else { return base }
    let pick = transformers[(copyIndex - 1) % transformers.count]
    return pick.transform(base)
  }

  private func note(
    for step: HierarpStep,
    duration: Double,
    octave: Int,
    velocity: Int
  ) -> ScoreNoteSyntax {
    switch step {
    case .chordTone(let idx, _):
      return ScoreNoteSyntax(
        type: .chordTone, durationBeats: duration,
        index: idx, octave: octave, velocity: velocity
      )
    case .scaleTone(let deg, _):
      return ScoreNoteSyntax(
        type: .scaleDegree, durationBeats: duration,
        degree: deg, octave: octave, velocity: velocity
      )
    case .rest:
      return ScoreNoteSyntax(type: .rest, durationBeats: duration)
    }
  }
}
