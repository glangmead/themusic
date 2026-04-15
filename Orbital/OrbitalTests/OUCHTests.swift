//
//  OUCHTests.swift
//  OrbitalTests
//
//  Tests for OUCH configuration classification and the Bach-like state machine.
//

import Testing
import Foundation
@testable import Orbital

// MARK: - Classification

@Suite("OUCHClassificationTests", .serialized)
struct OUCHClassificationTests {

    @Test("Close-position C major triad classifies as .closed")
    func closedClassification() {
        // C4-E4-G4 = 60-64-67, within an octave with all 3 pitch classes
        let config = classifyOUCH(upperVoices: [60, 64, 67])
        #expect(config == .closed)
    }

    @Test("Open-position C major triad classifies as .open")
    func openClassification() {
        // C4-G4-E5 = 60-67-76, span 16 > octave, all 3 pitch classes
        let config = classifyOUCH(upperVoices: [60, 67, 76])
        #expect(config == .open)
    }

    @Test("Half-open voicing with octave-spanned doubling classifies as .halfOpen")
    func halfOpenClassification() {
        // C4-E4-C5: two C's an octave apart, E between
        let config = classifyOUCH(upperVoices: [60, 64, 72])
        #expect(config == .halfOpen)
    }

    @Test("Unison doubling classifies as .unusualDoubleInterval")
    func unusualDoubleIntervalClassification() {
        // Two voices on same pitch, third nearby
        let config = classifyOUCH(upperVoices: [60, 60, 64])
        #expect(config == .unusualDoubleInterval)
    }

    @Test("Open-octave with third voice outside classifies as .unusualOpenOctave")
    func unusualOpenOctaveClassification() {
        // E4-C5-C6: C's an octave apart, E outside below
        // Actually E4 (64), C5 (72), C6 (84): 72 and 84 are octave apart, 64 is outside
        let config = classifyOUCH(upperVoices: [64, 72, 84])
        #expect(config == .unusualOpenOctave)
    }
}

// MARK: - Transitions

@Suite("OUCHStateMachineTests", .serialized)
struct OUCHStateMachineTests {

    @Test("Bach transition table has self-loops closed→closed and open→open")
    func bachSelfLoops() {
        let closed = OUCHState.bachTransitions[.closed] ?? []
        let open = OUCHState.bachTransitions[.open] ?? []
        #expect(closed.contains { $0.0 == .closed })
        #expect(open.contains { $0.0 == .open })
    }

    @Test("closed→closed self-loop has highest probability among .closed transitions")
    func closedSelfLoopDominant() {
        let transitions = OUCHState.bachTransitions[.closed] ?? []
        let sorted = transitions.sorted { $0.1 > $1.1 }
        #expect(sorted.first?.0 == .closed)
    }

    @Test("step produces varied configurations over many samples")
    func stochasticSamplesVary() {
        var rng = SeededRNG(seed: 7)
        var state = OUCHState(current: .closed)

        var seen: Set<OUCHConfiguration> = []
        for _ in 0..<200 {
            let next = state.step(using: &rng)
            seen.insert(next)
        }
        // Should hit at least closed and one other over 200 samples.
        #expect(seen.contains(.closed))
        #expect(seen.count >= 2)
    }

    @Test("step is deterministic for a given seed")
    func stochasticDeterministic() {
        var rng1 = SeededRNG(seed: 42)
        var rng2 = SeededRNG(seed: 42)
        var s1 = OUCHState(current: .closed)
        var s2 = OUCHState(current: .closed)
        for _ in 0..<50 {
            let a = s1.step(using: &rng1)
            let b = s2.step(using: &rng2)
            #expect(a == b)
        }
    }
}
