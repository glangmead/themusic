//
//  Performer.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation
import AVFAudio
import os

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

/// Thread-safe voice allocator. All mutable state is protected by an
/// OSAllocatedUnfairLock so callers can use it synchronously from any
/// thread (MIDI callbacks, audio render thread, main thread).
final class VoiceLedger: @unchecked Sendable {
  private struct State {
    var noteOnnedVoiceIdxs: Set<Int>
    var availableVoiceIdxs: Set<Int>
    var indexQueue: [Int]
    var noteToVoiceIdx: [MidiValue: Int]
  }
  
  private let lock: OSAllocatedUnfairLock<State>
  
  init(voiceCount: Int) {
    let initialState = State(
      noteOnnedVoiceIdxs: Set<Int>(),
      availableVoiceIdxs: Set(0..<voiceCount),
      indexQueue: Array(0..<voiceCount),
      noteToVoiceIdx: [:]
    )
    self.lock = OSAllocatedUnfairLock(initialState: initialState)
  }
  
  /// Read the current note-to-voice mapping (for tests/diagnostics).
  var noteToVoiceIdx: [MidiValue: Int] {
    lock.withLock { $0.noteToVoiceIdx }
  }
  
  func takeAvailableVoice(_ note: MidiValue) -> Int? {
    lock.withLock { state in
      if let availableIdx = state.indexQueue.first(where: {
        state.availableVoiceIdxs.contains($0)
      }) {
        state.availableVoiceIdxs.remove(availableIdx)
        state.noteOnnedVoiceIdxs.insert(availableIdx)
        state.noteToVoiceIdx[note] = availableIdx
        state.indexQueue.removeAll(where: { $0 == availableIdx })
        return availableIdx
      }
      return nil
    }
  }
  
  func voiceIndex(for note: MidiValue) -> Int? {
    lock.withLock { state in
      state.noteToVoiceIdx[note]
    }
  }
  
  func releaseVoice(_ note: MidiValue) -> Int? {
    lock.withLock { state in
      if let voiceIdx = state.noteToVoiceIdx[note] {
        state.noteOnnedVoiceIdxs.remove(voiceIdx)
        state.availableVoiceIdxs.insert(voiceIdx)
        state.noteToVoiceIdx.removeValue(forKey: note)
        state.indexQueue.append(voiceIdx)
        return voiceIdx
      }
      return nil
    }
  }
}



