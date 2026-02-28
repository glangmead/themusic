//
//  ScorePatternTests.swift
//  OrbitalTests
//
//  Tests for the scoreTracks pattern type:
//  - HarmonyTimeline state queries (initial, after T/t/setChord/setKey, looping)
//  - ScorePatternCompiler note resolution (all NoteSpecTypes)
//  - Hold merging in compileTrack
//  - parseNoteName utility
//  - Codable round-trips for ScorePatternSyntax types
//

import Testing
import Foundation
import Tonic
@testable import Orbital

// MARK: - Helpers

private func cMajorI() -> (key: Key, chord: ChordInScale) {
    (
        key: Key(root: .C, scale: .major),
        chord: ChordInScale(degrees: [0, 2, 4], inversion: 0)
    )
}

private func simpleTimeline(
    bpm: Double = 120,
    totalBeats: Double = 16,
    events: [ChordEventSyntax] = []
) -> HarmonyTimeline {
    let key = Key(root: .C, scale: .major)
    let evs = events.map { HarmonyTimeline.Event(beat: $0.beat, op: $0) }
    return HarmonyTimeline(totalBeats: totalBeats, initialKey: key, events: evs)
}

// MARK: - HarmonyTimeline Tests

@Suite("HarmonyTimeline", .serialized)
struct HarmonyTimelineTests {

    @Test("Initial state returns initial key and fallback I chord")
    func initialState() {
        let timeline = simpleTimeline()
        let (key, chord) = timeline.state(at: 0, loop: false)
        #expect(key.root == NoteClass.C)
        // Fallback chord should be [0, 2, 4]
        #expect(chord.degrees == [0, 2, 4])
        #expect(chord.inversion == 0)
    }

    @Test("setChord event at beat 0 establishes the chord")
    func setChordAtBeat0() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [1, 3, 5], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil)
        ]
        let timeline = simpleTimeline(events: events)
        let (_, chord) = timeline.state(at: 0, loop: false)
        #expect(chord.degrees == [1, 3, 5])
    }

    @Test("T event shifts chord degrees")
    func tShiftsDegrees() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil),
            ChordEventSyntax(beat: 4, op: "T", degrees: nil, inversion: nil,
                             n: 3, tVal: nil, root: nil, scale: nil)
        ]
        let timeline = simpleTimeline(events: events)
        // Before beat 4: I chord
        let (_, chordBefore) = timeline.state(at: 3.9, loop: false)
        #expect(chordBefore.degrees == [0, 2, 4])
        // At beat 4: I + T(3) = IV chord [3, 5, 7]
        let (_, chordAfter) = timeline.state(at: 4, loop: false)
        #expect(chordAfter.degrees == [3, 5, 7])
    }

    @Test("t event changes inversion")
    func tChangesInversion() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil),
            ChordEventSyntax(beat: 4, op: "t", degrees: nil, inversion: nil,
                             n: 1, tVal: nil, root: nil, scale: nil)
        ]
        let timeline = simpleTimeline(events: events)
        let (_, chord) = timeline.state(at: 4, loop: false)
        #expect(chord.inversion == 1)
        #expect(chord.degrees == [0, 2, 4])  // degrees unchanged, only inversion
    }

    @Test("Tt event applies both T and t")
    func ttEvent() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil),
            ChordEventSyntax(beat: 4, op: "Tt", degrees: nil, inversion: nil,
                             n: 1, tVal: 1, root: nil, scale: nil)
        ]
        let timeline = simpleTimeline(events: events)
        let (_, chord) = timeline.state(at: 4, loop: false)
        // T(1): [0,2,4] → [1,3,5]; t(1): inversion=0→1
        #expect(chord.degrees == [1, 3, 5])
        #expect(chord.inversion == 1)
    }

    @Test("setKey event changes the key")
    func setKeyEvent() {
        let events = [
            ChordEventSyntax(beat: 8, op: "setKey", degrees: nil, inversion: nil,
                             n: nil, tVal: nil, root: "G", scale: "major")
        ]
        let timeline = simpleTimeline(events: events)
        let (keyBefore, _) = timeline.state(at: 7.9, loop: false)
        let (keyAfter, _) = timeline.state(at: 8, loop: false)
        #expect(keyBefore.root == NoteClass.C)
        #expect(keyAfter.root == NoteClass.G)
    }

    @Test("Events at exact beat boundary fire at that beat")
    func exactBeatBoundary() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil),
            ChordEventSyntax(beat: 8, op: "T", degrees: nil, inversion: nil,
                             n: 2, tVal: nil, root: nil, scale: nil)
        ]
        let timeline = simpleTimeline(events: events)
        let (_, at8) = timeline.state(at: 8.0, loop: false)
        let (_, at8minus) = timeline.state(at: 7.999, loop: false)
        #expect(at8.degrees == [2, 4, 6])    // T(2) applied
        #expect(at8minus.degrees == [0, 2, 4]) // not yet applied
    }

    @Test("Looping wraps beat into [0, totalBeats)")
    func loopingWraps() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil),
            ChordEventSyntax(beat: 8, op: "T", degrees: nil, inversion: nil,
                             n: 2, tVal: nil, root: nil, scale: nil)
        ]
        let timeline = simpleTimeline(totalBeats: 16, events: events)
        // Beat 20 = beat 4 (mod 16) — T(2) not yet applied
        let (_, at20) = timeline.state(at: 20, loop: true)
        #expect(at20.degrees == [0, 2, 4])
        // Beat 24 = beat 8 (mod 16) — T(2) applied
        let (_, at24) = timeline.state(at: 24, loop: true)
        #expect(at24.degrees == [2, 4, 6])
    }
}

// MARK: - Note Resolution Tests

@Suite("ScorePatternCompiler Note Resolution", .serialized)
struct NoteResolutionTests {

    private func cMajorHierarchy() -> PitchHierarchy {
        PitchHierarchy(
            key: Key(root: .C, scale: .major),
            chord: ChordInScale(degrees: [0, 2, 4], inversion: 0)
        )
    }

    @Test("rest returns empty note array")
    func restReturnsEmpty() {
        let spec = ScoreNoteSyntax(
            type: .rest, durationBeats: 1,
            index: nil, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.isEmpty)
    }

    @Test("hold returns empty note array")
    func holdReturnsEmpty() {
        let spec = ScoreNoteSyntax(
            type: .hold, durationBeats: 1,
            index: nil, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.isEmpty)
    }

    @Test("chordTone index 0 resolves to bass note of I chord in C major at octave 4")
    func chordToneIndex0() {
        // I chord voiced: [0(C), 2(E), 4(G)], bass = C4 = MIDI 60
        let spec = ScoreNoteSyntax(
            type: .chordTone, durationBeats: 1,
            index: 0, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 60, "C4 = MIDI 60, got \(notes[0].note)")
    }

    @Test("chordTone index 1 resolves to E4 (third of I chord) in C major")
    func chordToneIndex1() {
        // voicedDegrees[1] = 2 (E) → E4 = MIDI 64
        let spec = ScoreNoteSyntax(
            type: .chordTone, durationBeats: 1,
            index: 1, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 64, "E4 = MIDI 64, got \(notes[0].note)")
    }

    @Test("chordTone index wraps at chord size: index 3 on triad = index 0 + 1 octave")
    func chordToneIndexWraps() {
        // index 3 on 3-note chord: octaveShift=1, wrappedIdx=0 → C4+1 octave = C5 = MIDI 72
        let spec = ScoreNoteSyntax(
            type: .chordTone, durationBeats: 1,
            index: 3, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 72, "C5 = MIDI 72, got \(notes[0].note)")
    }

    @Test("scaleDegree 0 resolves to C4 in C major")
    func scaleDegree0() {
        let spec = ScoreNoteSyntax(
            type: .scaleDegree, durationBeats: 1,
            index: nil, degree: 0, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 60, "C4 = MIDI 60, got \(notes[0].note)")
    }

    @Test("scaleDegree 2 resolves to E4 in C major")
    func scaleDegree2() {
        // Scale degree 2 = E (third of C major scale) → E4 = MIDI 64
        let spec = ScoreNoteSyntax(
            type: .scaleDegree, durationBeats: 1,
            index: nil, degree: 2, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 64, "E4 = MIDI 64, got \(notes[0].note)")
    }

    @Test("absolute midi resolves directly")
    func absoluteMidi() {
        let spec = ScoreNoteSyntax(
            type: .absolute, durationBeats: 1,
            index: nil, degree: nil, midi: 69, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 69, "MIDI 69 = A4")
    }

    @Test("absolute note name 'C4' resolves to MIDI 60")
    func absoluteNoteNameC4() {
        let spec = ScoreNoteSyntax(
            type: .absolute, durationBeats: 1,
            index: nil, degree: nil, midi: nil, note: "C4",
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 60, "C4 = MIDI 60, got \(notes[0].note)")
    }

    @Test("absolute note name 'Bb3' resolves to MIDI 58")
    func absoluteNoteNameBb3() {
        let spec = ScoreNoteSyntax(
            type: .absolute, durationBeats: 1,
            index: nil, degree: nil, midi: nil, note: "Bb3",
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 1)
        #expect(Int(notes[0].note) == 58, "Bb3 = MIDI 58, got \(notes[0].note)")
    }

    @Test("currentChord emits all three voices of I chord in C major")
    func currentChord() {
        let spec = ScoreNoteSyntax(
            type: .currentChord, durationBeats: 2,
            index: nil, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 80)
        #expect(notes.count == 3)
        let pitches = notes.map { Int($0.note) }.sorted()
        #expect(pitches[0] == 60, "C4")
        #expect(pitches[1] == 64, "E4")
        #expect(pitches[2] == 67, "G4")
    }

    @Test("velocity is applied correctly")
    func velocityApplied() {
        let spec = ScoreNoteSyntax(
            type: .absolute, durationBeats: 1,
            index: nil, degree: nil, midi: 60, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let h = cMajorHierarchy()
        let notes = ScorePatternCompiler.resolveNote(spec, hierarchy: h, octave: 4, voicing: .closed, velocity: 100)
        #expect(notes[0].velocity == 100)
    }
}

// MARK: - parseNoteName Tests

@Suite("ScorePatternCompiler.parseNoteName", .serialized)
struct ParseNoteNameTests {

    @Test("C4 → MIDI 60")
    func c4() {
        #expect(ScorePatternCompiler.parseNoteName("C4") == 60)
    }

    @Test("D4 → MIDI 62")
    func d4() {
        #expect(ScorePatternCompiler.parseNoteName("D4") == 62)
    }

    @Test("Bb3 → MIDI 58")
    func bb3() {
        #expect(ScorePatternCompiler.parseNoteName("Bb3") == 58)
    }

    @Test("F#5 → MIDI 78")
    func fSharp5() {
        #expect(ScorePatternCompiler.parseNoteName("F#5") == 78)
    }

    @Test("Eb4 → MIDI 63")
    func eb4() {
        #expect(ScorePatternCompiler.parseNoteName("Eb4") == 63)
    }

    @Test("G3 → MIDI 55")
    func g3() {
        #expect(ScorePatternCompiler.parseNoteName("G3") == 55)
    }

    @Test("A4 → MIDI 69")
    func a4() {
        #expect(ScorePatternCompiler.parseNoteName("A4") == 69)
    }

    @Test("D5 → MIDI 74")
    func d5() {
        #expect(ScorePatternCompiler.parseNoteName("D5") == 74)
    }

    @Test("Invalid string returns nil")
    func invalid() {
        #expect(ScorePatternCompiler.parseNoteName("NotANote") == nil)
        #expect(ScorePatternCompiler.parseNoteName("") == nil)
        #expect(ScorePatternCompiler.parseNoteName("4") == nil)
    }
}

// MARK: - Hold Merging Tests

@Suite("ScorePatternCompiler Hold Merging", .serialized)
struct HoldMergingTests {

    @Test("Single note with no holds: sustain = duration * fraction, gap = duration")
    func singleNoteNoHold() {
        let bpm = 60.0  // 1 second per beat
        let track = ScoreTrackSyntax(
            name: "T", presetFilename: "sine", numVoices: nil, octave: 4,
            voicing: .closed, sustainFraction: 0.8,
            notes: [
                ScoreNoteSyntax(type: .absolute, durationBeats: 2,
                                index: nil, degree: nil, midi: 60, note: nil,
                                octave: nil, voicing: nil, velocity: nil)
            ]
        )
        let timeline = simpleTimeline(bpm: bpm, totalBeats: 8)
        let (chords, sustains, gaps) = ScorePatternCompiler.compileTrack(
            track, timeline: timeline, bpm: bpm, loop: true
        )
        #expect(chords.count == 1)
        #expect(chords[0].count == 1)
        #expect(chords[0][0].note == 60)
        // sustain = 2 beats * 1 s/beat * 0.8 = 1.6 s
        #expect(abs(Double(sustains[0]) - 1.6) < 0.001)
        // gap = 2 beats * 1 s/beat = 2.0 s
        #expect(abs(Double(gaps[0]) - 2.0) < 0.001)
    }

    @Test("Note followed by hold: sustain extends over both, single event emitted")
    func noteFollowedByHold() {
        let bpm = 60.0
        let track = ScoreTrackSyntax(
            name: "T", presetFilename: "sine", numVoices: nil, octave: 4,
            voicing: .closed, sustainFraction: 0.9,
            notes: [
                ScoreNoteSyntax(type: .absolute, durationBeats: 1,
                                index: nil, degree: nil, midi: 60, note: nil,
                                octave: nil, voicing: nil, velocity: nil),
                ScoreNoteSyntax(type: .hold, durationBeats: 1,
                                index: nil, degree: nil, midi: nil, note: nil,
                                octave: nil, voicing: nil, velocity: nil),
                ScoreNoteSyntax(type: .hold, durationBeats: 1,
                                index: nil, degree: nil, midi: nil, note: nil,
                                octave: nil, voicing: nil, velocity: nil)
            ]
        )
        let timeline = simpleTimeline(bpm: bpm, totalBeats: 8)
        let (chords, sustains, gaps) = ScorePatternCompiler.compileTrack(
            track, timeline: timeline, bpm: bpm, loop: true
        )
        // One event: the note (holds are absorbed)
        #expect(chords.count == 1)
        // Total duration = 1+1+1 = 3 beats; sustain = 3 * 1.0 * 0.9 = 2.7
        #expect(abs(Double(sustains[0]) - 2.7) < 0.001)
        #expect(abs(Double(gaps[0]) - 3.0) < 0.001)
    }

    @Test("Rest emits empty notes with gap = rest duration")
    func restEmission() {
        let bpm = 120.0  // 0.5 s/beat
        let track = ScoreTrackSyntax(
            name: "T", presetFilename: "sine", numVoices: nil, octave: 4,
            voicing: .closed, sustainFraction: 0.85,
            notes: [
                ScoreNoteSyntax(type: .rest, durationBeats: 2,
                                index: nil, degree: nil, midi: nil, note: nil,
                                octave: nil, voicing: nil, velocity: nil)
            ]
        )
        let timeline = simpleTimeline(bpm: bpm, totalBeats: 8)
        let (chords, sustains, gaps) = ScorePatternCompiler.compileTrack(
            track, timeline: timeline, bpm: bpm, loop: true
        )
        #expect(chords.count == 1)
        #expect(chords[0].isEmpty)
        #expect(sustains[0] == 0)
        // gap = 2 beats * 0.5 s/beat = 1.0 s
        #expect(abs(Double(gaps[0]) - 1.0) < 0.001)
    }

    @Test("Note with chord change mid-track: each note resolves against its local beat")
    func chordChangeResolution() {
        // C major: beat 0 = I (C E G), beat 4 = T(3) = IV (F A C)
        let events = [
            ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                             n: nil, tVal: nil, root: nil, scale: nil),
            ChordEventSyntax(beat: 4, op: "T", degrees: nil, inversion: nil,
                             n: 3, tVal: nil, root: nil, scale: nil)
        ]
        let bpm = 60.0
        // Two notes: beat 0 (chordTone index 0 = C) and beat 4 (chordTone index 0 = F)
        let track = ScoreTrackSyntax(
            name: "T", presetFilename: "sine", numVoices: nil, octave: 4,
            voicing: .closed, sustainFraction: 0.85,
            notes: [
                ScoreNoteSyntax(type: .chordTone, durationBeats: 4,
                                index: 0, degree: nil, midi: nil, note: nil,
                                octave: nil, voicing: nil, velocity: nil),
                ScoreNoteSyntax(type: .chordTone, durationBeats: 4,
                                index: 0, degree: nil, midi: nil, note: nil,
                                octave: nil, voicing: nil, velocity: nil)
            ]
        )
        let timeline = HarmonyTimeline(
            totalBeats: 8,
            initialKey: Key(root: .C, scale: .major),
            events: events.map { HarmonyTimeline.Event(beat: $0.beat, op: $0) }
        )
        let (chords, _, _) = ScorePatternCompiler.compileTrack(
            track, timeline: timeline, bpm: bpm, loop: false
        )
        #expect(chords.count == 2)
        // First note at beat 0: I chord, tone 0 = C4 = 60
        #expect(Int(chords[0][0].note) == 60, "First note should be C4 (60), got \(chords[0][0].note)")
        // Second note at beat 4: IV chord [3,5,7], tone 0 = F4 = 65
        #expect(Int(chords[1][0].note) == 65, "Second note should be F4 (65), got \(chords[1][0].note)")
    }
}

// MARK: - Codable Round-Trip Tests

@Suite("ScorePatternSyntax Codable", .serialized)
struct ScorePatternCodableTests {

    @Test("ScoreKeySyntax round-trips")
    func keySyntaxRoundTrip() throws {
        let key = ScoreKeySyntax(root: "Bb", scale: "major")
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(ScoreKeySyntax.self, from: data)
        #expect(decoded == key)
    }

    @Test("ChordEventSyntax setChord round-trips")
    func chordEventSetChord() throws {
        let event = ChordEventSyntax(
            beat: 4.0, op: "setChord",
            degrees: [0, 2, 4], inversion: 1,
            n: nil, tVal: nil, root: nil, scale: nil
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ChordEventSyntax.self, from: data)
        #expect(decoded == event)
    }

    @Test("ChordEventSyntax T op round-trips")
    func chordEventT() throws {
        let event = ChordEventSyntax(
            beat: 8.0, op: "T",
            degrees: nil, inversion: nil,
            n: -1, tVal: nil, root: nil, scale: nil
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ChordEventSyntax.self, from: data)
        #expect(decoded == event)
    }

    @Test("ScoreNoteType raw values encode as strings")
    func noteTypeRawValues() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for t in [ScoreNoteType.rest, .hold, .currentChord, .chordTone, .scaleDegree, .absolute] {
            let data = try encoder.encode(t)
            let decoded = try decoder.decode(ScoreNoteType.self, from: data)
            #expect(decoded == t)
        }
    }

    @Test("ScoreNoteSyntax with all nil optionals round-trips")
    func noteSpecMinimal() throws {
        let note = ScoreNoteSyntax(
            type: .rest, durationBeats: 1.5,
            index: nil, degree: nil, midi: nil, note: nil,
            octave: nil, voicing: nil, velocity: nil
        )
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(ScoreNoteSyntax.self, from: data)
        #expect(decoded == note)
    }

    @Test("ScoreNoteSyntax with all fields round-trips")
    func noteSpecFull() throws {
        let note = ScoreNoteSyntax(
            type: .chordTone, durationBeats: 0.5,
            index: 2, degree: nil, midi: nil, note: nil,
            octave: 5, voicing: .open, velocity: 100
        )
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(ScoreNoteSyntax.self, from: data)
        #expect(decoded == note)
    }

    @Test("Full ScorePatternSyntax round-trips")
    func fullScoreRoundTrip() throws {
        let score = ScorePatternSyntax(
            bpm: 120,
            totalBeats: 8,
            loop: true,
            key: ScoreKeySyntax(root: "C", scale: "major"),
            chordEvents: [
                ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                                 n: nil, tVal: nil, root: nil, scale: nil),
                ChordEventSyntax(beat: 4, op: "T", degrees: nil, inversion: nil,
                                 n: 3, tVal: nil, root: nil, scale: nil)
            ],
            tracks: [
                ScoreTrackSyntax(
                    name: "Chords",
                    presetFilename: "auroraBorealis",
                    numVoices: 8,
                    octave: 4,
                    voicing: .closed,
                    sustainFraction: 0.9,
                    notes: [
                        ScoreNoteSyntax(type: .currentChord, durationBeats: 4,
                                        index: nil, degree: nil, midi: nil, note: nil,
                                        octave: nil, voicing: nil, velocity: nil),
                        ScoreNoteSyntax(type: .currentChord, durationBeats: 4,
                                        index: nil, degree: nil, midi: nil, note: nil,
                                        octave: nil, voicing: nil, velocity: nil)
                    ]
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(score)
        let decoded = try JSONDecoder().decode(ScorePatternSyntax.self, from: data)
        #expect(decoded.bpm == score.bpm)
        #expect(decoded.totalBeats == score.totalBeats)
        #expect(decoded.loop == score.loop)
        #expect(decoded.key == score.key)
        #expect(decoded.chordEvents.count == score.chordEvents.count)
        #expect(decoded.tracks.count == score.tracks.count)
        #expect(decoded.tracks[0].name == "Chords")
        #expect(decoded.tracks[0].notes.count == 2)
    }
}

// MARK: - buildTimeline Tests

@Suite("ScorePatternCompiler buildTimeline", .serialized)
struct BuildTimelineTests {

    @Test("buildTimeline constructs correct initial key")
    func correctInitialKey() {
        let score = ScorePatternSyntax(
            bpm: 120, totalBeats: 8, loop: true,
            key: ScoreKeySyntax(root: "G", scale: "minor"),
            chordEvents: [],
            tracks: []
        )
        let timeline = ScorePatternCompiler.buildTimeline(score)
        #expect(timeline.initialKey.root == NoteClass.G)
        #expect(timeline.initialKey.scale == Scale.minor)
    }

    @Test("buildTimeline sorts unsorted events by beat")
    func sortsByBeat() {
        let score = ScorePatternSyntax(
            bpm: 120, totalBeats: 8, loop: true,
            key: ScoreKeySyntax(root: "C", scale: "major"),
            chordEvents: [
                ChordEventSyntax(beat: 4, op: "T", degrees: nil, inversion: nil,
                                 n: 1, tVal: nil, root: nil, scale: nil),
                ChordEventSyntax(beat: 0, op: "setChord", degrees: [0, 2, 4], inversion: 0,
                                 n: nil, tVal: nil, root: nil, scale: nil)
            ],
            tracks: []
        )
        let timeline = ScorePatternCompiler.buildTimeline(score)
        #expect(timeline.events.count == 2)
        #expect(timeline.events[0].beat == 0.0)
        #expect(timeline.events[1].beat == 4.0)
    }
}

// MARK: - setRoman Tests

/// Helper: build a one-event timeline in C major and query state at beat 0.
private func romanState(_ roman: String, key: Key = Key(root: .C, scale: .major))
    -> (key: Key, chord: ChordInScale)
{
    let event = ChordEventSyntax(beat: 0, op: "setRoman", roman: roman)
    let evs = [HarmonyTimeline.Event(beat: 0, op: event)]
    let timeline = HarmonyTimeline(totalBeats: 16, initialKey: key, events: evs)
    return timeline.state(at: 0, loop: false)
}

@Suite("HarmonyTimeline setRoman", .serialized)
struct SetRomanTests {

    // MARK: Diatonic triads

    @Test("I → degrees [0,2,4] root position, key unchanged")
    func romanI() {
        let (key, chord) = romanState("I")
        #expect(chord.degrees == [0, 2, 4])
        #expect(chord.inversion == 0)
        #expect(key.root == NoteClass.C)
        #expect(key.scale == Scale.major)
    }

    @Test("ii → degrees [1,3,5] root position")
    func romanII() {
        let (_, chord) = romanState("ii")
        #expect(chord.degrees == [1, 3, 5])
        #expect(chord.inversion == 0)
    }

    @Test("IV → degrees [3,5,7]")
    func romanIV() {
        let (_, chord) = romanState("IV")
        #expect(chord.degrees == [3, 5, 7])
    }

    @Test("V → degrees [4,6,8]")
    func romanV() {
        let (_, chord) = romanState("V")
        #expect(chord.degrees == [4, 6, 8])
    }

    @Test("vi → degrees [5,7,9]")
    func romanVI() {
        let (_, chord) = romanState("vi")
        #expect(chord.degrees == [5, 7, 9])
    }

    @Test("viio → degrees [6,8,10], dim quality consumed")
    func romanVIIo() {
        let (_, chord) = romanState("viio")
        #expect(chord.degrees == [6, 8, 10])
        #expect(chord.inversion == 0)
    }

    // MARK: Seventh chords

    @Test("V7 → degrees [4,6,8,10]")
    func romanV7() {
        let (_, chord) = romanState("V7")
        #expect(chord.degrees == [4, 6, 8, 10])
        #expect(chord.inversion == 0)
    }

    @Test("viio7 → degrees [6,8,10,12]")
    func romanVIIo7() {
        let (_, chord) = romanState("viio7")
        #expect(chord.degrees == [6, 8, 10, 12])
    }

    @Test("ii/o7 → degrees [1,3,5,7] (half-dim, /o consumed)")
    func romanIIhalfDim7() {
        let (_, chord) = romanState("ii/o7")
        #expect(chord.degrees == [1, 3, 5, 7])
        #expect(chord.inversion == 0)
    }

    // MARK: Inversions from figured bass

    @Test("I6 → triad, 1st inversion")
    func romanI6() {
        let (_, chord) = romanState("I6")
        #expect(chord.degrees == [0, 2, 4])
        #expect(chord.inversion == 1)
    }

    @Test("I6/4 → triad, 2nd inversion")
    func romanI64() {
        let (_, chord) = romanState("I6/4")
        #expect(chord.degrees == [0, 2, 4])
        #expect(chord.inversion == 2)
    }

    @Test("V6/5 → seventh, 1st inversion")
    func romanV65() {
        let (_, chord) = romanState("V6/5")
        #expect(chord.degrees == [4, 6, 8, 10])
        #expect(chord.inversion == 1)
    }

    @Test("ii6/5 → degrees [1,3,5,7] 1st inversion")
    func romanII65() {
        let (_, chord) = romanState("ii6/5")
        #expect(chord.degrees == [1, 3, 5, 7])
        #expect(chord.inversion == 1)
    }

    @Test("V4/3 → seventh, 2nd inversion")
    func romanV43() {
        let (_, chord) = romanState("V4/3")
        #expect(chord.degrees == [4, 6, 8, 10])
        #expect(chord.inversion == 2)
    }

    @Test("V2 → seventh, 3rd inversion")
    func romanV2() {
        let (_, chord) = romanState("V2")
        #expect(chord.degrees == [4, 6, 8, 10])
        #expect(chord.inversion == 3)
    }

    @Test("viio6/5 → [6,8,10,12] 1st inversion (quality+figure)")
    func romanVIIo65() {
        let (_, chord) = romanState("viio6/5")
        #expect(chord.degrees == [6, 8, 10, 12])
        #expect(chord.inversion == 1)
    }

    @Test("ii/o6/5 → [1,3,5,7] 1st inversion")
    func romanIIhalfDim65() {
        let (_, chord) = romanState("ii/o6/5")
        #expect(chord.degrees == [1, 3, 5, 7])
        #expect(chord.inversion == 1)
    }

    // MARK: Applied chords (tonicization)

    @Test("V/V in C major → chord [4,6,8] in G major")
    func romanVofV() {
        let (key, chord) = romanState("V/V")
        // V of C = G → key changes to G major
        #expect(key.root == NoteClass.G)
        #expect(key.scale == Scale.major)
        // V in G major = scale degrees [4,6,8]
        #expect(chord.degrees == [4, 6, 8])
        #expect(chord.inversion == 0)
    }

    @Test("V/vi in C major → chord [4,6,8] in A minor")
    func romanVofVI() {
        let (key, chord) = romanState("V/vi")
        // vi of C = A → key changes to A minor (lowercase target)
        #expect(key.root == NoteClass.A)
        #expect(key.scale == Scale.minor)
        #expect(chord.degrees == [4, 6, 8])
    }

    @Test("V/IV in C major → key changes to F major")
    func romanVofIV() {
        let (key, chord) = romanState("V/IV")
        #expect(key.root == NoteClass.F)
        #expect(key.scale == Scale.major)
        #expect(chord.degrees == [4, 6, 8])
    }

    @Test("V7/V in C major → seventh chord in G major")
    func romanV7ofV() {
        let (key, chord) = romanState("V7/V")
        #expect(key.root == NoteClass.G)
        #expect(key.scale == Scale.major)
        #expect(chord.degrees == [4, 6, 8, 10])
        #expect(chord.inversion == 0)
    }

    @Test("viio7/V in C major → [6,8,10,12] in G major")
    func romanVIIo7ofV() {
        let (key, chord) = romanState("viio7/V")
        #expect(key.root == NoteClass.G)
        #expect(chord.degrees == [6, 8, 10, 12])
    }

    @Test("V6/5/IV in C major → [4,6,8,10] inv=1 in F major")
    func romanV65ofIV() {
        let (key, chord) = romanState("V6/5/IV")
        #expect(key.root == NoteClass.F)
        #expect(key.scale == Scale.major)
        #expect(chord.degrees == [4, 6, 8, 10])
        #expect(chord.inversion == 1)
    }

    // MARK: Unsupported symbols → no chord change

    @Test("N6 is unsupported → fallback chord unchanged")
    func romanN6Unsupported() {
        // Timeline with only N6 event; fallback chord is [0,2,4]
        let (_, chord) = romanState("N6")
        #expect(chord.degrees == [0, 2, 4], "Unsupported N6 should leave fallback chord")
    }

    @Test("Ger6/5 is unsupported → fallback chord unchanged")
    func romanGerUnsupported() {
        let (_, chord) = romanState("Ger6/5")
        #expect(chord.degrees == [0, 2, 4])
    }

    @Test("bII is unsupported → fallback chord unchanged")
    func romanBIIUnsupported() {
        let (_, chord) = romanState("bII")
        #expect(chord.degrees == [0, 2, 4])
    }

    @Test("It6 is unsupported → fallback chord unchanged")
    func romanIt6Unsupported() {
        let (_, chord) = romanState("It6")
        #expect(chord.degrees == [0, 2, 4])
    }

    // MARK: Codable round-trip with roman field

    @Test("ChordEventSyntax setRoman round-trips through JSON")
    func setRomanCodable() throws {
        let event = ChordEventSyntax(beat: 4.0, op: "setRoman", roman: "V7/V")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ChordEventSyntax.self, from: data)
        #expect(decoded.op == "setRoman")
        #expect(decoded.roman == "V7/V")
        #expect(decoded.beat == 4.0)
    }

    @Test("setRoman event fires correctly at the right beat in a multi-event timeline")
    func setRomanBeatBoundary() {
        let events = [
            ChordEventSyntax(beat: 0, op: "setRoman", roman: "I"),
            ChordEventSyntax(beat: 4, op: "setRoman", roman: "V7")
        ]
        let evs = events.map { HarmonyTimeline.Event(beat: $0.beat, op: $0) }
        let timeline = HarmonyTimeline(
            totalBeats: 8,
            initialKey: Key(root: .C, scale: .major),
            events: evs
        )
        let (_, before) = timeline.state(at: 3.9, loop: false)
        let (_, after) = timeline.state(at: 4.0, loop: false)
        #expect(before.degrees == [0, 2, 4])
        #expect(after.degrees == [4, 6, 8, 10])
    }
}
