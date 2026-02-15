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
final class PlayableArrow: ArrowWithHandles, NoteHandler {
  var arrow: ArrowWithHandles
  weak var preset: Preset?
  var globalOffset: Int  = 0
  init(arrow: ArrowWithHandles) {
    self.arrow = arrow
    super.init(arrow)
    let _ = withMergeDictsFromArrow(arrow)
  }
  
  func noteOn(_ note: MidiNote) {
    preset?.noteOn()
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
    preset?.noteOff()
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
  func notesOn(_ notes: [MidiNote])
  func notesOff(_ notes: [MidiNote])
  var globalOffset: Int { get set }
  func applyOffset(note: UInt8) -> UInt8
}

extension NoteHandler {
  func notesOn(_ notes: [MidiNote]) {
    for note in notes { noteOn(note) }
  }
  func notesOff(_ notes: [MidiNote]) {
    for note in notes { noteOff(note) }
  }
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
  private var indexQueue: [Int] // lets us control the order we reuse voices
  var noteToVoiceIdx: [MidiValue: Int]
  
  init(voiceCount: Int) {
    self.voiceCount = voiceCount
    // mark all voices as available
    availableVoiceIdxs = Set(0..<voiceCount)
    noteOnnedVoiceIdxs = Set<Int>()
    noteToVoiceIdx = [:]
    indexQueue = Array(0..<voiceCount)
  }
  
  func takeAvailableVoice(_ note: MidiValue) -> Int? {
    // using first(where:) on a Range ensures we pick the lowest index available
    if let availableIdx = indexQueue.first(where: {
      availableVoiceIdxs.contains($0)
    }) {
      availableVoiceIdxs.remove(availableIdx)
      noteOnnedVoiceIdxs.insert(availableIdx)
      noteToVoiceIdx[note] = availableIdx
      // we'll re-insert this index at the end of the array when returned
      indexQueue.removeAll(where: {$0 == availableIdx})
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
      indexQueue.append(voiceIdx)
      return voiceIdx
    }
    return nil
  }
}

// player of a sampler voice, via Apple's startNote/stopNote
// Inherently polyphonic since AVAudioUnitSampler handles multiple simultaneous notes.
final class PlayableSampler: NoteHandler {
  var globalOffset: Int = 0
  weak var preset: Preset?
  let sampler: Sampler
  
  init(sampler: Sampler) {
    self.sampler = sampler
  }
  
  func noteOn(_ note: MidiNote) {
    preset?.noteOn()
    let offsetNote = applyOffset(note: note.note)
    sampler.node.startNote(offsetNote, withVelocity: note.velocity, onChannel: 0)
  }
  
  func noteOff(_ note: MidiNote) {
    preset?.noteOff()
    let offsetNote = applyOffset(note: note.note)
    sampler.node.stopNote(offsetNote, onChannel: 0)
  }
}

// A pool of PlayableArrow voices for polyphonic Arrow-based synthesis.
// Uses VoiceLedger for note-to-voice allocation.
final class PolyphonicArrowPool: ArrowWithHandles, NoteHandler {
  var globalOffset: Int = 0
  private let voices: [PlayableArrow]
  private let ledger: VoiceLedger
  
  init(presets: [Preset]) {
    let handles = presets.compactMap { preset -> PlayableArrow? in
      guard let sound = preset.sound else { return nil }
      let player = PlayableArrow(arrow: sound)
      player.preset = preset
      return player
    }
    self.voices = handles
    self.ledger = VoiceLedger(voiceCount: handles.count)
    
    if handles.isEmpty {
      super.init(ArrowIdentity())
    } else {
      super.init(ArrowSum(innerArrs: handles))
      let _ = withMergeDictsFromArrows(handles)
    }
  }
  
  func noteOn(_ noteVelIn: MidiNote) {
    let noteVel = MidiNote(note: applyOffset(note: noteVelIn.note), velocity: noteVelIn.velocity)
    // case 1: this note is being played by a voice already: re-trigger it
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
// Sampler is inherently polyphonic, so the "pool" is just the PlayableSampler itself.
typealias PolyphonicSamplerPool = PlayableSampler

