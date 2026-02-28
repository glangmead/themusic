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

        case "setRoman":
            if let romanStr = event.roman,
               let (newChord, newKey) = parseRomanNumeral(romanStr, in: key) {
                chord = newChord
                if let k = newKey { key = k }
            }

        default:
            break
        }
    }

    // MARK: - Roman Numeral Parser

    /// Parse a RomanText-style Roman numeral string into a ChordInScale and optional
    /// tonicized Key (for applied chords). Returns nil for unsupported symbols.
    ///
    /// Supported:
    ///   - Diatonic numerals: I ii III IV V vi VII (any case)
    ///   - Quality suffixes: o (dim), /o or ø (half-dim) — consumed, don't affect degrees
    ///   - Figured bass: "", 6, 6/4, 7, 6/5, 4/3, 2, 4/2, 9
    ///   - Applied targets: /V, /vi, /IV, etc. — tonicizes to that degree's key
    ///
    /// Not supported (returns nil, caller keeps current harmony):
    ///   - Chromatic prefixes: bII, #IV, etc.
    ///   - Special chord names: N6, Ger6/5, It6, Fr4/3
    private func parseRomanNumeral(_ s: String, in key: Key) -> (ChordInScale, Key?)? {
        var str = s.trimmingCharacters(in: .whitespaces)

        // Special named chords: not expressible as diatonic scale degrees
        let specials = ["Ger", "Fr", "It", "N6", "N"]
        if specials.contains(where: { str.hasPrefix($0) }) { return nil }

        // Chromatic prefix: not supported
        if str.hasPrefix("b") || str.hasPrefix("#") { return nil }

        // Extract Roman numeral characters (I, V, i, v only — covers I through VII)
        let romanChars: Set<Character> = ["I", "V", "i", "v"]
        var numEnd = str.startIndex
        while numEnd < str.endIndex && romanChars.contains(str[numEnd]) {
            numEnd = str.index(after: numEnd)
        }
        guard numEnd > str.startIndex else { return nil }
        let numeralStr = String(str[str.startIndex..<numEnd]).uppercased()
        str = String(str[numEnd...])

        let degreeMap: [String: Int] = [
            "I": 0, "II": 1, "III": 2, "IV": 3, "V": 4, "VI": 5, "VII": 6
        ]
        guard let rootDegree = degreeMap[numeralStr] else { return nil }

        // Consume quality suffix: /o (half-dim) or o (dim) or ø (half-dim unicode)
        if str.hasPrefix("/o") {
            str = String(str.dropFirst(2))
        } else if str.hasPrefix("o") || str.hasPrefix("ø") {
            str = String(str.dropFirst(1))
        }

        // Find applied chord target: last "/" followed by a Roman numeral character
        var appliedTargetStr: String? = nil
        if let lastSlash = str.lastIndex(of: "/") {
            let afterSlash = str.index(after: lastSlash)
            if afterSlash < str.endIndex && romanChars.contains(str[afterSlash]) {
                appliedTargetStr = String(str[afterSlash...])
                str = String(str[..<lastSlash])
            }
        }

        let (chordSize, inversion) = parseFiguredBass(str)
        let degrees = (0..<chordSize).map { rootDegree + $0 * 2 }
        let chord = ChordInScale(degrees: degrees, inversion: inversion)

        // Resolve applied key if present
        let newKey = appliedTargetStr.flatMap { tonicizeKey(key, toTarget: $0) }
        return (chord, newKey)
    }

    /// Compute the tonicized key for an applied chord target like "V", "vi", "IV".
    /// Uppercase target → major key; lowercase → minor key.
    private func tonicizeKey(_ key: Key, toTarget targetStr: String) -> Key? {
        let romanChars: Set<Character> = ["I", "V", "i", "v"]
        let degreeMap: [String: Int] = [
            "I": 0, "II": 1, "III": 2, "IV": 3, "V": 4, "VI": 5, "VII": 6
        ]
        let targetNumeral = String(targetStr.prefix(while: { romanChars.contains($0) })).uppercased()
        guard let targetDegree = degreeMap[targetNumeral],
              targetDegree < key.scale.intervals.count else { return nil }

        let targetSemitones = key.scale.intervals[targetDegree].semitones
        let homeRootPC = Int(key.root.canonicalNote.noteNumber) % 12
        let targetRootPC = (homeRootPC + targetSemitones) % 12

        // Default enharmonic spellings (flat preference, matching common usage)
        let pcToName = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        let rootStr = pcToName[targetRootPC]
        let nc = NoteGeneratorSyntax.resolveNoteClass(rootStr)

        let targetIsMinor = targetStr.first?.isLowercase ?? false
        let targetScale: Scale = targetIsMinor ? .minor : .major
        return Key(root: nc, scale: targetScale)
    }

    /// Map a figured bass string to (chordSize, inversion).
    private func parseFiguredBass(_ fig: String) -> (chordSize: Int, inversion: Int) {
        switch fig {
        case "":          return (3, 0)  // triad, root position
        case "6":         return (3, 1)  // triad, 1st inversion
        case "6/4":       return (3, 2)  // triad, 2nd inversion
        case "7":         return (4, 0)  // seventh, root position
        case "6/5":       return (4, 1)  // seventh, 1st inversion
        case "4/3":       return (4, 2)  // seventh, 2nd inversion
        case "2", "4/2":  return (4, 3)  // seventh, 3rd inversion
        case "9":         return (5, 0)  // ninth chord
        default:          return (3, 0)  // unrecognized → triad root position
        }
    }
}
