//
//  Performer.swift
//  Orbital
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation
import AVFAudio
import os

/// Taking data such as a MIDI note and driving an oscillator, filter, and amp envelope to emit something in particular.

typealias MidiValue = UInt8

struct MidiNote: Sendable {
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
///
/// Voices move through three states:
///   available → noteOnned → releasing → available
///
/// The "releasing" state keeps the voice unavailable for new notes while
/// the amplitude envelope completes its release phase, preventing volume
/// jumps from interrupted releases.
///
/// If envelopes are registered via `registerEnvelopes(forVoice:envelopes:)`,
/// `beginRelease` automatically appends finish callbacks on them and calls
/// `finishRelease` when all envelopes for that voice have closed. Callers
/// don't need to manage the callback plumbing themselves.
final class VoiceLedger: @unchecked Sendable {
  private struct State {
    var noteOnnedVoiceIdxs: Set<Int>
    var releasingVoiceIdxs: Set<Int>
    var availableVoiceIdxs: Set<Int>
    var indexQueue: [Int]
    var noteToVoiceIdx: [MidiValue: Int]
  }
  
  private let lock: OSAllocatedUnfairLock<State>
  
  /// Envelopes per voice index. When set, `beginRelease` installs
  /// `releaseDidComplete` callbacks that auto-call `finishRelease`.
  private var voiceEnvelopes: [Int: [ADSR]] = [:]
  
  init(voiceCount: Int) {
    let initialState = State(
      noteOnnedVoiceIdxs: Set<Int>(),
      releasingVoiceIdxs: Set<Int>(),
      availableVoiceIdxs: Set(0..<voiceCount),
      indexQueue: Array(0..<voiceCount),
      noteToVoiceIdx: [:]
    )
    self.lock = OSAllocatedUnfairLock(initialState: initialState)
  }
  
  /// Register the amplitude envelopes for a voice so that `beginRelease`
  /// can append finish callbacks that automatically call `finishRelease`
  /// when all envelopes close.
  func registerEnvelopes(forVoice voiceIndex: Int, envelopes: [ADSR]) {
    voiceEnvelopes[voiceIndex] = envelopes
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
  
  /// Begin releasing a voice: moves it from noteOnned to releasing.
  /// The voice is no longer mapped to the note (so the same MIDI note
  /// can be played again on a different voice) but is NOT yet available
  /// for arbitrary new notes.
  ///
  /// If envelopes were registered for this voice, appends
  /// finish callbacks that automatically call `finishRelease`
  /// when all envelopes have closed.
  /// Otherwise the caller must call `finishRelease(voiceIndex:)` manually.
  func beginRelease(_ note: MidiValue) -> Int? {
    let voiceIdx: Int? = lock.withLock { state in
      if let idx = state.noteToVoiceIdx[note] {
        state.noteOnnedVoiceIdxs.remove(idx)
        state.releasingVoiceIdxs.insert(idx)
        state.noteToVoiceIdx.removeValue(forKey: note)
        return idx
      }
      return nil
    }
    
    // Install auto-finish callbacks if envelopes are registered
    if let voiceIdx, let envelopes = voiceEnvelopes[voiceIdx], !envelopes.isEmpty {
      for env in envelopes {
        env.finishCallbacks.append { [weak self] in
          guard let self else { return }
          // Check if ALL envelopes for this voice are now closed
          if let envs = self.voiceEnvelopes[voiceIdx],
             envs.allSatisfy({ $0.state == .closed }) {
            self.finishRelease(voiceIndex: voiceIdx)
          }
        }
      }
    }
    
    return voiceIdx
  }
  
  /// Finish releasing a voice: moves it from releasing to available.
  /// Called automatically by envelope callbacks if envelopes were
  /// registered, or manually by the caller otherwise.
  func finishRelease(voiceIndex: Int) {
    lock.withLock { state in
      // Guard against double-finish (e.g. multiple envelopes both triggering)
      guard state.releasingVoiceIdxs.contains(voiceIndex) else { return }
      state.releasingVoiceIdxs.remove(voiceIndex)
      state.availableVoiceIdxs.insert(voiceIndex)
      state.indexQueue.append(voiceIndex)
    }
  }
  
  /// Immediate release: moves a voice directly from noteOnned to available.
  /// Used for sampler-based presets where the sampler handles its own release.
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



