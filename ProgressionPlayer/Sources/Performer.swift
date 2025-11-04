//
//  Performer.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation

/// Taking data such as a MIDI note and driving a Preset to emit something in particular.

typealias MidiValue = UInt8

struct MidiNote {
  let note: MidiValue
  let velocity: MidiValue
}

protocol NoteHandler {
  func noteOn(_ note: MidiNote)
  func noteOff(_ note: MidiNote)
}

// Have a collection of note-handling arrows, which we sum as our output.
// Allocate noteOn among the voices somehow.
class PolyVoice: Arrow11, NoteHandler {
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
    self.sumSource = arrowSum(voices)
    
    // mark all voices as available
    availableVoiceIdxs = Set(0..<voices.count)
    noteOnnedVoiceIdxs = Set<Int>()
    noteToVoiceIdx = [:]
    
    weak var futureSelf: PolyVoice? = nil
    super.init(id: "PolyVoice", of: { time in
      futureSelf!.sumSource.of(time)
    })
    futureSelf = self
  }
  
  private func takeAvailableVoice(_ note: MidiValue) -> NoteHandler? {
    if let availableIdx = (0..<voiceCount).first(where: {
      availableVoiceIdxs.contains($0)
    }) {
      availableVoiceIdxs.remove(availableIdx)
      noteOnnedVoiceIdxs.insert(availableIdx)
      noteToVoiceIdx[note] = availableIdx
      return voices[availableIdx]
    }
    return nil
  }
  
  func noteOn(_ noteVel: MidiNote) {
    takeAvailableVoice(noteVel.note)?.noteOn(noteVel)
  }
  
  func noteOff(_ noteVel: MidiNote) {
    if let voiceIdx = noteToVoiceIdx[noteVel.note] {
      voices[voiceIdx].noteOff(noteVel)
      noteOnnedVoiceIdxs.remove(voiceIdx)
      availableVoiceIdxs.insert(voiceIdx)
    }
  }
}

class SimpleVoice: Arrow11, NoteHandler {
  var oscillator: HasFactor & Arrow11
  let filter: NoteHandler & Arrow21
  var amplitude: Double = 0.0 // Controls the current loudness of the voice
  
  init(oscillator: HasFactor & Arrow11, filter: NoteHandler & Arrow21) {
    self.oscillator = oscillator
    self.filter = filter
    weak var futureSelf: SimpleVoice? = nil
    super.init(id: "SimpleVoice", of: { time in
      // If the amplitude is zero, the voice is effectively off, so we return silence.
      guard futureSelf!.amplitude > 0.0 else {
        return 0.0
      }
      let rawOscillatorSample = oscillator.of(time)
      let envelopedSample = filter.of(rawOscillatorSample, time)
      return futureSelf!.amplitude * envelopedSample
    })
    futureSelf = self
    
  }
  
  func noteOn(_ note: MidiNote) {
    // Map the MIDI velocity (0-127) to an amplitude (0.0-1.0)
    self.amplitude = Double(note.velocity) / 127.0
    
    // Calculate the frequency for the given MIDI note number
    let freq = 440.0 * pow(2.0, (Double(note.note) - 69.0) / 12.0)
    
    // Set the oscillator's frequency to produce the correct pitch
    //print("\(freq)")
    oscillator.factor = freq
    filter.noteOn(note)
  }
  
  func noteOff(_ note: MidiNote) {
    // For this simple voice, turning the note off means setting amplitude to zero,
    // effectively silencing the sound instantly.
    filter.noteOff(note)
  }
}

