//
//  NoteHandlingTests.swift
//  OrbitalTests
//
//  Phase 2: Note handling tests — VoiceLedger unit tests, Preset noteOn/noteOff logic tests
//

import Testing
import Foundation
@testable import Orbital

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

    // Release note 60 — voice 0 returns to the pool
    let released = ledger.releaseVoice(60)
    #expect(released == 0, "Should release index 0")

    // Next allocation reuses voice 0 (now available)
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

  @Test("Tier-3 steals oldest noteOnned voice when all voices are busy")
  func exhaustionStealsOldest() {
    let ledger = VoiceLedger(voiceCount: 2)
    let a = ledger.takeAvailableVoice(60)
    let b = ledger.takeAvailableVoice(62)
    // Tier-3: steals the oldest noteOnned voice (index 0, which played note 60)
    let c = ledger.takeAvailableVoice(64)
    #expect(a == 0)
    #expect(b == 1)
    #expect(c == 0, "Tier-3 should steal oldest noteOnned voice (index 0)")
    // Old note 60 mapping is evicted; note 64 now owns index 0
    #expect(ledger.voiceIndex(for: 60) == nil, "Old note mapping should be evicted")
    #expect(ledger.voiceIndex(for: 64) == 0, "New note should own the stolen voice")
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

  @Test("beginRelease keeps voice unavailable until finishRelease")
  func deferredRelease() {
    // Use 3 voices so voice 2 stays available during the test, avoiding voice stealing.
    let ledger = VoiceLedger(voiceCount: 3)
    let _ = ledger.takeAvailableVoice(60) // voice 0
    let _ = ledger.takeAvailableVoice(62) // voice 1
    // voice 2 remains available

    // Begin release on note 60 — voice 0 moves to releasing
    let released = ledger.beginRelease(60)
    #expect(released == 0)

    // Available voice 2 is preferred over releasing voice 0
    let next = ledger.takeAvailableVoice(64)
    #expect(next == 2, "Available voice 2 should be used before stealing releasing voice 0")

    // Note mapping for 60 is cleared by beginRelease
    #expect(ledger.voiceIndex(for: 60) == nil)

    // Finish release — voice 0 becomes available at end of queue
    ledger.finishRelease(voiceIndex: 0)
    let reused = ledger.takeAvailableVoice(66)
    #expect(reused == 0, "Voice 0 should be available after finishRelease")
  }

  @Test("beginRelease for untracked note returns nil")
  func beginReleaseUntracked() {
    let ledger = VoiceLedger(voiceCount: 4)
    #expect(ledger.beginRelease(60) == nil)
  }

  @Test("Same note can be replayed on a different voice while first is releasing")
  func replayWhileReleasing() {
    let ledger = VoiceLedger(voiceCount: 3)
    let idx0 = ledger.takeAvailableVoice(60) // index 0
    #expect(idx0 == 0)

    // Begin release — voice 0 is releasing, note 60 unmapped
    let _ = ledger.beginRelease(60)

    // Play note 60 again — should get a different voice
    let idx1 = ledger.takeAvailableVoice(60)
    #expect(idx1 == 1, "Should get voice 1 since voice 0 is still releasing")

    // Finish release of voice 0
    ledger.finishRelease(voiceIndex: 0)

    // Now voice 0 is back in the pool
    let idx2 = ledger.takeAvailableVoice(62)
    #expect(idx2 == 2, "Voice 2 was next in queue")
    let idx3 = ledger.takeAvailableVoice(64)
    #expect(idx3 == 0, "Voice 0 should now be available at end of queue")
  }

  @Test("Registered envelopes auto-release voice when all close")
  func autoReleaseViaEnvelopes() {
    // Use 3 voices so voice 2 stays available during the test, avoiding voice stealing.
    let ledger = VoiceLedger(voiceCount: 3)
    let env = ADSR(envelope: EnvelopeData(
      attackTime: 0.01, decayTime: 0.01, sustainLevel: 1.0,
      releaseTime: 0.05, scale: 1.0
    ))
    ledger.registerEnvelopes(forVoice: 0, envelopes: [env])

    let _ = ledger.takeAvailableVoice(60) // voice 0
    let _ = ledger.takeAvailableVoice(62) // voice 1
    // voice 2 remains available

    // Begin release — appends finish callback on the envelope
    let released = ledger.beginRelease(60)
    #expect(released == 0)

    // Available voice 2 is preferred over releasing voice 0
    let next = ledger.takeAvailableVoice(64)
    #expect(next == 2, "Available voice 2 should be used before stealing releasing voice 0")

    // Start the envelope's attack, then release
    env.noteOn(MidiNote(note: 60, velocity: 127))
    _ = env.env(0.0)
    _ = env.env(0.03) // past attack+decay
    env.noteOff(MidiNote(note: 60, velocity: 0))

    // Pump the envelope past the release time to trigger the callback
    _ = env.env(0.03) // reset timeOrigin for release
    _ = env.env(0.03 + 0.06) // past releaseTime (0.05)

    // The finish callback should have called finishRelease
    #expect(env.state == .closed)
    let reused = ledger.takeAvailableVoice(64)
    #expect(reused == 0, "Voice 0 should be auto-released after envelope closed")
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

  @Test("Retrigger does not inflate activeNoteCount")
  func retriggerDoesNotInflateCount() {
    let preset = makeTestPreset(numVoices: 4)
    let note60 = MidiNote(note: 60, velocity: 127)
    preset.noteOn(note60)
    #expect(preset.activeNoteCount == 1)

    // Retrigger same note without noteOff
    preset.noteOn(MidiNote(note: 60, velocity: 80))
    #expect(preset.activeNoteCount == 1,
            "Retrigger should not increment count; got \(preset.activeNoteCount)")

    // Multiple retriggers
    preset.noteOn(MidiNote(note: 60, velocity: 90))
    preset.noteOn(MidiNote(note: 60, velocity: 100))
    #expect(preset.activeNoteCount == 1,
            "Multiple retriggers should keep count at 1; got \(preset.activeNoteCount)")

    // Release should bring count to 0
    preset.noteOff(MidiNote(note: 60, velocity: 0))
    #expect(preset.activeNoteCount == 0,
            "After release, count should be 0; got \(preset.activeNoteCount)")
  }

  @Test("Rapid retrigger-then-release cycle leaves count at zero")
  func rapidRetriggerReleaseCycle() {
    let preset = makeTestPreset(numVoices: 4)
    // Simulate rapid key presses: noteOn, retrigger, release, repeated
    for _ in 0..<10 {
      preset.noteOn(MidiNote(note: 60, velocity: 127))
      preset.noteOn(MidiNote(note: 60, velocity: 80))  // retrigger
      preset.noteOff(MidiNote(note: 60, velocity: 0))
    }
    #expect(preset.activeNoteCount == 0,
            "After 10 retrigger+release cycles, count should be 0; got \(preset.activeNoteCount)")
  }

  @Test("Retrigger then release leaves all ADSRs in release state")
  func retriggerThenReleaseADSRState() {
    let preset = makeTestPreset(numVoices: 4)
    preset.noteOn(MidiNote(note: 60, velocity: 127))

    // Retrigger several times
    preset.noteOn(MidiNote(note: 60, velocity: 80))
    preset.noteOn(MidiNote(note: 60, velocity: 90))

    // Release
    preset.noteOff(MidiNote(note: 60, velocity: 0))

    // Voice 0 should be in release, not stuck in attack
    let voice0 = preset.voices[0]
    let ampEnvs = voice0.namedADSREnvelopes["ampEnv"]!
    for env in ampEnvs {
      #expect(env.state == .release,
              "After retrigger+release, ADSR should be in release, got \(env.state)")
    }
  }

  @Test("Voice exhaustion steals oldest voice for new note")
  func voiceExhaustion() {
    let preset = makeTestPreset(numVoices: 2)
    preset.noteOn(MidiNote(note: 60, velocity: 127))
    preset.noteOn(MidiNote(note: 64, velocity: 127))
    // Both voices busy — tier-3 steals voice 0 (note 60) for note 67.
    // The stolen voice remains noteOnned, so activeNoteCount stays at 2.
    preset.noteOn(MidiNote(note: 67, velocity: 127))
    #expect(preset.activeNoteCount == 2,
            "Stolen voice stays noteOnned; count should remain 2")
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

// MARK: - Handle Duplication Diagnostic

@Suite("Handle duplication in compose", .serialized)
struct HandleDuplicationTests {

  @Test("Single compile of compose should not duplicate ADSR handles")
  func singleCompileNoDuplicateADSR() {
    // Mimics 5th Cluedo structure: compose([ prod(ampEnv, osc), lowPassFilter(filterEnv) ])
    let syntax: ArrowSyntax = .compose(arrows: [
      .prod(of: [
        .envelope(name: "ampEnv", attack: 0.01, decay: 0.01, sustain: 1.0, release: 0.1, scale: 1.0),
        .compose(arrows: [
          .prod(of: [.const(name: "freq", val: 440), .identity]),
          .osc(name: "osc", shape: .sine, width: .const(name: "w", val: 1))
        ])
      ]),
      .lowPassFilter(
        name: "filter",
        cutoff: .sum(of: [
          .const(name: "cutoffLow", val: 50),
          .prod(of: [
            .const(name: "cutoff", val: 5000),
            .envelope(name: "filterEnv", attack: 0.1, decay: 0.3, sustain: 1.0, release: 0.1, scale: 1.0)
          ])
        ]),
        resonance: .const(name: "resonance", val: 1.6)
      )
    ])

    let compiled = syntax.compile()
    let ampEnvCount = compiled.namedADSREnvelopes["ampEnv"]?.count ?? 0
    let filterEnvCount = compiled.namedADSREnvelopes["filterEnv"]?.count ?? 0
    print("ampEnv count: \(ampEnvCount), filterEnv count: \(filterEnvCount)")

    // Check for unique object references
    if let ampEnvs = compiled.namedADSREnvelopes["ampEnv"] {
      let uniqueAmpEnvs = Set(ampEnvs.map { ObjectIdentifier($0) })
      print("ampEnv: \(ampEnvs.count) total, \(uniqueAmpEnvs.count) unique")
      #expect(ampEnvs.count == 1,
              "Should have exactly 1 ampEnv entry, got \(ampEnvs.count) (compose is duplicating handles)")
    }
    if let filterEnvs = compiled.namedADSREnvelopes["filterEnv"] {
      let uniqueFilterEnvs = Set(filterEnvs.map { ObjectIdentifier($0) })
      print("filterEnv: \(filterEnvs.count) total, \(uniqueFilterEnvs.count) unique")
      #expect(filterEnvs.count == 1,
              "Should have exactly 1 filterEnv entry, got \(filterEnvs.count) (compose is duplicating handles)")
    }
  }

  @Test("5th Cluedo preset compile should not duplicate ADSR handles")
  func cluedoPresetNoDuplicateADSR() throws {
    let presetSpec = try loadPresetSyntax("5th_cluedo.json")
    guard let arrowSyntax = presetSpec.arrow else {
      Issue.record("5th Cluedo should have an arrow")
      return
    }
    let compiled = arrowSyntax.compile()
    let ampEnvCount = compiled.namedADSREnvelopes["ampEnv"]?.count ?? 0
    let filterEnvCount = compiled.namedADSREnvelopes["filterEnv"]?.count ?? 0
    print("5th Cluedo - ampEnv count: \(ampEnvCount), filterEnv count: \(filterEnvCount)")

    if let ampEnvs = compiled.namedADSREnvelopes["ampEnv"] {
      let unique = Set(ampEnvs.map { ObjectIdentifier($0) })
      print("5th Cluedo - ampEnv unique: \(unique.count) out of \(ampEnvs.count)")
      #expect(unique.count == 1,
              "5th Cluedo should have 1 unique ampEnv, got \(unique.count) unique out of \(ampEnvs.count)")
    }
  }
}
