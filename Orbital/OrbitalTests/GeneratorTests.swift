//
//  GeneratorTests.swift
//  OrbitalTests
//
//  Tests for the chorale-based GeneratorSyntax, GeneratorEngine, and
//  PatternSyntax.generatorTracks.
//

import Testing
import Foundation
@testable import Orbital

// MARK: - GeneratorEngine Tests

@Suite("GeneratorEngineTests", .serialized)
struct GeneratorEngineTests {

    // MARK: - Chord events

    @Test("fourChords produces setRoman events for I, V, vi, IV")
    func fourChordsMajorProducesCorrectChordEvents() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad)
        let score = GeneratorEngine.generate(params)

        let romanEvents = score.chordEvents.filter { $0.op == "setRoman" }
        let romans = romanEvents.map { $0.roman ?? "" }

        #expect(romanEvents.count == 4)
        #expect(romans.contains("I"))
        #expect(romans.contains("V"))
        #expect(romans.contains("vi"))
        #expect(romans.contains("IV"))
    }

    @Test("seventh chord type has degrees [0, 2, 4, 6]")
    func seventhChordTypeProducesDegreesZero246() {
        #expect(GeneratorChordType.seventh.degrees == [0, 2, 4, 6])
    }

    @Test("triad chord type has degrees [0, 2, 4]")
    func triadChordTypeProducesDegreesZero24() {
        #expect(GeneratorChordType.triad.degrees == [0, 2, 4])
    }

    @Test("dyad chord type has degrees [0, 4]")
    func dyadChordTypeProducesDegreesZero4() {
        #expect(GeneratorChordType.dyad.degrees == [0, 4])
    }

    @Test("drone motion produces a single setRoman or setChord event")
    func droneMotionProducesSingleChordEvent() {
        let params = GeneratorSyntax(motion: .drone, chordType: .triad)
        let score = GeneratorEngine.generate(params)

        let chordChangingEvents = score.chordEvents.filter { $0.op != "setKey" }
        #expect(chordChangingEvents.count == 1)
        #expect(chordChangingEvents[0].beat == 0)
    }

    @Test("descendingFifths motion produces 8 chord events")
    func descendingFifthsProducesEightEvents() {
        let params = GeneratorSyntax(motion: .descendingFifths, chordType: .triad)
        let score = GeneratorEngine.generate(params)

        let romanEvents = score.chordEvents.filter { $0.op == "setRoman" }
        #expect(romanEvents.count == 8)
    }

    @Test("lPowers motion emits one Tt event per sequence element")
    func lPowersProducesTtEvents() {
        let params = GeneratorSyntax(
            motion: .lPowers, chordType: .triad,
            lPowerSequence: [2, -1, 3]
        )
        let score = GeneratorEngine.generate(params)
        let ttEvents = score.chordEvents.filter { $0.op == "Tt" }
        #expect(ttEvents.count == 3)
        // Each element p emits Tt with n = p * -5 and tVal = p * 2 for triads.
        #expect(ttEvents.contains { $0.n == -10 && $0.tVal == 4 })
        #expect(ttEvents.contains { $0.n == 5 && $0.tVal == -2 })
        #expect(ttEvents.contains { $0.n == -15 && $0.tVal == 6 })
    }

    // MARK: - Track structure

    @Test("triad produces 1 bass + 3 upper = 4 tracks")
    func triadProducesFourTracks() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 4)
        #expect(score.tracks[0].name == "Bass")
    }

    @Test("dyad produces 1 bass + 2 upper = 3 tracks")
    func dyadProducesThreeTracks() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .dyad)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 3)
    }

    @Test("seventh produces 1 bass + 4 upper = 5 tracks")
    func seventhProducesFiveTracks() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .seventh)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 5)
    }

    @Test("bass track contains absolute MIDI notes")
    func bassTrackUsesAbsoluteMidi() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad)
        let score = GeneratorEngine.generate(params)
        let bass = score.tracks[0]
        #expect(!bass.notes.isEmpty)
        for note in bass.notes where note.type != .rest && note.type != .hold {
            #expect(note.type == .absolute)
            #expect(note.midi != nil)
        }
    }

    @Test("upper voice MIDI pitches stay within configured range")
    func upperVoicesStayInRange() {
        let params = GeneratorSyntax(
            motion: .fourChords, chordType: .triad,
            upperVoiceLowOctave: 3, upperVoiceHighOctave: 5
        )
        let score = GeneratorEngine.generate(params)
        let lowMidi = (3 + 1) * 12       // 48
        let highMidi = (5 + 1) * 12 + 11 // 83
        for track in score.tracks.dropFirst() {
            for note in track.notes where note.type == .absolute {
                if let midi = note.midi {
                    #expect(midi >= lowMidi && midi <= highMidi,
                            "MIDI \(midi) outside [\(lowMidi), \(highMidi)]")
                }
            }
        }
    }

    @Test("pad track totalBeats matches beatsPerChord × chordCount")
    func padTotalBeatsMatchesExpected() {
        let params = GeneratorSyntax(
            motion: .fourChords, chordType: .triad,
            bpm: 120, beatsPerChord: 4
        )
        let score = GeneratorEngine.generate(params)
        #expect(score.totalBeats == 16)
    }

    // MARK: - Debussy scale events

    @Test("acousticBridge contains setKey events")
    func acousticBridgeContainsSetKeyEvents() {
        let params = GeneratorSyntax(
            rootNote: "C", scaleType: .major,
            motion: .acousticBridge, chordType: .triad
        )
        let score = GeneratorEngine.generate(params)

        let keyEvents = score.chordEvents.filter { $0.op == "setKey" }
        #expect(keyEvents.count >= 4)

        let scaleNames = keyEvents.compactMap { $0.scale }
        #expect(scaleNames.contains(GeneratorScaleType.acoustic.tonicScaleName))
        #expect(scaleNames.contains(GeneratorScaleType.wholeTone.tonicScaleName))
    }

    @Test("parallelAscending produces only T(+1) chord events after beat 0")
    func parallelAscendingProducesOnlyTPlus1Events() {
        let params = GeneratorSyntax(
            scaleType: .wholeTone, motion: .parallelAscending, chordType: .triad
        )
        let score = GeneratorEngine.generate(params)

        let tEvents = score.chordEvents.filter { $0.op == "T" && $0.beat > 0 }
        #expect(!tEvents.isEmpty)
        #expect(tEvents.allSatisfy { $0.n == 1 })
    }

    // MARK: - Reproducibility

    @Test("same seed produces same output")
    func sameSeedProducesSameOutput() {
        let params = GeneratorSyntax(
            motion: .randomWalk, chordType: .triad, randomSeed: 42
        )
        let score1 = GeneratorEngine.generate(params)
        let score2 = GeneratorEngine.generate(params)

        let events1 = score1.chordEvents.map { "\($0.beat)-\($0.op)-\($0.n ?? 0)" }
        let events2 = score2.chordEvents.map { "\($0.beat)-\($0.op)-\($0.n ?? 0)" }
        #expect(events1 == events2)

        let midis1 = score1.tracks.first?.notes.map { $0.midi ?? -1 } ?? []
        let midis2 = score2.tracks.first?.notes.map { $0.midi ?? -1 } ?? []
        #expect(midis1 == midis2)
    }

    // MARK: - Scale type properties

    @Test("acoustic scale maps to lydianFlat7 Tonic name")
    func acousticScaleMapsToLydianFlat7() {
        #expect(GeneratorScaleType.acoustic.tonicScaleName == "lydianFlat7")
    }

    @Test("non-diatonic scales do not support functional motion")
    func nonDiatonicScalesNotFunctional() {
        let nonFunctional: [GeneratorScaleType] = [.wholeTone, .octatonic, .hexatonic, .acoustic]
        for scale in nonFunctional {
            #expect(!scale.supportsFunctionalMotion)
        }
    }
}

// MARK: - GeneratorSyntax Codable Tests

@Suite("GeneratorSyntaxCodableTests", .serialized)
struct GeneratorSyntaxCodableTests {

    @Test("GeneratorSyntax round-trips through JSON")
    func generatorSyntaxRoundTripsJSON() throws {
        let original = GeneratorSyntax(
            rootNote: "F#",
            scaleType: .dorian,
            motion: .descendingThirds,
            chordType: .seventh,
            bpm: 72,
            beatsPerChord: 2,
            oUCHMode: .fixedClosed,
            bassOctave: 2,
            upperVoiceLowOctave: 3,
            upperVoiceHighOctave: 6,
            bassPresetName: "moog_sub_bass",
            upperPresetNames: ["warm_analog_pad", "solina_strings", "solina_strings", "solina_strings"],
            lPowerSequence: [2, -1, 3],
            randomSeed: 777
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GeneratorSyntax.self, from: data)

        #expect(decoded == original)
    }

    @Test("GeneratorSyntax encodes chord type as raw value")
    func generatorSyntaxEncodesEnumRawValues() throws {
        let params = GeneratorSyntax(
            scaleType: .wholeTone, motion: .parallelAscending, chordType: .seventh,
            oUCHMode: .stochastic
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(json.contains("\"wholeTone\""))
        #expect(json.contains("\"parallelAscending\""))
        #expect(json.contains("\"seventh\""))
        #expect(json.contains("\"stochastic\""))
    }

    @Test("PatternSyntax with generatorTracks round-trips through JSON")
    func patternSyntaxWithGeneratorTracksRoundTrips() throws {
        let gen = GeneratorSyntax(motion: .shuttle, chordType: .triad, randomSeed: 1)
        let pattern = PatternSyntax(generatorTracks: gen)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(pattern)
        let decoded = try decoder.decode(PatternSyntax.self, from: data)

        #expect(decoded.generatorTracks == gen)
        #expect(decoded.midiTracks == nil)
        #expect(decoded.tableTracks == nil)
        #expect(decoded.scoreTracks == nil)
    }

    @Test("PatternSyntax compileTrackInfoOnly dispatches through generatorTracks")
    func patternSyntaxCompilesGeneratorTracks() {
        let gen = GeneratorSyntax(
            motion: .fourChords, chordType: .triad, randomSeed: 42
        )
        let pattern = PatternSyntax(generatorTracks: gen)

        let trackInfos = pattern.compileTrackInfoOnly()
        // bass + triad = 4 tracks
        #expect(trackInfos.count == 4)
    }
}
