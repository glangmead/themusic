//
//  HarmonyTimeline.swift
//  Orbital
//
//  An immutable absolute-time harmony index built from a ScorePatternSyntax.
//  Given any beat position, it folds over all events up to that beat and
//  returns the resulting (Key, ChordInScale).
//

import Foundation
import Tonic

// MARK: - HarmonyTimeline

/// An immutable, queryable record of how the key and chord evolve over time.
///
/// Built once at compile time from the `chordEvents` of a `ScorePatternSyntax`.
/// `state(at:loop:)` is O(n_events) per call — acceptable for typical scores
/// which have far fewer than 100 chord changes per cycle.
///
/// Usage:
///   let timeline = HarmonyTimeline(totalBeats: 16, initialKey: cMajor, events: [...])
///   let (key, chord) = timeline.state(at: 6.0, loop: true)
struct HarmonyTimeline {

    struct Event {
        let beat: Double
        let op: ChordEventSyntax
    }

    /// Total duration of one cycle in beats.
    let totalBeats: Double

    /// The key established at beat 0 (before any events fire).
    let initialKey: Key

    /// All chord/key change events, sorted by beat ascending.
    let events: [Event]

    // MARK: - Query

    /// Return the (key, chord) that applies at the given absolute beat.
    ///
    /// - Parameters:
    ///   - beat: Absolute beat position (may exceed totalBeats when loop is true).
    ///   - loop: If true, wraps beat into [0, totalBeats) before querying.
    /// - Returns: The key and chord that apply at that beat.
    func state(at beat: Double, loop: Bool) -> (key: Key, chord: ChordInScale) {
        let effectiveBeat: Double
        if loop {
            let total = max(totalBeats, 1)
            effectiveBeat = beat.truncatingRemainder(dividingBy: total)
        } else {
            effectiveBeat = beat
        }

        var key = initialKey
        var chord = ChordInScale(degrees: [0, 2, 4], inversion: 0)  // I triad fallback

        for event in events {
            guard event.beat <= effectiveBeat else { break }
            applyEvent(event.op, to: &key, chord: &chord)
        }

        return (key, chord)
    }

    // MARK: - Event Application

    /// Mutate key/chord in place according to a ChordEventSyntax operation.
    private func applyEvent(
        _ event: ChordEventSyntax,
        to key: inout Key,
        chord: inout ChordInScale
    ) {
        switch event.op {
        case "setChord":
            if let degrees = event.degrees {
                chord = ChordInScale(degrees: degrees, inversion: event.inversion ?? 0)
            }

        case "T":
            if let n = event.n { chord.T(n) }

        case "t":
            if let n = event.n { chord.t(n) }

        case "Tt":
            if let n = event.n { chord.T(n) }
            if let t = event.tVal { chord.t(t) }

        case "setKey":
            if let rootStr = event.root, let scaleStr = event.scale {
                let nc = NoteGeneratorSyntax.resolveNoteClass(rootStr)
                let sc = NoteGeneratorSyntax.resolveScale(scaleStr)
                key = Key(root: nc, scale: sc)
            }

        default:
            break
        }
    }
}
