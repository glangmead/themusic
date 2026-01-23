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
  let sustain: CoreFloat // time between noteOn and noteOff in seconds
  let gap: CoreFloat // time reserved for this event, before next event is played
  
  func play() async throws {
    notes.forEach { synth.poolVoice?.noteOn($0) }
    do {
      try await Task.sleep(for: .seconds(sustain))
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
  var sustains: any IteratorProtocol<CoreFloat> // a sequence of sustain lengths
  var gaps: any IteratorProtocol<CoreFloat> // a sequence of sustain lengths

  init(
    synth: SyntacticSynth,
    modulators: [String : Arrow11],
    notes: any IteratorProtocol<[MidiNote]>,
    sustains: any IteratorProtocol<CoreFloat>,
    gaps: any IteratorProtocol<CoreFloat>
  ){
    self.synth = synth
    self.modulators = modulators
    self.notes = notes
    self.sustains = sustains
    self.gaps = gaps
  }
  
  func next() -> MusicEvent? {
    guard let note = notes.next() else { return nil }
    guard let sustain = sustains.next() else { return nil }
    guard let gap = gaps.next() else { return nil }
    modulateSound()
    return MusicEvent(
      synth: synth,
      notes: note,
      sustain: sustain,
      gap: gap
    )
  }
  
  func play() async {
    while let event = next(), !Task.isCancelled {
      do {
        try await event.play()
        try await Task.sleep(for: .seconds(event.gap))
      } catch { }
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
