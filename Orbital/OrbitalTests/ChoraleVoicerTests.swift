//
//  ChoraleVoicerTests.swift
//  OrbitalTests
//
//  Tests for the voice-leading constraint solver.
//

import Testing
import Foundation
@testable import Orbital

// MARK: - ChoraleVoicerTests

@Suite("ChoraleVoicerTests", .serialized)
struct ChoraleVoicerTests {

    private var voicer: ChoraleVoicer {
        var c = VoicingConstraints.default
        c.upperVoiceRange = 48...84
        return ChoraleVoicer(constraints: c)
    }

    // MARK: - Initial voicing

    @Test("First chord (no previous) fits within range and matches target configuration")
    func firstChordWithTargetClosed() {
        let pitches = voicer.voice(
            previousUpper: [],
            previousBass: 0,
            nextChordPCs: [0, 4, 7], // C major triad
            nextBass: 36,            // C2
            upperVoiceCount: 3,
            targetConfiguration: .closed,
            scaleRootPC: 0
        )
        #expect(pitches.count == 3)
        #expect(pitches.allSatisfy { (48...84).contains($0) })
        #expect(pitches[2] - pitches[0] < 12, "closed configuration should span < 1 octave")
    }

    @Test("Open configuration spans ≥ octave")
    func firstChordWithTargetOpen() {
        let pitches = voicer.voice(
            previousUpper: [],
            previousBass: 0,
            nextChordPCs: [0, 4, 7],
            nextBass: 36,
            upperVoiceCount: 3,
            targetConfiguration: .open,
            scaleRootPC: 0
        )
        #expect(pitches.count == 3)
        #expect(pitches[2] - pitches[0] >= 12, "open configuration should span ≥ 1 octave")
    }

    // MARK: - V→I voice leading

    @Test("V → I produces minimal-motion voice leading (triad, closed)")
    func vToIClosedVoiceLeading() {
        // Previous: V chord in C major with upper voices voicing {G, B, D}, bass G2
        let previousUpper = [67, 71, 74] // G4, B4, D5
        let previousBass = 43            // G2

        // Next: I chord — upper voices should voice {C, E, G} with minimal motion
        let next = voicer.voice(
            previousUpper: previousUpper,
            previousBass: previousBass,
            nextChordPCs: [0, 4, 7],      // C, E, G
            nextBass: 36,                  // C2
            upperVoiceCount: 3,
            targetConfiguration: .closed,
            scaleRootPC: 0
        )

        // Each voice should move by a small amount (≤ 5 semitones is comfortable).
        var totalMotion = 0
        for (prev, new) in zip(previousUpper, next) {
            totalMotion += abs(new - prev)
        }
        #expect(totalMotion <= 9, "V→I should have minimal voice motion; got \(totalMotion)")
    }

    // MARK: - Leading-tone doubling

    @Test("Leading tone is not doubled across bass+upper voices in V chord")
    func leadingToneNotDoubled() {
        // V in C major: bass=G2=43, upper voices should not include 2 B's
        // (B is scale degree 7 / leading tone of C major)
        let next = voicer.voice(
            previousUpper: [],
            previousBass: 0,
            nextChordPCs: [7, 11, 2],      // G, B, D
            nextBass: 43,                   // G2
            upperVoiceCount: 3,
            targetConfiguration: .closed,
            scaleRootPC: 0
        )
        let pcs = next.map { ((($0 % 12) + 12) % 12) }
        let leadingTonePC = 11             // B in C major
        let leadingToneCount = pcs.filter { $0 == leadingTonePC }.count
        // Bass is G (not a leading tone), so upper voices can have at most 1 B.
        #expect(leadingToneCount <= 1)
    }

    // MARK: - Seventh chord (no OUCH target)

    @Test("Seventh chord produces 4 upper voices covering 4 distinct chord tones")
    func seventhChordAllTonesPresent() {
        let next = voicer.voice(
            previousUpper: [],
            previousBass: 0,
            nextChordPCs: [0, 4, 7, 10],   // C7
            nextBass: 36,
            upperVoiceCount: 4,
            targetConfiguration: nil,
            scaleRootPC: 0
        )
        #expect(next.count == 4)
        let pcs = Set(next.map { ((($0 % 12) + 12) % 12) })
        #expect(pcs.count == 4, "all 4 chord tones should appear in upper voices")
    }

    // MARK: - No voice crossing

    @Test("Upper voices are ascending (no crossing)")
    func upperVoicesAscending() {
        let next = voicer.voice(
            previousUpper: [],
            previousBass: 0,
            nextChordPCs: [0, 4, 7],
            nextBass: 36,
            upperVoiceCount: 3,
            targetConfiguration: .closed,
            scaleRootPC: 0
        )
        for i in 1..<next.count {
            #expect(next[i] >= next[i - 1], "voices must ascend or equal (no crossings)")
        }
    }

    @Test("All upper voices are above the bass")
    func upperVoicesAboveBass() {
        let next = voicer.voice(
            previousUpper: [],
            previousBass: 0,
            nextChordPCs: [0, 4, 7],
            nextBass: 36,
            upperVoiceCount: 3,
            targetConfiguration: .closed,
            scaleRootPC: 0
        )
        #expect(next.allSatisfy { $0 > 36 })
    }
}
