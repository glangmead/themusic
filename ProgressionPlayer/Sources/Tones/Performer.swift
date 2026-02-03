//
//  Performer.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation
import AVFAudio

/// Taking data such as a MIDI note and driving an oscillator, filter, and amp envelope to emit something in particular.

typealias MidiValue = UInt8

struct MidiNote {
  let note: MidiValue
  let velocity: MidiValue
  var freq: CoreFloat {
    440.0 * pow(2.0, (CoreFloat(note) - 69.0) / 12.0)
  }
}

// player of a single synthesized voice, via its envelope
final class EnvelopeHandlePlayer: ArrowWithHandles, NoteHandler {
  var arrow: ArrowWithHandles
  var globalOffset: Int  = 0
  init(arrow: ArrowWithHandles) {
    self.arrow = arrow
    super.init(arrow)
    let _ = withMergeDictsFromArrow(arrow)
  }
  
  func noteOn(_ note: MidiNote) {
    for key in arrow.namedADSREnvelopes.keys {
      for env in arrow.namedADSREnvelopes[key]! {
        env.noteOn(note)
      }
    }
    if arrow.namedConsts["freq"] != nil {
      for const in arrow.namedConsts["freq"]! {
        const.val = note.freq
      }
    }
  }
  
  func noteOff(_ note: MidiNote) {
    for key in arrow.namedADSREnvelopes.keys {
      for env in arrow.namedADSREnvelopes[key]! {
        env.noteOff(note)
      }
    }
  }
}

protocol NoteHandler: AnyObject {
  func noteOn(_ note: MidiNote)
  func noteOff(_ note: MidiNote)
  var globalOffset: Int { get set }
  func applyOffset(note: UInt8) -> UInt8
}

extension NoteHandler {
  func applyOffset(note: UInt8) -> UInt8 {
    var result = note
    if globalOffset < 0 {
      if -1 * globalOffset < Int(result) {
        result -= UInt8(-1 * globalOffset)
      } else {
        result = 0
      }
    } else {
      let offsetResult = Int(result) + globalOffset
      result = UInt8(clamping: offsetResult)
    }
    return result
  }
}

final class VoiceLedger {
  private let voiceCount: Int
  private var noteOnnedVoiceIdxs: Set<Int>
  private var availableVoiceIdxs: Set<Int>
  var noteToVoiceIdx: [MidiValue: Int]

  init(voiceCount: Int) {
    self.voiceCount = voiceCount
    // mark all voices as available
    availableVoiceIdxs = Set(0..<voiceCount)
    noteOnnedVoiceIdxs = Set<Int>()
    noteToVoiceIdx = [:]
  }

  func takeAvailableVoice(_ note: MidiValue) -> Int? {
    // using first(where:) on a Range ensures we pick the lowest index available
    if let availableIdx = (0..<voiceCount).first(where: {
      availableVoiceIdxs.contains($0)
    }) {
      availableVoiceIdxs.remove(availableIdx)
      noteOnnedVoiceIdxs.insert(availableIdx)
      noteToVoiceIdx[note] = availableIdx
      return availableIdx
    }
    return nil
  }
  
  func voiceIndex(for note: MidiValue) -> Int? {
    return noteToVoiceIdx[note]
  }

  func releaseVoice(_ note: MidiValue) -> Int? {
    if let voiceIdx = noteToVoiceIdx[note] {
      noteOnnedVoiceIdxs.remove(voiceIdx)
      availableVoiceIdxs.insert(voiceIdx)
      noteToVoiceIdx.removeValue(forKey: note)
      return voiceIdx
    }
    return nil
  }
}

// player of a single sampler voice, via Apple's startNote/stopNote
final class SamplerVoice: NoteHandler {
  var globalOffset: Int = 0
  let samplerNode: AVAudioUnitSampler
  
  init(node: AVAudioUnitSampler) {
    self.samplerNode = node
  }
  
  func noteOn(_ note: MidiNote) {
    let offsetNote = applyOffset(note: note.note)
    //print("samplerNode.startNote(\(offsetNote), withVelocity: \(note.velocity)")
    samplerNode.startNote(offsetNote, withVelocity: note.velocity, onChannel: 0)
  }
  
  func noteOff(_ note: MidiNote) {
    let offsetNote = applyOffset(note: note.note)
    samplerNode.stopNote(offsetNote, onChannel: 0)
  }
}

// Have a collection of note-handling arrows, which we sum as our output.
final class PolyphonicVoiceGroup: ArrowWithHandles, NoteHandler {
  var globalOffset: Int = 0
  private let voices: [NoteHandler]
  private let ledger: VoiceLedger
  
  init(presets: [Preset]) {
    if presets.isEmpty {
      self.voices = []
      self.ledger = VoiceLedger(voiceCount: 0)
      super.init(ArrowIdentity())
      return
    }
    
    if presets[0].sound != nil {
      // Arrow/Synth path
      let handles = presets.compactMap { $0.sound }.map { EnvelopeHandlePlayer(arrow: $0) }
      self.voices = handles
      self.ledger = VoiceLedger(voiceCount: handles.count)
      
      super.init(ArrowSum(innerArrs: handles))
      let _ = withMergeDictsFromArrows(handles)
    } else if let node = presets[0].samplerNode {
      // Sampler path
      let count = presets.count
      if presets.count == 1 && count > 1 {
        // Replicate the single sampler
        let handlers = (0..<count).map { _ in SamplerVoice(node: node) }
        self.voices = handlers
      } else {
        let handlers = presets.compactMap { $0.samplerNode }.map { SamplerVoice(node: $0) }
        self.voices = handlers
      }
      self.ledger = VoiceLedger(voiceCount: self.voices.count)
      // Samplers don't participate in the Arrow graph for audio signal.
      super.init(ArrowIdentity())
    } else {
      self.voices = []
      self.ledger = VoiceLedger(voiceCount: 0)
      super.init(ArrowIdentity())
    }
  }

  
  func noteOn(_ noteVelIn: MidiNote) {
    let noteVel = MidiNote(note: applyOffset(note: noteVelIn.note), velocity: noteVelIn.velocity)
    // case 1: this note is being played by a voice already: send noteOff then noteOn to re-up it
    if let voiceIdx = ledger.voiceIndex(for: noteVelIn.note) {
      voices[voiceIdx].noteOn(noteVel)
    // case 2: assign a fresh voice to the note
    } else if let voiceIdx = ledger.takeAvailableVoice(noteVelIn.note) {
      voices[voiceIdx].noteOn(noteVel)
    }
  }
  
  func noteOff(_ noteVelIn: MidiNote) {
    let noteVel = MidiNote(note: applyOffset(note: noteVelIn.note), velocity: noteVelIn.velocity)
    if let voiceIdx = ledger.releaseVoice(noteVelIn.note) {
      voices[voiceIdx].noteOff(noteVel)
    }
  }
}
