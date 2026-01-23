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
  let synth: SyntacticSynth
  let notes: [MidiNote]
  let duration: CoreFloat // time between noteOn and noteOff in seconds
  
  func play() async throws {
    notes.forEach { synth.poolVoice?.noteOn($0) }
    do {
      try await Task.sleep(for: .seconds(duration))
    } catch {
      
    }
    notes.forEach { synth.poolVoice?.noteOff($0) }
  }
  
  func cancel() {
    notes.forEach { synth.poolVoice?.noteOff($0) }
  }
}

// the ingredients for generating music events
actor MusicPattern {
  var synth: SyntacticSynth
  var modulators: [String: Arrow11] // modulates constants in the preset
  var notes: any IteratorProtocol<[MidiNote]> // a sequence of chords
  var durations: any IteratorProtocol<CoreFloat> // a sequence of durations
  
  init(synth: SyntacticSynth, modulators: [String : Arrow11], notes: any IteratorProtocol<[MidiNote]>, durations: any IteratorProtocol<CoreFloat>) {
    self.synth = synth
    self.modulators = modulators
    self.notes = notes
    self.durations = durations
  }
  
  func next() -> MusicEvent? {
    guard let note = notes.next() else { return nil }
    guard let duration = durations.next() else { return nil }
    modulateSound()
    return MusicEvent(
      synth: synth,
      notes: note,
      duration: duration
    )
  }
  
  func play() async {
    while let event = next(), !Task.isCancelled {
      do {
        try await event.play()
      } catch {
        
      }
    }
  }
  
  func modulateSound() {
    let tone = synth.poolVoice
    let now = Date.now.timeIntervalSince1970
    for (key, modulatingArrow) in modulators {
      if tone?.namedConsts[key] != nil {
        for arrowConst in tone!.namedConsts[key]! {
          arrowConst.val = modulatingArrow.of(now)
        }
      }
    }
  }
}

// then we need a builder and JSON format for a MusicPattern
