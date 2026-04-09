//
//  GeneratorTests.swift
//  OrbitalTests
//
//  Tests for GeneratorSyntax, GeneratorEngine, and PatternSyntax.generatorTracks.
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
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad, texture: .pad)
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
        let degrees = GeneratorChordType.seventh.degrees
        #expect(degrees == [0, 2, 4, 6])
    }

    @Test("drone motion produces a single setRoman or setChord event")
    func droneMotionProducesSingleChordEvent() {
        let params = GeneratorSyntax(motion: .drone, chordType: .triad, texture: .pad)
        let score = GeneratorEngine.generate(params)

        // Drone = only 1 setChord or setRoman at beat 0, nothing else
        let chordChangingEvents = score.chordEvents.filter { $0.op != "setKey" }
        #expect(chordChangingEvents.count == 1)
        #expect(chordChangingEvents[0].beat == 0)
    }

    @Test("descendingFifths motion produces 8 chord events")
    func descendingFifthsProducesEightEvents() {
        let params = GeneratorSyntax(motion: .descendingFifths, chordType: .triad, texture: .pad)
        let score = GeneratorEngine.generate(params)

        let romanEvents = score.chordEvents.filter { $0.op == "setRoman" }
        #expect(romanEvents.count == 8)
    }

    // MARK: - Texture / track count

    @Test("SATB texture produces exactly 4 tracks")
    func satbTextureProducesFourTracks() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad, texture: .satb)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 4)
    }

    @Test("pad texture produces exactly 1 track")
    func padTextureProducesOneTrack() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad, texture: .pad)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 1)
    }

    @Test("full texture produces exactly 3 tracks")
    func fullTextureProducesThreeTracks() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad, texture: .full)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 3)
    }

    @Test("bassAndMelody texture produces exactly 2 tracks")
    func bassAndMelodyProducesTwoTracks() {
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad, texture: .bassAndMelody)
        let score = GeneratorEngine.generate(params)
        #expect(score.tracks.count == 2)
    }

    // MARK: - Note counts

    @Test("arpeggio track note count = chordSize × chordCount")
    func arpeggioTrackHasNoteCountOfChordSizeTimesChordCount() {
        // fourChords = 4 chords, triad = 3 notes per chord → 12 notes total
        let params = GeneratorSyntax(motion: .fourChords, chordType: .triad, texture: .arpeggio)
        let score = GeneratorEngine.generate(params)

        #expect(score.tracks.count == 1)
        let nonHoldNotes = score.tracks[0].notes.filter { $0.type != .hold }
        // 4 chords × 3 chord tones each
        #expect(nonHoldNotes.count == 4 * 3)
    }

    @Test("seventh chord arpeggio track note count = 4 × chordCount")
    func seventhArpeggioHasCorrectNoteCount() {
        let params = GeneratorSyntax(motion: .shuttle, chordType: .seventh, texture: .arpeggio)
        let score = GeneratorEngine.generate(params)

        let notes = score.tracks[0].notes.filter { $0.type != .hold }
        // 2 chords × 4 notes each
        #expect(notes.count == 2 * 4)
    }

    @Test("pad track totalBeats matches beatsPerChord × chordCount")
    func padTotalBeatsMatchesExpected() {
        let params = GeneratorSyntax(
            motion: .fourChords, chordType: .triad,
            texture: .pad, bpm: 120, beatsPerChord: 4
        )
        let score = GeneratorEngine.generate(params)
        // fourChords = 4 chord events, beatsPerChord = 4 → totalBeats = 16
        #expect(score.totalBeats == 16)
    }

    // MARK: - Debussy scale events

    @Test("acousticBridge contains setKey events")
    func acousticBridgeContainsSetKeyEvents() {
        let params = GeneratorSyntax(
            rootNote: "C", scaleType: .major,
            motion: .acousticBridge, chordType: .triad, texture: .pad
        )
        let score = GeneratorEngine.generate(params)

        let keyEvents = score.chordEvents.filter { $0.op == "setKey" }
        #expect(keyEvents.count >= 4)  // diatonic→acoustic→wholeTone→acoustic→diatonic

        let scaleNames = keyEvents.compactMap { $0.scale }
        #expect(scaleNames.contains(GeneratorScaleType.acoustic.tonicScaleName))
        #expect(scaleNames.contains(GeneratorScaleType.wholeTone.tonicScaleName))
    }

    @Test("octatonicImmersion contains setKey events for octatonic and diatonic")
    func octatonicImmersionContainsSetKeyEvents() {
        let params = GeneratorSyntax(
            rootNote: "C", scaleType: .major,
            motion: .octatonicImmersion, chordType: .triad, texture: .pad
        )
        let score = GeneratorEngine.generate(params)

        let keyEvents = score.chordEvents.filter { $0.op == "setKey" }
        #expect(keyEvents.count >= 2)

        let scaleNames = keyEvents.compactMap { $0.scale }
        #expect(scaleNames.contains(GeneratorScaleType.octatonic.tonicScaleName))
    }

    @Test("parallelAscending produces only T(+1) chord events after beat 0")
    func parallelAscendingProducesOnlyTPlus1Events() {
        let params = GeneratorSyntax(
            scaleType: .wholeTone, motion: .parallelAscending,
            chordType: .triad, texture: .pad
        )
        let score = GeneratorEngine.generate(params)

        let tEvents = score.chordEvents.filter { $0.op == "T" && $0.beat > 0 }
        #expect(!tEvents.isEmpty)
        #expect(tEvents.allSatisfy { $0.n == 1 })
    }

    @Test("parallelDescending produces only T(-1) chord events after beat 0")
    func parallelDescendingProducesOnlyTMinus1Events() {
        let params = GeneratorSyntax(
            scaleType: .wholeTone, motion: .parallelDescending,
            chordType: .triad, texture: .pad
        )
        let score = GeneratorEngine.generate(params)

        let tEvents = score.chordEvents.filter { $0.op == "T" && $0.beat > 0 }
        #expect(!tEvents.isEmpty)
        #expect(tEvents.allSatisfy { $0.n == -1 })
    }

    // MARK: - Reproducibility

    @Test("same seed produces same output")
    func sameSeedProducesSameOutput() {
        let params = GeneratorSyntax(
            motion: .randomWalk, chordType: .triad, texture: .melody, randomSeed: 42
        )
        let score1 = GeneratorEngine.generate(params)
        let score2 = GeneratorEngine.generate(params)

        let events1 = score1.chordEvents.map { "\($0.beat)-\($0.op)-\($0.n ?? 0)" }
        let events2 = score2.chordEvents.map { "\($0.beat)-\($0.op)-\($0.n ?? 0)" }
        #expect(events1 == events2)

        let notes1 = score1.tracks.first?.notes.map { "\($0.type)-\($0.durationBeats)" } ?? []
        let notes2 = score2.tracks.first?.notes.map { "\($0.type)-\($0.durationBeats)" } ?? []
        #expect(notes1 == notes2)
    }

    @Test("different seeds produce different melody note patterns")
    func differentSeedsProduceDifferentOutput() {
        let p1 = GeneratorSyntax(motion: .randomWalk, chordType: .triad, texture: .melody, randomSeed: 1)
        let p2 = GeneratorSyntax(motion: .randomWalk, chordType: .triad, texture: .melody, randomSeed: 999)

        let s1 = GeneratorEngine.generate(p1)
        let s2 = GeneratorEngine.generate(p2)

        let chords1 = s1.chordEvents.map { $0.n ?? 0 }
        let chords2 = s2.chordEvents.map { $0.n ?? 0 }
        // Very likely to differ for different seeds; if not, at least notes differ
        let notes1 = s1.tracks.first?.notes.map { "\($0.type)-\($0.durationBeats)" } ?? []
        let notes2 = s2.tracks.first?.notes.map { "\($0.type)-\($0.durationBeats)" } ?? []
        #expect(chords1 != chords2 || notes1 != notes2)
    }

    // MARK: - Scale type properties

    @Test("acoustic scale maps to lydianFlat7 Tonic name")
    func acousticScaleMapsToLydianFlat7() {
        #expect(GeneratorScaleType.acoustic.tonicScaleName == "lydianFlat7")
    }

    @Test("wholeTone scale maps to whole Tonic name")
    func wholeToneScaleMapsToWhole() {
        #expect(GeneratorScaleType.wholeTone.tonicScaleName == "whole")
    }

    @Test("octatonic scale maps to wholeDiminished Tonic name")
    func octatonicScaleMapsToWholeDiminished() {
        #expect(GeneratorScaleType.octatonic.tonicScaleName == "wholeDiminished")
    }

    @Test("non-diatonic scales do not support functional motion")
    func nonDiatonicScalesNotFunctional() {
        let nonFunctional: [GeneratorScaleType] = [.wholeTone, .octatonic, .hexatonic, .acoustic]
        for scale in nonFunctional {
            #expect(!scale.supportsFunctionalMotion, "Expected \(scale) to not support functional motion")
        }
    }

    @Test("diatonic scales support functional motion")
    func diatonicScalesSupportFunctionalMotion() {
        let functional: [GeneratorScaleType] = [.major, .naturalMinor, .dorian, .mixolydian, .lydian]
        for scale in functional {
            #expect(scale.supportsFunctionalMotion, "Expected \(scale) to support functional motion")
        }
    }

    // MARK: - Default presets

    @Test("SATB default presets returns 4 entries")
    func satbDefaultPresetsFourEntries() {
        let presets = GeneratorEngine.defaultPresets(.satb)
        #expect(presets.count == 4)
    }

    @Test("full default presets returns 3 entries")
    func fullDefaultPresetsThreeEntries() {
        let presets = GeneratorEngine.defaultPresets(.full)
        #expect(presets.count == 3)
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
            texture: .satb,
            bpm: 72,
            beatsPerChord: 2,
            voicing: .open,
            randomSeed: 777,
            presetNames: ["warm_analog_pad", "solina_strings"]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GeneratorSyntax.self, from: data)

        #expect(decoded == original)
    }

    @Test("GeneratorSyntax encodes all enum cases as raw values")
    func generatorSyntaxEncodesEnumRawValues() throws {
        let params = GeneratorSyntax(
            scaleType: .wholeTone,
            motion: .parallelAscending,
            chordType: .shell,
            texture: .arpeggio
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(json.contains("\"wholeTone\""))
        #expect(json.contains("\"parallelAscending\""))
        #expect(json.contains("\"shell\""))
        #expect(json.contains("\"arpeggio\""))
    }

    @Test("PatternSyntax with generatorTracks round-trips through JSON")
    func patternSyntaxWithGeneratorTracksRoundTrips() throws {
        let gen = GeneratorSyntax(motion: .shuttle, chordType: .triad, texture: .pad, randomSeed: 1)
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
            motion: .fourChords, chordType: .triad, texture: .satb, randomSeed: 42
        )
        let pattern = PatternSyntax(generatorTracks: gen)

        let trackInfos = pattern.compileTrackInfoOnly()
        // SATB = 4 tracks
        #expect(trackInfos.count == 4)
    }
}
