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

  /// The result of a voice allocation attempt.
  struct VoiceAllocation {
    let voiceIdx: Int
    /// True only for tier-3: a sustaining (noteOnned) voice was stolen.
    /// Callers should treat this as a retrigger and not increment activeNoteCount.
    let wasNoteOnnedSteal: Bool
  }

  /// Full allocation result — use this when the caller needs to distinguish tier-3 steals.
  func takeAvailableVoiceAllocation(_ note: MidiValue) -> VoiceAllocation? {
    lock.withLock { state in
      // Helper: move a voice to the back of indexQueue (marks it as most recently activated).
      func activate(_ idx: Int) {
        state.indexQueue.removeAll(where: { $0 == idx })
        state.indexQueue.append(idx)
      }

      // Tier 1: Prefer a genuinely available voice (oldest first via indexQueue).
      if let availableIdx = state.indexQueue.first(where: {
        state.availableVoiceIdxs.contains($0)
      }) {
        state.availableVoiceIdxs.remove(availableIdx)
        state.noteOnnedVoiceIdxs.insert(availableIdx)
        state.noteToVoiceIdx[note] = availableIdx
        activate(availableIdx)
        return VoiceAllocation(voiceIdx: availableIdx, wasNoteOnnedSteal: false)
      }

      // Tier 2: Steal a releasing voice (already fading out, least audible impact).
      // The new noteOn picks up from the current envelope level — no click.
      // Any pending finishRelease callbacks become no-ops because the voice
      // is removed from releasingVoiceIdxs before they fire.
      if let releasingIdx = state.indexQueue.first(where: {
        state.releasingVoiceIdxs.contains($0)
      }) {
        state.releasingVoiceIdxs.remove(releasingIdx)
        state.noteOnnedVoiceIdxs.insert(releasingIdx)
        state.noteToVoiceIdx[note] = releasingIdx
        activate(releasingIdx)
        return VoiceAllocation(voiceIdx: releasingIdx, wasNoteOnnedSteal: false)
      }

      // Tier 3: Steal the oldest noteOnned voice (front of indexQueue).
      // The new noteOn picks up from the current envelope level — no click.
      // The old note's pending noteOff becomes a no-op because its
      // noteToVoiceIdx entry is evicted here.
      if let oldestIdx = state.indexQueue.first(where: {
        state.noteOnnedVoiceIdxs.contains($0)
      }) {
        // Evict the old note's mapping for this voice.
        if let oldNote = state.noteToVoiceIdx.first(where: { $0.value == oldestIdx })?.key {
          state.noteToVoiceIdx.removeValue(forKey: oldNote)
        }
        state.noteToVoiceIdx[note] = oldestIdx
        // noteOnnedVoiceIdxs unchanged — voice is still noteOnned, now for the new note.
        activate(oldestIdx)
        return VoiceAllocation(voiceIdx: oldestIdx, wasNoteOnnedSteal: true)
      }

      return nil
    }
  }

  /// Convenience wrapper — use when only the voice index is needed.
  func takeAvailableVoice(_ note: MidiValue) -> Int? {
    takeAvailableVoiceAllocation(note)?.voiceIdx
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
      // Voice remains in indexQueue at its current position (representing its age
      // relative to when it was last noteOnned — oldest available stays near the front).
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
        // Voice remains in indexQueue at its current position.
        return voiceIdx
      }
      return nil
    }
  }
}
