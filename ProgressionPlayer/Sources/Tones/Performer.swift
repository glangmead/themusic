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

protocol NoteHandler: AnyObject {
  func noteOn(_ note: MidiNote)
  func noteOff(_ note: MidiNote)
  func notesOn(_ notes: [MidiNote])
  func notesOff(_ notes: [MidiNote])
  var globalOffset: Int { get set }
  func applyOffset(note: UInt8) -> UInt8
  var handles: ArrowWithHandles? { get }
}

extension NoteHandler {
  func notesOn(_ notes: [MidiNote]) {
    for note in notes { noteOn(note) }
  }
  func notesOff(_ notes: [MidiNote]) {
    for note in notes { noteOff(note) }
  }
  var handles: ArrowWithHandles? { nil }
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
    print("No voice available in this ledger")
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



