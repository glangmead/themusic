//
//  Player.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/21/26.
//

import Foundation

// This layer doesn't know about synths or sequencers, only the Sequence protocol and Arrow* classes.
// The client of MusicPattern would own concepts like beats and absolute time.
// Our job here is to own an arrow that has generators in some of its slots, and then instantiate those.

// a fully specified musical utterance to play at one point in time, a set of simultaneous noteOns
struct MusicEvent {
  let preset: Preset
  let notes: [MidiNote]
  let duration: Float
}

// the ingredients for generating music events
struct MusicPattern: Sequence, IteratorProtocol {
  var preset: Preset // a base preset sound, what Supercollider calls a SynthDef
  var modulators: [String: Arrow11] // modulates constants in the preset
  var notes: any IteratorProtocol<[MidiNote]> // a sequence of chords
  var durations: any IteratorProtocol<Float> // a sequence of durations
  
  mutating func next() -> MusicEvent? {
    guard let note = notes.next() else { return nil }
    guard let duration = durations.next() else { return nil }
    modulateSound()
    return MusicEvent(
      preset: preset,
      notes: note,
      duration: duration
    )
  }
  
  func modulateSound() {
    var tone = preset.sound
    for (key, modulatingArrow) in modulators {
      if tone.namedConsts.keys.contains(key) {
        for arrowConst in tone.namedConsts[key]! {
          arrowConst.val = modulatingArrow.of(Date.now.timeIntervalSince1970)
        }
      }
    }
  }
}

// then we need a builder and JSON format for a MusicPattern
