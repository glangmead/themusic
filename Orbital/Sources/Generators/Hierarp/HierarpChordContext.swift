//
//  HierarpChordContext.swift
//  Orbital
//
//  Small protocol abstracting chord lookup by beat, so embellishers can
//  query harmonic state without depending on a full HarmonyTimeline.
//  Lets tests and previews hand in a one-line stub.
//

import Foundation
import Tonic

protocol HierarpChordContext {
  /// The (key, chord) pair active at the given absolute beat.
  func state(at beat: Double) -> (key: Key, chord: ChordInScale)
}

/// Adapter so HarmonyTimeline can be passed wherever HierarpChordContext is
/// expected. Embeds the loop flag chosen at construction time.
struct HierarpTimelineContext: HierarpChordContext {
  let timeline: HarmonyTimeline
  let loop: Bool

  func state(at beat: Double) -> (key: Key, chord: ChordInScale) {
    timeline.state(at: beat, loop: loop)
  }
}
