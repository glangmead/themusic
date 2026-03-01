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
                let perturbations: [Perturbation]? = event.perturbations.map { arr in
                    arr.map { $0?.toPerturbation() ?? .none }
                }
                chord = ChordInScale(degrees: degrees, inversion: event.inversion ?? 0,
                                     perturbations: perturbations)
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
    ///   - Quality suffixes: o (dim), /o or ø (half-dim) — consumed for quality tracking
    ///   - Figured bass: "", 6, 6/4, 7, 6/5, 4/3, 2, 4/2, 9
    ///   - Applied targets: /V, /vi, /IV, /bIII, etc.
    ///   - Flat/sharp prefix: bII, bVII, bVI, bIII, #IV, etc. → degrees + perturbations
    ///   - Neapolitan: N = bII, N6 = bII6
    ///   - Augmented sixths: It6, Ger6/5, Ger7, Fr4/3, Fr6
    ///   - Bracket annotations like [b9] are stripped before parsing
    private func parseRomanNumeral(_ s: String, in key: Key) -> (ChordInScale, Key?)? {
        var str = s.trimmingCharacters(in: .whitespaces)

        // Strip analytical bracket annotations (e.g. "V9[b9]" → "V9")
        if let bracketIdx = str.firstIndex(of: "[") {
            str = String(str[..<bracketIdx]).trimmingCharacters(in: .whitespaces)
        }

        // 1. Augmented sixth chords — fixed chromatic structures
        if str.hasPrefix("Ger") || str.hasPrefix("Fr") || str.hasPrefix("It") {
            return parseAugmentedSixth(str, in: key)
        }

        // 2. Neapolitan: N = bII (root position), N6 = bII6 (1st inversion)
        if str == "N" { str = "bII" }
        else if str == "N6" { str = "bII6" }
        else if str.hasPrefix("N") { return nil }   // N7 etc. not supported

        // 3. Flat / sharp chromatic prefix
        var semitonePrefix = 0
        if str.hasPrefix("b") {
            semitonePrefix = -1
            str = String(str.dropFirst())
        } else if str.hasPrefix("#") {
            semitonePrefix = 1
            str = String(str.dropFirst())
        }

        // 4. Extract Roman numeral characters (I, V, i, v only — covers I through VII)
        let romanChars: Set<Character> = ["I", "V", "i", "v"]
        var numEnd = str.startIndex
        while numEnd < str.endIndex && romanChars.contains(str[numEnd]) {
            numEnd = str.index(after: numEnd)
        }
        guard numEnd > str.startIndex else { return nil }

        let originalNumeral = String(str[str.startIndex..<numEnd])
        let numeralStr = originalNumeral.uppercased()
        let isUppercase = originalNumeral.first?.isUppercase ?? true
        str = String(str[numEnd...])

        let degreeMap: [String: Int] = [
            "I": 0, "II": 1, "III": 2, "IV": 3, "V": 4, "VI": 5, "VII": 6
        ]
        guard let rootDegree = degreeMap[numeralStr] else { return nil }

        // 5. Consume quality suffix and track for perturbation calculation
        var quality = isUppercase ? "major" : "minor"
        if str.hasPrefix("/o") {
            quality = "halfDim"
            str = String(str.dropFirst(2))
        } else if str.hasPrefix("o") || str.hasPrefix("ø") {
            quality = "dim"
            str = String(str.dropFirst(1))
        }

        // 6. Find applied chord target: last "/" before b/# or Roman numeral char
        let appliedStartChars: Set<Character> = ["I", "V", "i", "v", "b", "#"]
        var appliedTargetStr: String? = nil
        if let lastSlash = str.lastIndex(of: "/") {
            let afterSlash = str.index(after: lastSlash)
            if afterSlash < str.endIndex && appliedStartChars.contains(str[afterSlash]) {
                appliedTargetStr = String(str[afterSlash...])
                str = String(str[..<lastSlash])
            }
        }

        // 7. Parse figured bass
        let (chordSize, inversion) = parseFiguredBass(str)
        let degrees = (0..<chordSize).map { rootDegree + $0 * 2 }

        // 8. Compute perturbations for b/# prefix chords
        var perturbations: [Perturbation]? = nil
        if semitonePrefix != 0 {
            let baseRoot = scaleSemitonesForDegree(rootDegree, in: key)
            let alteredRoot = baseRoot + semitonePrefix
            let chordInts = chordIntervalsFor(quality: quality, size: chordSize)

            var perturbs: [Perturbation] = []
            for (i, degree) in degrees.enumerated() {
                let target = alteredRoot + chordInts[i]
                let actual = scaleSemitonesForDegree(degree, in: key)
                let offset = target - actual
                perturbs.append(offset != 0 ? .chromatic(offset) : .none)
            }
            let allNone = perturbs.allSatisfy { if case .none = $0 { return true }; return false }
            perturbations = allNone ? nil : perturbs
        }

        let chord = ChordInScale(degrees: degrees, inversion: inversion,
                                 perturbations: perturbations)
        let newKey = appliedTargetStr.flatMap { tonicizeKey(key, toTarget: $0) }
        return (chord, newKey)
    }

    /// Parse augmented sixth chords (It6, Ger6/5, Ger7, Fr4/3, Fr6).
    /// All are voiced from the b6 (8 semitones above tonic) with chromatic perturbations.
    private func parseAugmentedSixth(_ s: String, in key: Key) -> (ChordInScale, Key?)? {
        // Fixed pitch targets (semitones above tonic): b6, C(oct), [Eb(oct),] [D(oct),] #4(oct)
        let degrees: [Int]
        let targetSemitones: [Int]
        if s.hasPrefix("It") {
            degrees = [5, 7, 10]
            targetSemitones = [8, 12, 18]          // Ab, C5, F#5
        } else if s.hasPrefix("Ger") {
            degrees = [5, 7, 9, 10]
            targetSemitones = [8, 12, 15, 18]      // Ab, C5, Eb5, F#5
        } else if s.hasPrefix("Fr") {
            degrees = [5, 7, 8, 10]
            targetSemitones = [8, 12, 14, 18]      // Ab, C5, D5, F#5
        } else {
            return nil
        }
        let perturbations: [Perturbation] = zip(degrees, targetSemitones).map { (deg, target) in
            let actual = scaleSemitonesForDegree(deg, in: key)
            let offset = target - actual
            return offset != 0 ? .chromatic(offset) : .none
        }
        let allNone = perturbations.allSatisfy { if case .none = $0 { return true }; return false }
        let chord = ChordInScale(degrees: degrees, inversion: 0,
                                 perturbations: allNone ? nil : perturbations)
        return (chord, nil)
    }

    /// Compute the tonicized key for an applied chord target like "V", "vi", "bIII", etc.
    /// Supports b/# prefix on the target; case of the numeral part determines major/minor.
    private func tonicizeKey(_ key: Key, toTarget targetStr: String) -> Key? {
        var target = targetStr
        var semitoneOffset = 0
        if target.hasPrefix("b") {
            semitoneOffset = -1
            target = String(target.dropFirst())
        } else if target.hasPrefix("#") {
            semitoneOffset = 1
            target = String(target.dropFirst())
        }

        let romanChars: Set<Character> = ["I", "V", "i", "v"]
        let degreeMap: [String: Int] = [
            "I": 0, "II": 1, "III": 2, "IV": 3, "V": 4, "VI": 5, "VII": 6
        ]
        let targetIsMinor = target.first?.isLowercase ?? false
        let targetNumeral = String(target.prefix(while: { romanChars.contains($0) })).uppercased()
        guard let targetDegree = degreeMap[targetNumeral],
              targetDegree < key.scale.intervals.count else { return nil }

        let targetSemitones = key.scale.intervals[targetDegree].semitones
        let homeRootPC = Int(key.root.canonicalNote.noteNumber) % 12
        let targetRootPC = ((homeRootPC + targetSemitones + semitoneOffset) % 12 + 12) % 12

        // Flat-preference enharmonic spellings to match Tonic library conventions
        let pcToName = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        let rootStr = pcToName[targetRootPC]
        let nc = NoteGeneratorSyntax.resolveNoteClass(rootStr)

        let targetScale: Scale = targetIsMinor ? .minor : .major
        return Key(root: nc, scale: targetScale)
    }

    /// Semitones above key root for the given scale degree (supports degrees > scaleSize).
    private func scaleSemitonesForDegree(_ degree: Int, in key: Key) -> Int {
        let intervals = key.scale.intervals
        let scaleSize = intervals.count
        let octaveShift = degree / scaleSize
        let degreeInScale = ((degree % scaleSize) + scaleSize) % scaleSize
        return intervals[degreeInScale].semitones + octaveShift * 12
    }

    /// Chord tone intervals (semitones from root) for a given quality and chord size.
    private func chordIntervalsFor(quality: String, size: Int) -> [Int] {
        let triads:   [String: [Int]] = [
            "major":   [0, 4, 7],
            "minor":   [0, 3, 7],
            "dim":     [0, 3, 6],
            "halfDim": [0, 3, 6],
        ]
        let sevenths: [String: [Int]] = [
            "major":   [0, 4, 7, 10],   // dominant 7th (most common uppercase 7th)
            "minor":   [0, 3, 7, 10],
            "dim":     [0, 3, 6,  9],
            "halfDim": [0, 3, 6, 10],
        ]
        switch size {
        case 3:  return triads[quality]   ?? [0, 4, 7]
        case 4:  return sevenths[quality] ?? [0, 4, 7, 10]
        case 5:  return (sevenths[quality] ?? [0, 4, 7, 10]) + [14]  // 9th approx
        default: return Array(repeating: 0, count: size).enumerated().map { $0.offset * 3 }
        }
    }

    // MARK: - Chord Event Label Formatting

    /// Format a ChordEventSyntax as a human-readable label for display in the UI.
    ///
    /// Returns nil for ops that don't produce a meaningful standalone label.
    /// Used by ScorePatternCompiler to build the chord label stream.
    static func formatLabel(for event: ChordEventSyntax) -> String? {
        switch event.op {
        case "setRoman":
            return event.roman

        case "T":
            guard let n = event.n else { return nil }
            return n >= 0 ? "T+\(n)" : "T\(n)"

        case "t":
            guard let n = event.n else { return nil }
            return n >= 0 ? "t+\(n)" : "t\(n)"

        case "Tt":
            var parts: [String] = []
            if let n = event.n { parts.append(n >= 0 ? "T+\(n)" : "T\(n)") }
            if let t = event.tVal { parts.append(t >= 0 ? "t+\(t)" : "t\(t)") }
            return parts.isEmpty ? nil : parts.joined(separator: " ")

        case "setChord":
            guard let degrees = event.degrees else { return nil }
            let degreePart = "[\(degrees.map(String.init).joined(separator: ","))]"
            if let inv = event.inversion, inv > 0 {
                let invLabels = ["", "⁶", "⁶⁄₄", "⁷", "⁶⁄₅", "⁴⁄₃", "²"]
                let invLabel = inv < invLabels.count ? invLabels[inv] : " inv\(inv)"
                return degreePart + invLabel
            }
            return degreePart

        case "setKey":
            guard let root = event.root, let scale = event.scale else { return nil }
            return "\(root) \(scale)"

        default:
            return nil
        }
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
