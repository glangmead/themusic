//
//  SongRNG.swift
//  Orbital
//
//  Generation-time RNG for shareable song seeds. Wraps a SplitMix64 instance
//  in a TaskLocal so any code path running inside the install scope (see
//  `SongDocument.play(seedString:)`) draws from the same deterministic stream.
//
//  Outside the install scope, the default box wraps `SystemRandomNumberGenerator`
//  so existing call sites that haven't been swept yet — and any future ones —
//  produce non-deterministic output, matching pre-seed behavior.
//
//  IMPORTANT: this is a generation-time mechanism only. Render-thread random
//  consumers (`ArrowRandom`, `NoiseSmoothStep`, `ArrowExponentialRandom`) own
//  their own per-node `Xorshift128Plus` state, seeded at compile time via
//  `Arrow11.applyRandomSeed`. They do NOT use `SongRNG`.
//
//  Concurrency: the install site runs the entire generation pipeline as a
//  sequential chain of awaits inside one Task. The single `SongRNGBox` is
//  touched from one thread at a time. If parallelism is added later (async let,
//  TaskGroup), each child task must own a split sub-seed via
//  `SplitMix64(seed: SongRNG.box.rng.next())` and install it in its own
//  `withValue` block, otherwise the box races and reproducibility breaks.
//

import Foundation

final class SongRNGBox: @unchecked Sendable {
  // SAFETY: this box holds a mutable PRNG state. It is `@unchecked Sendable`
  // because the project's install pattern guarantees no two concurrent tasks
  // ever share the *same* box mutably:
  //
  //   1. SongDocument.play() installs an outer box for the sequential
  //      compile pipeline. That pipeline does not fan out into a TaskGroup
  //      or async let, so only one thread touches the outer box.
  //   2. MusicPattern.play() does fan out into a TaskGroup, but each child
  //      task installs its OWN fresh box via `SongRNG.$box.withValue(...)`
  //      before drawing. The TaskLocal binding shadows the parent box for
  //      the duration of the child task.
  //
  // If you ever add code that calls SongRNG.* from multiple concurrent tasks
  // *without* installing a fresh per-task box first, you have a data race.
  // The compiler cannot enforce this rule, so the @unchecked is load-bearing.
  var rng: any RandomNumberGenerator

  init(_ rng: any RandomNumberGenerator) {
    self.rng = rng
  }
}

enum SongRNG {
  @TaskLocal static var box: SongRNGBox = SongRNGBox(SystemRandomNumberGenerator())

  static func float(in range: ClosedRange<CoreFloat>) -> CoreFloat {
    .random(in: range, using: &box.rng)
  }

  static func int(in range: ClosedRange<Int>) -> Int {
    .random(in: range, using: &box.rng)
  }

  static func intExclusive(in range: Range<Int>) -> Int {
    .random(in: range, using: &box.rng)
  }

  static func double(in range: ClosedRange<Double>) -> Double {
    .random(in: range, using: &box.rng)
  }

  static func pick<C: Collection>(_ collection: C) -> C.Element? {
    collection.randomElement(using: &box.rng)
  }

  static func shuffle<T>(_ array: inout [T]) {
    array.shuffle(using: &box.rng)
  }

  static func shuffled<T>(_ array: [T]) -> [T] {
    array.shuffled(using: &box.rng)
  }
}
