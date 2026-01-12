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

final class EnvelopeHandlePlayer: Arrow11, NoteHandler {
  var arrow: ArrowWithHandles
  init(arrow: ArrowWithHandles) {
    self.arrow = arrow
    super.init(innerArr: arrow)
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
final class PoolVoice: Arrow11, NoteHandler {
  // the voices, their count, and their sum arrow
  private let voices: [Arrow11 & NoteHandler]
  private let voiceCount: Int
  
  // treating voices as a pool of resources
  private var noteOnnedVoiceIdxs: Set<Int>
  private var availableVoiceIdxs: Set<Int>
  var noteToVoiceIdx: [MidiValue: Int]
  
  init(voices: [Arrow11 & NoteHandler]) {
    self.voices = voices
    self.voiceCount = voices.count
    
    // mark all voices as available
    availableVoiceIdxs = Set(0..<voices.count)
    noteOnnedVoiceIdxs = Set<Int>()
    noteToVoiceIdx = [:]
    super.init(innerArr: ArrowSum(innerArrs: voices))
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
    print(" ON: trying \(noteVel.note)")
    // case 1: this note is being played by a voice already: send noteOff then noteOn to re-up it
    if let voiceIdx = noteToVoiceIdx[noteVel.note] {
      print(" ON: restarting \(noteVel.note)")
      //voices[voiceIdx].noteOff(noteVel)
      voices[voiceIdx].noteOn(noteVel)
    // case 2: assign a fresh voice to the note
    } else if let handler = takeAvailableVoice(noteVel.note) {
      handler.noteOn(noteVel)
    }
  }
  
  func noteOff(_ noteVel: MidiNote) {
    //print("OFF: trying \(noteVel.note)")
    if let voiceIdx = noteToVoiceIdx[noteVel.note] {
      print("OFF: note \(noteVel.note) releasing voice \(voiceIdx)")
      voices[voiceIdx].noteOff(noteVel)
      noteOnnedVoiceIdxs.remove(voiceIdx)
      availableVoiceIdxs.insert(voiceIdx)
      noteToVoiceIdx.removeValue(forKey: noteVel.note)
    }
  }
}


