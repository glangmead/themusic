//
//  NoteHandlingTests.swift
//  ProgressionPlayerTests
//
//  Phase 2: Note handling tests — VoiceLedger unit tests, Preset noteOn/noteOff logic tests
//

import Testing
import Foundation
@testable import ProgressionPlayer

// MARK: - VoiceLedger Tests

@Suite("VoiceLedger", .serialized)
struct VoiceLedgerTests {

  @Test("Allocate a voice and retrieve its index")
  func allocateAndRetrieve() {
    let ledger = VoiceLedger(voiceCount: 4)
    let idx = ledger.takeAvailableVoice(60)
    #expect(idx != nil, "Should allocate a voice")
    #expect(ledger.voiceIndex(for: 60) == idx, "Should retrieve the same index")
  }

  @Test("Allocate returns lowest available index first")
  func lowestIndexFirst() {
    let ledger = VoiceLedger(voiceCount: 4)
    let first = ledger.takeAvailableVoice(60)
    let second = ledger.takeAvailableVoice(62)
    let third = ledger.takeAvailableVoice(64)
    #expect(first == 0)
    #expect(second == 1)
    #expect(third == 2)
  }

  @Test("Release makes a voice available again")
  func releaseAndReuse() {
    let ledger = VoiceLedger(voiceCount: 2)
    let _ = ledger.takeAvailableVoice(60) // takes index 0
    let _ = ledger.takeAvailableVoice(62) // takes index 1

    // Full — next allocation should fail
    let overflow = ledger.takeAvailableVoice(64)
    #expect(overflow == nil, "Should be full")

    // Release note 60 (index 0)
    let released = ledger.releaseVoice(60)
    #expect(released == 0, "Should release index 0")

    // Now we can allocate again
    let reused = ledger.takeAvailableVoice(64)
    #expect(reused == 0, "Should reuse released index 0")
  }

  @Test("Released voices go to end of reuse queue")
  func reuseOrdering() {
    let ledger = VoiceLedger(voiceCount: 3)
    let _ = ledger.takeAvailableVoice(60) // index 0
    let _ = ledger.takeAvailableVoice(62) // index 1
    let _ = ledger.takeAvailableVoice(64) // index 2

    // Release 0, then 2
    let _ = ledger.releaseVoice(60)
    let _ = ledger.releaseVoice(64)

    // Next allocation should get 0 first (released first → appended first)
    let first = ledger.takeAvailableVoice(65)
    let second = ledger.takeAvailableVoice(67)
    #expect(first == 0, "Should reuse index 0 first (released earlier)")
    #expect(second == 2, "Should reuse index 2 second")
  }

  @Test("Returns nil when all voices are exhausted")
  func exhaustion() {
    let ledger = VoiceLedger(voiceCount: 2)
    let a = ledger.takeAvailableVoice(60)
    let b = ledger.takeAvailableVoice(62)
    let c = ledger.takeAvailableVoice(64)
    #expect(a != nil)
    #expect(b != nil)
    #expect(c == nil, "Third allocation should fail with 2 voices")
  }

  @Test("voiceIndex returns nil for untracked note")
  func untrackedNote() {
    let ledger = VoiceLedger(voiceCount: 4)
    #expect(ledger.voiceIndex(for: 60) == nil)
  }

  @Test("releaseVoice returns nil for untracked note")
  func releaseUntracked() {
    let ledger = VoiceLedger(voiceCount: 4)
    #expect(ledger.releaseVoice(60) == nil)
  }

  @Test("Same note can be allocated after release")
  func reallocateSameNote() {
    let ledger = VoiceLedger(voiceCount: 2)
    let idx1 = ledger.takeAvailableVoice(60)
    let _ = ledger.releaseVoice(60)
    let idx2 = ledger.takeAvailableVoice(60)
    #expect(idx1 != nil)
    #expect(idx2 != nil)
    // After release+realloc, the note→voice mapping should be restored
    #expect(ledger.voiceIndex(for: 60) == idx2)
  }

  @Test("Multiple notes map to distinct voice indices")
  func distinctVoices() {
    let ledger = VoiceLedger(voiceCount: 12)
    var indices = Set<Int>()
    for note: MidiValue in 60...71 {
      if let idx = ledger.takeAvailableVoice(note) {
        indices.insert(idx)
      }
    }
    #expect(indices.count == 12, "12 notes should get 12 distinct voices")
  }
}

// MARK: - Preset NoteOn/NoteOff Tests (Arrow path)

/// A minimal ArrowSyntax that produces: freq * t -> sine osc, with ampEnv envelope.
/// This matches the structure of real presets: an ampEnv ADSR and a freq const.
private let testArrowSyntax: ArrowSyntax = .compose(arrows: [
  .prod(of: [
    .envelope(name: "ampEnv", attack: 0.01, decay: 0.01, sustain: 1.0, release: 0.1, scale: 1.0),
    .compose(arrows: [
      .prod(of: [.const(name: "freq", val: 440), .identity]),
      .osc(name: "osc", shape: .sine, width: .const(name: "w", val: 1))
    ])
  ])
])

@Suite("Preset NoteOn/NoteOff", .serialized)
struct PresetNoteOnOffTests {

  /// Create a Preset without AVFoundation effects for testing.
  private func makeTestPreset(numVoices: Int = 4) -> Preset {
    Preset(arrowSyntax: testArrowSyntax, numVoices: numVoices, initEffects: false)
  }

  @Test("noteOn increments activeNoteCount")
  func noteOnIncrementsCount() {
    let preset = makeTestPreset()
    #expect(preset.activeNoteCount == 0)
    preset.noteOn(MidiNote(note: 60, velocity: 127))
    #expect(preset.activeNoteCount == 1)
    preset.noteOn(MidiNote(note: 64, velocity: 127))
    #expect(preset.activeNoteCount == 2)
  }

  @Test("noteOff decrements activeNoteCount")
  func noteOffDecrementsCount() {
    let preset = makeTestPreset()
    preset.noteOn(MidiNote(note: 60, velocity: 127))
    preset.noteOn(MidiNote(note: 64, velocity: 127))
    #expect(preset.activeNoteCount == 2)
    preset.noteOff(MidiNote(note: 60, velocity: 0))
    #expect(preset.activeNoteCount == 1)
    preset.noteOff(MidiNote(note: 64, velocity: 0))
    #expect(preset.activeNoteCount == 0)
  }

  @Test("noteOff for unplayed note does not change count")
  func noteOffUnplayedNote() {
    let preset = makeTestPreset()
    preset.noteOn(MidiNote(note: 60, velocity: 127))
    preset.noteOff(MidiNote(note: 72, velocity: 0)) // never played
    #expect(preset.activeNoteCount == 1, "Should still be 1")
  }

  @Test("noteOn sets freq consts on the allocated voice")
  func noteOnSetsFreq() {
    let preset = makeTestPreset(numVoices: 4)
    let note60 = MidiNote(note: 60, velocity: 127)
    preset.noteOn(note60)

    // Voice 0 should have its freq const set to note 60's frequency
    let voice0 = preset.voices[0]
    let freqConsts = voice0.namedConsts["freq"]!
    for c in freqConsts {
      #expect(abs(c.val - note60.freq) < 0.001,
              "Voice 0 freq should be \(note60.freq), got \(c.val)")
    }
  }

  @Test("noteOn triggers ADSR envelopes on the allocated voice")
  func noteOnTriggersADSR() {
    let preset = makeTestPreset(numVoices: 4)
    preset.noteOn(MidiNote(note: 60, velocity: 127))

    // Voice 0's ampEnv should be in attack state
    let voice0 = preset.voices[0]
    let ampEnvs = voice0.namedADSREnvelopes["ampEnv"]!
    for env in ampEnvs {
      #expect(env.state == .attack, "ADSR should be in attack after noteOn, got \(env.state)")
    }
  }

  @Test("noteOff puts ADSR into release state")
  func noteOffReleasesADSR() {
    let preset = makeTestPreset(numVoices: 4)
    preset.noteOn(MidiNote(note: 60, velocity: 127))

    // Pump the envelope past attack so it's in sustain
    let voice0 = preset.voices[0]
    let ampEnvs = voice0.namedADSREnvelopes["ampEnv"]!
    for env in ampEnvs {
      _ = env.env(0.0)
      _ = env.env(0.05) // past attack+decay (0.01+0.01)
    }

    preset.noteOff(MidiNote(note: 60, velocity: 0))

    for env in ampEnvs {
      #expect(env.state == .release, "ADSR should be in release after noteOff, got \(env.state)")
    }
  }

  @Test("Multiple notes use different voices")
  func multipleNotesUseDifferentVoices() {
    let preset = makeTestPreset(numVoices: 4)
    let note60 = MidiNote(note: 60, velocity: 127)
    let note64 = MidiNote(note: 64, velocity: 127)
    preset.noteOn(note60)
    preset.noteOn(note64)

    // Voice 0 should have note 60's freq, voice 1 should have note 64's freq
    let voice0Freq = preset.voices[0].namedConsts["freq"]!.first!.val
    let voice1Freq = preset.voices[1].namedConsts["freq"]!.first!.val
    #expect(abs(voice0Freq - note60.freq) < 0.001)
    #expect(abs(voice1Freq - note64.freq) < 0.001)
  }

  @Test("Retrigger same note reuses the same voice")
  func retriggerReusesVoice() {
    let preset = makeTestPreset(numVoices: 4)
    let note60a = MidiNote(note: 60, velocity: 100)
    let note60b = MidiNote(note: 60, velocity: 80)
    preset.noteOn(note60a)

    // Voice 0 should be in attack
    let voice0 = preset.voices[0]
    let ampEnvs = voice0.namedADSREnvelopes["ampEnv"]!
    #expect(ampEnvs.first!.state == .attack)

    // Pump through to sustain
    for env in ampEnvs {
      _ = env.env(0.0)
      _ = env.env(0.05)
    }

    // Retrigger same note — should re-trigger voice 0, not allocate voice 1
    preset.noteOn(note60b)
    #expect(ampEnvs.first!.state == .attack,
            "Retrigger should put ADSR back in attack")

    // Voice 1 should NOT have been touched — its freq should still be the default 440
    let voice1Freq = preset.voices[1].namedConsts["freq"]!.first!.val
    #expect(abs(voice1Freq - 440.0) < 0.001,
            "Voice 1 should still have default freq, got \(voice1Freq)")
  }

  @Test("Voice exhaustion drops extra notes gracefully")
  func voiceExhaustion() {
    let preset = makeTestPreset(numVoices: 2)
    preset.noteOn(MidiNote(note: 60, velocity: 127))
    preset.noteOn(MidiNote(note: 64, velocity: 127))
    // Both voices taken — third note should be dropped
    preset.noteOn(MidiNote(note: 67, velocity: 127))
    #expect(preset.activeNoteCount == 2,
            "Should still be 2 since third note was dropped")
  }

  @Test("globalOffset shifts the note for freq calculation")
  func globalOffsetShiftsNote() {
    let preset = makeTestPreset(numVoices: 4)
    preset.globalOffset = 12 // one octave up
    preset.noteOn(MidiNote(note: 60, velocity: 127))

    // The offset note is 72, so freq should be note 72's frequency
    let expectedFreq = MidiNote(note: 72, velocity: 127).freq
    let voice0Freq = preset.voices[0].namedConsts["freq"]!.first!.val
    #expect(abs(voice0Freq - expectedFreq) < 0.001,
            "With +12 offset, note 60 should sound as note 72 (\(expectedFreq) Hz), got \(voice0Freq)")
  }

  @Test("Full noteOn/noteOff cycle leaves preset silent")
  func fullCycleLeavesSilent() {
    let preset = makeTestPreset(numVoices: 4)
    // Play 3 notes
    preset.noteOn(MidiNote(note: 60, velocity: 127))
    preset.noteOn(MidiNote(note: 64, velocity: 127))
    preset.noteOn(MidiNote(note: 67, velocity: 127))
    #expect(preset.activeNoteCount == 3)

    // Release all
    preset.noteOff(MidiNote(note: 60, velocity: 0))
    preset.noteOff(MidiNote(note: 64, velocity: 0))
    preset.noteOff(MidiNote(note: 67, velocity: 0))
    #expect(preset.activeNoteCount == 0)

    // All voices' ADSRs should be in release
    for i in 0..<3 {
      let ampEnvs = preset.voices[i].namedADSREnvelopes["ampEnv"]!
      for env in ampEnvs {
        #expect(env.state == .release,
                "Voice \(i) ADSR should be in release after noteOff")
      }
    }
  }

  @Test("noteOn produces audible output from the summed sound")
  func noteOnProducesSound() {
    let preset = makeTestPreset(numVoices: 2)
    guard let sound = preset.sound else {
      Issue.record("Preset should have a sound arrow")
      return
    }

    // Before noteOn — gate is closed, should be silent
    sound.setSampleRateRecursive(rate: 44100)
    var silentBuf = [CoreFloat](repeating: 0, count: 512)
    let times = (0..<512).map { CoreFloat($0) / 44100.0 + 100.0 }
    preset.audioGate!.process(inputs: times, outputs: &silentBuf)
    let silentRMS = sqrt(silentBuf.reduce(0) { $0 + $1 * $1 } / CoreFloat(silentBuf.count))
    #expect(silentRMS < 0.001, "Should be silent before noteOn")

    // Trigger a note — gate opens via lifecycle callback
    preset.noteOn(MidiNote(note: 69, velocity: 127))

    // Render through the gate
    var loudBuf = [CoreFloat](repeating: 0, count: 512)
    preset.audioGate!.process(inputs: times, outputs: &loudBuf)
    let loudRMS = sqrt(loudBuf.reduce(0) { $0 + $1 * $1 } / CoreFloat(loudBuf.count))
    #expect(loudRMS > 0.01, "Should produce sound after noteOn, got RMS \(loudRMS)")
  }
}
