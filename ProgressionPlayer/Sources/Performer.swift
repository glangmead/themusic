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

class SimpleVoice: Arrow11, NoteHandler {
  private let oscillator: VariableMult
  private let filter: NoteHandler & Arrow21
  private var amplitude: Double = 0.0 // Controls the current loudness of the voice
  
  init(oscillator: VariableMult, filter: NoteHandler & Arrow21) {
    self.oscillator = oscillator
    self.filter = filter
    weak var futureSelf: SimpleVoice? = nil
    super.init(of: { time in
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

