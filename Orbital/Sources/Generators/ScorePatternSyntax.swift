//
//  ScorePatternSyntax.swift
//  Orbital
//
//  Codable types for the "scoreTracks" pattern format.
//  A score pattern specifies melody and harmony at absolute beat positions,
//  compiled into delta-time iterators at build time.
//
//  JSON structure overview:
//  {
//    "name": "...",
//    "scoreTracks": {
//      "bpm": 120,
//      "totalBeats": 16,
//      "loop": true,
//      "key": { "root": "C", "scale": "major" },
//      "chordEvents": [
//        { "beat": 0, "op": "setChord", "degrees": [0,2,4], "inversion": 0 },
//        { "beat": 4, "op": "T", "n": 3 },
//        { "beat": 8, "op": "t", "n": 1 },
//        { "beat": 12, "op": "Tt", "n": 1, "tVal": -1 },
//        { "beat": 16, "op": "setKey", "root": "G", "scale": "major" }
//      ],
//      "tracks": [
//        {
//          "name": "Melody",
//          "presetFilename": "auroraBorealis",
//          "octave": 4,
//          "sustainFraction": 0.85,
//          "notes": [
//            { "type": "chordTone", "index": 0, "durationBeats": 1 },
//            { "type": "scaleDegree", "degree": 2, "durationBeats": 0.5 },
//            { "type": "hold", "durationBeats": 0.5 },
//            { "type": "rest", "durationBeats": 1 },
//            { "type": "absolute", "note": "C4", "durationBeats": 1 },
//            { "type": "currentChord", "durationBeats": 2 }
//          ]
//        }
//      ]
//    }
//  }

import Foundation
import Tonic

// MARK: - Key Syntax

/// JSON representation of a key: root note class + scale name.
struct ScoreKeySyntax: Codable, Equatable {
    let root: String    // e.g. "C", "Bb", "F#"
    let scale: String   // e.g. "major", "minor", "dorian"
}

// MARK: - Chord Event Syntax

/// A timed harmonic event that changes the chord or key at a specific beat.
/// Events are applied in order; beat 0 events establish the opening harmony.
///
/// Supported ops:
/// - "setChord": replace the chord outright (requires `degrees`, optionally `inversion`)
/// - "T": shift chord degrees by n steps in the scale (e.g. I→ii = T(1))
/// - "t": rotate chord inversion by n steps (e.g. root→1st inversion = t(1))
/// - "Tt": apply T(n) then t(tVal) atomically
/// - "setKey": change the key (requires `root` and `scale`)
/// - "setRoman": set chord from a Roman numeral string (requires `roman`).
///     Diatonic numerals (I, ii, V7, viio, ii6/5, …) map to scale-degree arrays
///     within the current key. Applied chords (V/V, viio7/V, V6/5/IV, …)
///     additionally tonicize to the target degree's key and persist that key.
///     Unsupported symbols (N6, bII, Ger6/5, It6, Fr4/3) are silently ignored.
struct ChordEventSyntax: Codable, Equatable {
    let beat: Double
    let op: String          // "setChord" | "T" | "t" | "Tt" | "setKey" | "setRoman"

    // For "setChord":
    let degrees: [Int]?     // e.g. [0, 2, 4] for a triad on the root
    let inversion: Int?     // 0 = root position (default)
    // Per-degree chromatic offsets, parallel to degrees. null or {} → .none.
    // e.g. [{"chromatic": -1}, null, {"chromatic": -1}] for a Neapolitan 6th.
    let perturbations: [PerturbationSyntax?]?

    // For "T", "t", "Tt":
    let n: Int?             // T amount (or t amount for pure "t" op)
    let tVal: Int?          // t component of a combined Tt operation

    // For "setKey":
    let root: String?       // e.g. "G"
    let scale: String?      // e.g. "major"

    // For "setRoman":
    let roman: String?      // e.g. "V7", "ii6/5", "viio", "V7/V", "viio7/vi"

    init(
        beat: Double, op: String,
        degrees: [Int]? = nil, inversion: Int? = nil,
        perturbations: [PerturbationSyntax?]? = nil,
        n: Int? = nil, tVal: Int? = nil,
        root: String? = nil, scale: String? = nil,
        roman: String? = nil
    ) {
        self.beat = beat; self.op = op
        self.degrees = degrees; self.inversion = inversion
        self.perturbations = perturbations
        self.n = n; self.tVal = tVal
        self.root = root; self.scale = scale
        self.roman = roman
    }
}

// MARK: - Score Note Type

/// The semantic type of a note in the score.
enum ScoreNoteType: String, Codable, Equatable {
    case rest           // Silence for durationBeats; emits []
    case hold           // Extend the preceding note's sustain; no new attack
    case currentChord   // Emit all voiced chord pitches simultaneously
    case chordTone      // Single pitch: chord tone by index (wraps at chord size)
    case scaleDegree    // Single pitch: scale degree by number
    case absolute       // Single pitch: explicit MIDI number or note name ("Bb4")
}

// MARK: - Score Note Syntax

/// A single note in the score sequence, with its duration in beats.
struct ScoreNoteSyntax: Codable, Equatable {
    let type: ScoreNoteType
    let durationBeats: Double

    // For "chordTone": which chord tone (0 = bass of voiced chord).
    // Indices ≥ chord size wrap upward by octave (index 3 on a triad = root+1 octave).
    // Negative indices wrap downward (-1 = top tone of octave below, -3 on a triad = root-1 octave).
    let index: Int?

    // For "scaleDegree": the degree index (0 = root, 1 = 2nd, …).
    let degree: Int?

    // For "absolute": either a raw MIDI number or a note name string.
    let midi: Int?          // MIDI note number 0–127
    let note: String?       // Note name + octave, e.g. "C4", "Bb3", "F#5"

    // For "chordTone", "scaleDegree", "absolute": override the track's base octave.
    let octave: Int?

    // For "currentChord": override the track's default voicing.
    let voicing: VoicingStyle?

    // Velocity 0–127. Defaults to 80 if absent.
    let velocity: Int?
}

// MARK: - Score Track Syntax

/// A single instrument track in a score pattern.
struct ScoreTrackSyntax: Codable {
    let name: String
    let presetFilename: String
    let numVoices: Int?

    /// Base octave for note resolution. Middle-C region = 4.
    let octave: Int

    /// Default voicing style used for "currentChord" notes.
    let voicing: VoicingStyle?

    /// Sustain as a fraction of note duration (0.0–1.0). Default 0.85.
    /// Sustain seconds = durationBeats * (60/bpm) * sustainFraction.
    let sustainFraction: Double?

    /// The ordered sequence of notes for this track.
    /// Total durationBeats across all notes should equal totalBeats for clean looping.
    let notes: [ScoreNoteSyntax]
}

// MARK: - Score Pattern Syntax

/// Top-level Codable specification for a score-based pattern.
///
/// Unlike tableTracks (delta-time, stochastic) or midiTracks (MIDI file),
/// scoreTracks uses absolute beat positions for all events.
/// The compiler resolves each note against the harmony timeline at its beat,
/// then produces delta-time iterators — the same interface as the other paths.
struct ScorePatternSyntax: Codable {
    let bpm: Double

    /// Total beats in one loop cycle. All note durations should sum to this.
    let totalBeats: Double

    /// Whether to loop the pattern. Defaults to true.
    let loop: Bool?

    /// The initial key (root note class + scale name).
    let key: ScoreKeySyntax

    /// Timed harmonic events, sorted by beat ascending.
    /// Beat 0 typically contains the first "setChord".
    let chordEvents: [ChordEventSyntax]

    /// Per-instrument tracks.
    let tracks: [ScoreTrackSyntax]
}
