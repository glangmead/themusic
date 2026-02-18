//
//  PatternGenerationTests.swift
//  ProgressionPlayerTests
//
//  Phase 4: Pattern generation tests — iterator unit tests, MusicEvent modulation,
//  MusicPattern event generation
//

import Testing
import Foundation
import Tonic
@testable import ProgressionPlayer

// MARK: - Iterator Unit Tests

@Suite("Iterators", .serialized)
struct IteratorTests {

  @Test("Cyclic iterator wraps around")
  func cyclicWrapsAround() {
    var iter = [1, 2, 3].cyclicIterator()
    let results = (0..<7).map { _ in iter.next()! }
    #expect(results == [1, 2, 3, 1, 2, 3, 1])
  }

  @Test("Cyclic iterator with single element repeats")
  func cyclicSingleElement() {
    var iter = ["x"].cyclicIterator()
    for _ in 0..<5 {
      #expect(iter.next() == "x")
    }
  }

  @Test("Random iterator draws from the collection")
  func randomDrawsFromCollection() {
    let items = [10, 20, 30, 40, 50]
    var iter = items.randomIterator()
    let itemSet = Set(items)
    for _ in 0..<100 {
      let val = iter.next()!
      #expect(itemSet.contains(val), "Random iterator should only produce collection elements")
    }
  }

  @Test("Random iterator covers all elements given enough draws")
  func randomCoversAll() {
    let items = [1, 2, 3]
    var iter = items.randomIterator()
    var seen = Set<Int>()
    for _ in 0..<200 {
      seen.insert(iter.next()!)
    }
    #expect(seen == Set(items), "Should see all elements after many draws, saw \(seen)")
  }

  @Test("Shuffled iterator produces all elements before reshuffling")
  func shuffledProducesAll() {
    var iter = [1, 2, 3, 4].shuffledIterator()
    // First cycle: should produce all 4 elements in some order
    var firstCycle = Set<Int>()
    for _ in 0..<4 {
      firstCycle.insert(iter.next()!)
    }
    #expect(firstCycle == Set([1, 2, 3, 4]),
            "First full cycle should contain all elements")

    // Second cycle: should also produce all 4
    var secondCycle = Set<Int>()
    for _ in 0..<4 {
      secondCycle.insert(iter.next()!)
    }
    #expect(secondCycle == Set([1, 2, 3, 4]),
            "Second full cycle should also contain all elements")
  }

  @Test("FloatSampler produces values in range")
  func floatSamplerRange() {
    let sampler = FloatSampler(min: 2.0, max: 5.0)
    for _ in 0..<100 {
      let val = sampler.next()!
      #expect(val >= 2.0 && val <= 5.0, "FloatSampler value \(val) should be in [2, 5]")
    }
  }

  @Test("ListSampler draws from its items")
  func listSamplerDraws() {
    let items = ["a", "b", "c"]
    let sampler = ListSampler(items)
    let itemSet = Set(items)
    for _ in 0..<50 {
      let val = sampler.next()!
      #expect(itemSet.contains(val))
    }
  }

  @Test("MidiPitchGenerator produces valid MIDI note numbers")
  func midiPitchGeneratorRange() {
    var gen = MidiPitchGenerator(
      scaleGenerator: [Scale.major].cyclicIterator(),
      degreeGenerator: Array(0...6).cyclicIterator(),
      rootNoteGenerator: [NoteClass.C].cyclicIterator(),
      octaveGenerator: [3, 4].cyclicIterator()
    )
    for _ in 0..<20 {
      let note = gen.next()!
      #expect(note <= 127, "MIDI note \(note) should be <= 127")
    }
  }

  @Test("MidiPitchAsChordGenerator wraps pitch as single-note chord")
  func midiPitchAsChord() {
    var gen = MidiPitchAsChordGenerator(
      pitchGenerator: MidiPitchGenerator(
        scaleGenerator: [Scale.major].cyclicIterator(),
        degreeGenerator: [0].cyclicIterator(),
        rootNoteGenerator: [NoteClass.C].cyclicIterator(),
        octaveGenerator: [4].cyclicIterator()
      )
    )
    let chord = gen.next()!
    #expect(chord.count == 1, "Should produce a single-note chord")
    #expect(chord[0].velocity == 127)
  }

  @Test("Midi1700sChordGenerator produces non-empty chords")
  func chordGeneratorProducesChords() {
    var gen = Midi1700sChordGenerator(
      scaleGenerator: [Scale.major].cyclicIterator(),
      rootNoteGenerator: [NoteClass.C].cyclicIterator()
    )
    for _ in 0..<10 {
      let chord = gen.next()!
      #expect(!chord.isEmpty, "Chord should have at least one note")
      for note in chord {
        #expect(note.note <= 127)
        #expect(note.velocity == 127)
      }
    }
  }

  @Test("Midi1700sChordGenerator starts with chord I")
  func chordGeneratorStartsWithI() {
    var gen = Midi1700sChordGenerator(
      scaleGenerator: [Scale.major].cyclicIterator(),
      rootNoteGenerator: [NoteClass.C].cyclicIterator()
    )
    let _ = gen.next() // first chord
    // After the first call, currentChord should be .I
    #expect(gen.currentChord == .I, "First chord should be I")
  }

  @Test("ScaleSampler produces notes from the scale")
  func scaleSamplerProducesNotes() {
    let sampler = ScaleSampler(scale: .major)
    for _ in 0..<20 {
      let chord = sampler.next()!
      #expect(chord.count == 1)
      #expect(chord[0].note <= 127)
      #expect(chord[0].velocity >= 50 && chord[0].velocity <= 127)
    }
  }
}

// MARK: - MusicEvent Modulation Tests

/// ArrowSyntax that includes named consts we can modulate (overallAmp, vibratoAmp, vibratoFreq)
private let modulatableArrowSyntax: ArrowSyntax = .compose(arrows: [
  .prod(of: [
    .envelope(name: "ampEnv", attack: 0.01, decay: 0.01, sustain: 1.0, release: 0.1, scale: 1.0),
    .compose(arrows: [
      .prod(of: [
        .prod(of: [
          .const(name: "freq", val: 440),
          .prod(of: [
            .constCent(name: "overallCentDetune", val: 0),
            .prod(of: [
              .constOctave(name: "osc1Octave", val: 0),
              .identity
            ])
          ])
        ]),
        .identity
      ]),
      .osc(name: "osc", shape: .sine, width: .const(name: "w", val: 1))
    ]),
    .const(name: "overallAmp", val: 1.0)
  ])
])

@Suite("MusicEvent Modulation", .serialized)
struct MusicEventModulationTests {

  @Test("MusicEvent.play() applies const modulators to handles")
  func eventAppliesConstModulators() async throws {
    let preset = Preset(arrowSyntax: modulatableArrowSyntax, numVoices: 1, initEffects: false)
    let note = MidiNote(note: 60, velocity: 127)

    // A modulator that sets overallAmp to a fixed value
    let fixedAmpArrow = ArrowConst(value: 0.42)

    var event = MusicEvent(
      noteHandler: preset,
      notes: [note],
      sustain: 0.01, // very short
      gap: 0.01,
      modulators: ["overallAmp": fixedAmpArrow],
      timeOrigin: Date.now.timeIntervalSince1970,
      clock: ImmediateClock()
    )

    // Check initial value
    let initialAmp = preset.handles?.namedConsts["overallAmp"]?.first?.val ?? -1
    #expect(initialAmp == 1.0, "Initial overallAmp should be 1.0")

    // Play the event (will modulate, noteOn, sleep, noteOff)
    try await event.play()

    // After play, the const should have been set to the modulator's value
    let modulatedAmp = preset.handles?.namedConsts["overallAmp"]?.first?.val ?? -1
    #expect(abs(modulatedAmp - 0.42) < 0.001,
            "overallAmp should be modulated to 0.42, got \(modulatedAmp)")
  }

  @Test("MusicEvent.play() calls noteOn then noteOff")
  func eventCallsNoteOnAndOff() async throws {
    let preset = Preset(arrowSyntax: modulatableArrowSyntax, numVoices: 1, initEffects: false)
    let note = MidiNote(note: 60, velocity: 127)

    var event = MusicEvent(
      noteHandler: preset,
      notes: [note],
      sustain: 0.01,
      gap: 0.01,
      modulators: [:],
      timeOrigin: Date.now.timeIntervalSince1970,
      clock: ImmediateClock()
    )

    #expect(preset.activeNoteCount == 0)
    try await event.play()
    // After play completes, noteOff should have been called
    // activeNoteCount should be back to 0 (note was released)
    // The voice's ADSR should be in release state
    let ampEnvs = preset.voices[0].namedADSREnvelopes["ampEnv"]!
    for env in ampEnvs {
      #expect(env.state == .release,
              "ADSR should be in release after event.play() completes")
    }
  }

  @Test("MusicEvent.play() with multiple notes triggers all of them")
  func eventTriggersMultipleNotes() async throws {
    let preset = Preset(arrowSyntax: modulatableArrowSyntax, numVoices: 4, initEffects: false)
    let notes = [
      MidiNote(note: 60, velocity: 127),
      MidiNote(note: 64, velocity: 127),
      MidiNote(note: 67, velocity: 127)
    ]

    var event = MusicEvent(
      noteHandler: preset,
      notes: notes,
      sustain: 0.01,
      gap: 0.01,
      modulators: [:],
      timeOrigin: Date.now.timeIntervalSince1970,
      clock: ImmediateClock()
    )

    try await event.play()
    // All 3 notes should have been played and released
    // All 3 voices should have ADSRs in release
    for i in 0..<3 {
      let ampEnvs = preset.voices[i].namedADSREnvelopes["ampEnv"]!
      for env in ampEnvs {
        #expect(env.state == .release,
                "Voice \(i) ADSR should be in release after event completes")
      }
    }
  }

  @Test("EventUsingArrow receives the event and uses it")
  func eventUsingArrowReceivesEvent() async throws {
    let preset = Preset(arrowSyntax: modulatableArrowSyntax, numVoices: 1, initEffects: false)
    let note = MidiNote(note: 72, velocity: 100) // note 72

    // An EventUsingArrow that returns the note number divided by 100
    let eventArrow = EventUsingArrow(ofEvent: { event, _ in
      CoreFloat(event.notes[0].note) / 100.0
    })

    var event = MusicEvent(
      noteHandler: preset,
      notes: [note],
      sustain: 0.01,
      gap: 0.01,
      modulators: ["overallAmp": eventArrow],
      timeOrigin: Date.now.timeIntervalSince1970,
      clock: ImmediateClock()
    )

    try await event.play()

    let modulatedAmp = preset.handles?.namedConsts["overallAmp"]?.first?.val ?? -1
    #expect(abs(modulatedAmp - 0.72) < 0.001,
            "overallAmp should be 72/100 = 0.72, got \(modulatedAmp)")
  }

  @Test("MusicEvent.cancel() sends noteOff for all notes")
  func eventCancelSendsNoteOff() {
    let preset = Preset(arrowSyntax: modulatableArrowSyntax, numVoices: 4, initEffects: false)
    let notes = [
      MidiNote(note: 60, velocity: 127),
      MidiNote(note: 64, velocity: 127),
    ]

    // Manually trigger notes first
    preset.noteOn(notes[0])
    preset.noteOn(notes[1])
    #expect(preset.activeNoteCount == 2)

    let event = MusicEvent(
      noteHandler: preset,
      notes: notes,
      sustain: 10.0, // long sustain we won't wait for
      gap: 0.01,
      modulators: [:],
      timeOrigin: Date.now.timeIntervalSince1970
    )

    event.cancel()
    // cancel() calls notesOff, which should release both voices
    #expect(preset.activeNoteCount == 0,
            "Cancel should release all notes, activeNoteCount is \(preset.activeNoteCount)")
  }
}

// MARK: - MusicPattern Event Generation Tests

@Suite("MusicPattern Event Generation", .serialized)
struct MusicPatternEventGenerationTests {

  /// Build a test-friendly MusicPattern using a Preset-based SpatialPreset.
  /// This requires a SpatialAudioEngine, but we only use it for the SpatialPreset
  /// constructor — we won't start the engine.
  /// Since SpatialPreset.setup() calls wrapInAppleNodes, which needs the engine,
  /// we test MusicPattern.next() logic indirectly by verifying the building blocks.

  @Test("FloatSampler produces sustain and gap values")
  func sustainAndGapGeneration() {
    let sustains = FloatSampler(min: 1.0, max: 5.0)
    let gaps = FloatSampler(min: 0.5, max: 2.0)
    for _ in 0..<50 {
      let s = sustains.next()!
      let g = gaps.next()!
      #expect(s >= 1.0 && s <= 5.0)
      #expect(g >= 0.5 && g <= 2.0)
    }
  }

  @Test("MusicEvent has correct structure when assembled manually")
  func eventStructure() {
    let preset = Preset(
      arrowSyntax: modulatableArrowSyntax, numVoices: 2, initEffects: false
    )
    let notes = [MidiNote(note: 60, velocity: 100), MidiNote(note: 64, velocity: 100)]
    let modulator = ArrowConst(value: 0.5)

    let event = MusicEvent(
      noteHandler: preset,
      notes: notes,
      sustain: 3.0,
      gap: 1.0,
      modulators: ["overallAmp": modulator],
      timeOrigin: 0
    )

    #expect(event.notes.count == 2)
    #expect(event.sustain == 3.0)
    #expect(event.gap == 1.0)
    #expect(event.modulators.count == 1)
    #expect(event.modulators["overallAmp"] != nil)
  }

  @Test("Chord generator + sustain/gap iterators can produce a sequence of events")
  func eventSequenceFromGenerators() {
    var chordGen = Midi1700sChordGenerator(
      scaleGenerator: [Scale.major].cyclicIterator(),
      rootNoteGenerator: [NoteClass.C].cyclicIterator()
    )
    let sustains = FloatSampler(min: 1.0, max: 3.0)
    let gaps = FloatSampler(min: 0.5, max: 1.5)

    let preset = Preset(
      arrowSyntax: modulatableArrowSyntax, numVoices: 4, initEffects: false
    )

    // Generate 10 events
    for i in 0..<10 {
      guard let notes = chordGen.next() else {
        Issue.record("Chord generator returned nil at iteration \(i)")
        return
      }
      let sustain = sustains.next()!
      let gap = gaps.next()!

      let event = MusicEvent(
        noteHandler: preset,
        notes: notes,
        sustain: sustain,
        gap: gap,
        modulators: [:],
        timeOrigin: 0
      )

      #expect(!event.notes.isEmpty, "Event \(i) should have notes")
      #expect(event.sustain >= 1.0 && event.sustain <= 3.0)
      #expect(event.gap >= 0.5 && event.gap <= 1.5)
    }
  }

  @Test("Multiple modulators all apply to a single event")
  func multipleModulatorsApply() async throws {
    let preset = Preset(arrowSyntax: modulatableArrowSyntax, numVoices: 1, initEffects: false)
    let note = MidiNote(note: 69, velocity: 127)

    var event = MusicEvent(
      noteHandler: preset,
      notes: [note],
      sustain: 0.01,
      gap: 0.01,
      modulators: [
        "overallAmp": ArrowConst(value: 0.33),
        "overallCentDetune": ArrowConst(value: 7.0),
      ],
      timeOrigin: Date.now.timeIntervalSince1970,
      clock: ImmediateClock()
    )

    try await event.play()

    let amp = preset.handles?.namedConsts["overallAmp"]?.first?.val ?? -1
    let detune = preset.handles?.namedConsts["overallCentDetune"]?.first?.val ?? -1
    #expect(abs(amp - 0.33) < 0.001, "overallAmp should be 0.33, got \(amp)")
    #expect(abs(detune - 7.0) < 0.001, "overallCentDetune should be 7.0, got \(detune)")
  }

  @Test("Chord generator state transitions produce valid chord sequences")
  func chordTransitionsAreValid() {
    var gen = Midi1700sChordGenerator(
      scaleGenerator: [Scale.major].cyclicIterator(),
      rootNoteGenerator: [NoteClass.A].cyclicIterator()
    )

    // Generate many chords to exercise state transitions
    var chordNames = [Midi1700sChordGenerator.TymoczkoChords713]()
    for _ in 0..<50 {
      let _ = gen.next()!
      chordNames.append(gen.currentChord)
    }

    // Should start with I
    #expect(chordNames[0] == .I)

    // Should have visited more than just I over 50 iterations
    let uniqueChords = Set(chordNames.map { "\($0)" })
    #expect(uniqueChords.count > 3,
            "50 chord transitions should visit more than 3 chord types, visited \(uniqueChords)")
  }
}

// MARK: - Multi-track MIDI Parsing Tests

@Suite("Multi-track MIDI Parsing", .serialized)
struct MultiTrackMidiParsingTests {

  /// Locate the BachInvention1.mid file in the app bundle.
  private func bachURL() throws -> URL {
    guard let url = Bundle.main.url(forResource: "BachInvention1", withExtension: "mid", subdirectory: "patterns") else {
      throw MidiTestError.fileNotFound
    }
    return url
  }

  private enum MidiTestError: Error { case fileNotFound }

  @Test("allTracks returns two nonempty tracks for Bach Invention")
  func allTracksReturnsTwoTracks() throws {
    let url = try bachURL()
    let tracks = MidiEventSequence.allTracks(url: url, loop: false)
    #expect(tracks.count == 2,
            "Bach Invention 1 has two voices, got \(tracks.count) tracks")
  }

  @Test("Track 1 has a different first note than Track 0")
  func tracksHaveDifferentContent() throws {
    let url = try bachURL()
    let tracks = MidiEventSequence.allTracks(url: url, loop: false)
    #expect(tracks.count == 2)

    // Skip any leading empty rest chords to get the first real note
    let firstNote0 = tracks[0].sequence.chords.first(where: { !$0.isEmpty })
    let firstNote1 = tracks[1].sequence.chords.first(where: { !$0.isEmpty })
    #expect(firstNote0 != nil && firstNote1 != nil,
            "Both tracks should have at least one non-empty chord")

    // Right hand starts around C4 (60), left hand around C3 (48)
    let pitch0 = Int(firstNote0![0].note)
    let pitch1 = Int(firstNote1![0].note)
    #expect(pitch0 != pitch1,
            "First notes should differ between tracks: track0=\(pitch0), track1=\(pitch1)")
    // Right hand is higher than left hand
    #expect(pitch0 > pitch1,
            "Track 0 (right hand, \(pitch0)) should be higher than track 1 (left hand, \(pitch1))")
  }

  @Test("Track 1 has an initial rest gap preserving its late entry")
  func track1HasInitialRest() throws {
    let url = try bachURL()
    let tracks = MidiEventSequence.allTracks(url: url, loop: false)
    #expect(tracks.count == 2)

    let seq1 = tracks[1].sequence

    // The left hand enters at beat 2.25 in the MIDI file.
    // The first chord should be empty (the initial rest) and its gap should
    // correspond to 2.25 beats converted to seconds at the file's tempo (~59.3 BPM).
    #expect(seq1.chords[0].isEmpty,
            "Track 1 should start with an empty rest chord")
    #expect(seq1.sustains[0] == 0,
            "Rest chord sustain should be 0")

    // At ~59.3 BPM, secondsPerBeat ≈ 1.012. 2.25 beats ≈ 2.276 seconds.
    // Allow a generous tolerance for tempo rounding.
    let initialGap = seq1.gaps[0]
    #expect(initialGap > 1.5 && initialGap < 3.5,
            "Track 1 initial rest gap should be ~2.3s (2.25 beats at ~59 BPM), got \(initialGap)")
  }

  @Test("Track 0 has a shorter initial rest than Track 1")
  func track0HasShorterInitialRest() throws {
    let url = try bachURL()
    let tracks = MidiEventSequence.allTracks(url: url, loop: false)
    #expect(tracks.count == 2)

    let seq0 = tracks[0].sequence
    let seq1 = tracks[1].sequence

    // Track 0 starts at beat 0.25; track 1 starts at beat 2.25.
    // If track 0 has an initial rest it should be much shorter than track 1's.
    let gap0: CoreFloat
    if seq0.chords[0].isEmpty {
      gap0 = seq0.gaps[0]
    } else {
      gap0 = 0 // no initial rest means it starts immediately
    }

    // Track 1 definitely has an initial rest
    #expect(seq1.chords[0].isEmpty)
    let gap1 = seq1.gaps[0]

    #expect(gap1 > gap0 + 1.0,
            "Track 1 initial rest (\(gap1)s) should be > 1s longer than track 0's (\(gap0)s)")
  }

  @Test("Both tracks have many note events")
  func bothTracksHaveManyNotes() throws {
    let url = try bachURL()
    let tracks = MidiEventSequence.allTracks(url: url, loop: false)
    #expect(tracks.count == 2)

    // Bach Invention 1 has hundreds of notes per voice
    let noteCount0 = tracks[0].sequence.chords.filter({ !$0.isEmpty }).count
    let noteCount1 = tracks[1].sequence.chords.filter({ !$0.isEmpty }).count
    #expect(noteCount0 > 50,
            "Track 0 should have many note events, got \(noteCount0)")
    #expect(noteCount1 > 50,
            "Track 1 should have many note events, got \(noteCount1)")
  }
}
