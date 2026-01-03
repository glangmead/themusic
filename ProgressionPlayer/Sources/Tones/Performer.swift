//
//  Performer.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation

/// Taking data such as a MIDI note and driving an oscillator, filter, and amp envelope to emit something in particular.

typealias MidiValue = UInt8

struct MidiNote {
  let note: MidiValue
  let velocity: MidiValue
  var freq: CoreFloat {
    440.0 * pow(2.0, (CoreFloat(note) - 69.0) / 12.0)
  }
}

class EnvelopeHandlePlayer: Arrow11, NoteHandler {
  var arrow: ArrowWithHandles
  init(arrow: ArrowWithHandles) {
    self.arrow = arrow
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    arrow.of(t)
  }
  func noteOn(_ note: MidiNote) {
    for key in arrow.namedADSREnvelopes.keys {
      arrow.namedADSREnvelopes[key]!.noteOn(note)
    }
    if arrow.namedConsts["freq"] != nil {
      for const in arrow.namedConsts["freq"]! {
        const.val = note.freq
      }
    }
  }
  
  func noteOff(_ note: MidiNote) {
    for key in arrow.namedADSREnvelopes.keys {
      arrow.namedADSREnvelopes[key]!.noteOff(note)
    }
  }
}

protocol NoteHandler: AnyObject {
  func noteOn(_ note: MidiNote)
  func noteOff(_ note: MidiNote)
}

// Have a collection of note-handling arrows, which we sum as our output.
// Allocate noteOn among the voices somehow.
class PoolVoice: Arrow11, NoteHandler {
  // the voices, their count, and their sum arrow
  private let voices: [Arrow11 & NoteHandler]
  private let voiceCount: Int
  private let sumSource: Arrow11
  
  // treating voices as a pool of resources
  private var noteOnnedVoiceIdxs: Set<Int>
  private var availableVoiceIdxs: Set<Int>
  var noteToVoiceIdx: [MidiValue: Int]
  
  init(voices: [Arrow11 & NoteHandler]) {
    self.voices = voices
    self.voiceCount = voices.count
    self.sumSource = ArrowSum(voices)
    
    // mark all voices as available
    availableVoiceIdxs = Set(0..<voices.count)
    noteOnnedVoiceIdxs = Set<Int>()
    noteToVoiceIdx = [:]
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    sumSource.of(t)
  }
  
  private func takeAvailableVoice(_ note: MidiValue) -> NoteHandler? {
    if let availableIdx = (0..<voiceCount).first(where: {
      availableVoiceIdxs.contains($0)
    }) {
      availableVoiceIdxs.remove(availableIdx)
      noteOnnedVoiceIdxs.insert(availableIdx)
      noteToVoiceIdx[note] = availableIdx
      //print(" ON: note \(note) using voice \(availableIdx) from pool")
      return voices[availableIdx]
    }
    return nil
  }
  
  func noteOn(_ noteVel: MidiNote) {
    //print(" ON: trying \(noteVel.note)")
    // case 1: this note is being played by a voice already: send noteOff then noteOn to re-up it
    if let voiceIdx = noteToVoiceIdx[noteVel.note] {
      voices[voiceIdx].noteOff(noteVel)
      voices[voiceIdx].noteOn(noteVel)
    // case 2: assign a fresh voice to the note
    } else if let handler = takeAvailableVoice(noteVel.note) {
      handler.noteOn(noteVel)
    }
  }
  
  func noteOff(_ noteVel: MidiNote) {
    //print("OFF: trying \(noteVel.note)")
    if let voiceIdx = noteToVoiceIdx[noteVel.note] {
      //print("OFF: note \(noteVel.note) releasing voice \(voiceIdx)")
      voices[voiceIdx].noteOff(noteVel)
      noteOnnedVoiceIdxs.remove(voiceIdx)
      availableVoiceIdxs.insert(voiceIdx)
    }
  }
}

class SimpleVoice: Arrow11, NoteHandler {
  var oscillator: HasFactor & Arrow11
  var filteredOsc: LowPassFilter
  let ampMod: NoteHandler & Arrow11
  let filterMod: NoteHandler & Arrow11
  var amplitude: CoreFloat = 0.0 // Controls the current loudness of the voice
  
  init(oscillator: HasFactor & Arrow11, ampMod: NoteHandler & Arrow11, filterMod: NoteHandler & Arrow11) {
    self.oscillator = oscillator
    self.ampMod = ampMod
    self.filterMod = filterMod
    self.filteredOsc = LowPassFilter(of: oscillator, cutoff: filterMod.of(0), resonance: 0)
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    // If the amplitude is zero, the voice is effectively off, so we return silence.
    guard amplitude > 0.0 else {
      return 0.0
    }
    // update the filter with the filterMod envelope's current value
    filteredOsc.factor = filterMod.of(t)
    // get the tone
    let rawOscillatorSample = filteredOsc.of(t)
    // get the amplitude
    let ampEnv = ampMod.of(t)
    return amplitude * ampEnv * rawOscillatorSample
  }
  
  func noteOn(_ note: MidiNote) {
    // Map the MIDI velocity (0-127) to an amplitude (0.0-1.0)
    self.amplitude = CoreFloat(note.velocity) / 127.0
    oscillator.factor = note.freq
    ampMod.noteOn(note)
    filterMod.noteOn(note)
  }
  
  func noteOff(_ note: MidiNote) {
    // For this simple voice, turning the note off means setting amplitude to zero,
    // effectively silencing the sound instantly.
    ampMod.noteOff(note)
    filterMod.noteOff(note)
  }
}

