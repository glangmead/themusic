//
//  QuadHierarchy.swift
//  Orbital
//
//  Created by Greg Langmead on 1/13/26.
//

import Foundation
import Tonic

// MARK: - Tonic extensions

private let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

/// Figured bass figures for inversions of triads and seventh chords.
/// For triads:  root → "", 1st → ⁶, 2nd → ⁶₄
/// For sevenths: root → ⁷, 1st → ⁶₅, 2nd → ⁴₃, 3rd → ⁴₂
private let triadFigures = ["", "⁶", "⁶₄"]
private let seventhFigures = ["⁷", "⁶₅", "⁴₃", "⁴₂"]

extension Tonic.Chord {
  /// Returns (qualityMark, figures) for the chord type, where `figures` is the
  /// array of figured-bass symbols indexed by inversion (nil for extended chords).
  private func qualityAndFigures() -> (String, [String]?) {
    switch type {
    case .major, .minor:        return ("", triadFigures)
    case .dim:                  return ("°", triadFigures)
    case .aug:                  return ("⁺", triadFigures)
    case .dom7, .min7:          return ("", seventhFigures)
    case .maj7, .min_maj7:      return ("M", seventhFigures)
    case .halfDim7:             return ("ø", seventhFigures)
    case .dim7:                 return ("°", seventhFigures)
    case .min6:                 return ("", ["⁶"])
    default:
      let desc = type.description
      let hasMinorThird = type.intervals.contains(.m3)
      if hasMinorThird, desc.hasPrefix("m"), !desc.hasPrefix("maj") {
        return (String(desc.dropFirst()), nil)
      }
      return (desc, nil)
    }
  }

  /// Roman numeral notation for this chord in the given key, e.g. "ii", "V⁶₅", "viiø⁷".
  /// The `inversion` parameter supplies the current voicing (0 = root position).
  /// Returns nil if the chord root doesn't fall on a scale degree.
  func romanNumeralNotation(in key: Key, inversion: Int = 0) -> String? {
    let keyRootPC = Int(key.root.canonicalNote.noteNumber) % 12
    let chordRootPC = Int(root.canonicalNote.noteNumber) % 12
    let semitoneDistance = ((chordRootPC - keyRootPC) % 12 + 12) % 12

    let scaleIntervals = key.scale.intervals
    guard let degree = scaleIntervals.firstIndex(where: { $0.semitones == semitoneDistance }),
          degree < romanNumerals.count else {
      return nil
    }

    let hasMinorThird = type.intervals.contains(.m3)
    let numeral = hasMinorThird
      ? romanNumerals[degree].lowercased()
      : romanNumerals[degree]

    let chordSize = type.intervals.count + 1
    let inv = ((inversion % chordSize) + chordSize) % chordSize
    let (qualityMark, figures) = qualityAndFigures()
    let extensionFigure = figures.flatMap { inv < $0.count ? $0[inv] : nil } ?? ""

    return numeral + qualityMark + extensionFigure
  }
}

// MARK: - Interval helpers

extension Tonic.Interval {
  /// Canonical mapping from semitone count (0–11) to Interval.
  /// Picks the most standard enharmonic spelling for each pitch class.
  static let semitonesMap: [Int: Tonic.Interval] = [
    0: .P1,
    1: .m2,
    2: .M2,
    3: .m3,
    4: .M3,
    5: .P4,
    6: .A4,
    7: .P5,
    8: .m6,
    9: .M6,
    10: .m7,
    11: .M7
  ]
}

// MARK: - Chord as relative scale degrees
// See docs/hierarchical_pitch_design_notes.md for the full design rationale.

/// A chord expressed as scale degrees within a key, not absolute pitch classes.
/// e.g. [0, 2, 4] = triad built on the root (I chord).
/// T(1) shifts all degrees by 1: [0, 2, 4] -> [1, 3, 5] (ii chord).
/// t(1) rotates the ordering: bass moves from degree 0 to degree 2 (first inversion).
struct ChordInScale {
  var degrees: [Int]      // scale degrees, e.g. [0, 2, 4]
  var inversion: Int      // rotation: which degree is the bass (0 = root position)

  /// The degrees in voiced order (bass note first), accounting for inversion.
  var voicedDegrees: [Int] {
    guard !degrees.isEmpty else { return [] }
    let count = degrees.count
    let inv = ((inversion % count) + count) % count
    return Array(degrees[inv...]) + Array(degrees[..<inv])
  }

  /// T: shift all degrees by n steps in the parent scale.
  /// I [0,2,4] -> T(1) -> ii [1,3,5] -> T(1) -> iii [2,4,6] ...
  mutating func T(_ n: Int) { // swiftlint:disable:this identifier_name
    degrees = degrees.map { $0 + n }
  }

  /// t: rotate the voicing. t(1) = first inversion, t(2) = second inversion.
  mutating func t(_ n: Int) { // swiftlint:disable:this identifier_name
    inversion += n
  }
}

// MARK: Melody note as a query against the hierarchy

/// How a melody note departs from a chord tone.
/// A note is either a plain chord tone, or a chord tone perturbed by a
/// neighbor — either chromatically (semitones) or within the scale (steps).
enum Perturbation {
  case none
  case chromatic(Int)      // semitones from the chord tone
  case scaleDegree(Int)    // scale steps from the chord tone
}

/// A transient melody event: "play chord tone N, optionally perturbed."
/// Produced by a melody emitter, resolved through a PitchHierarchy at play time.
/// Not stored in the hierarchy — it has a different lifetime.
struct MelodyNote {
  var chordToneIndex: Int           // index into ChordInScale.voicedDegrees
  var perturbation: Perturbation    // NHT offset
}

// MARK: The shared hierarchy

/// Which level of the hierarchy to target with a transformation.
enum HierarchyLevel {
  case scale
  case chord
}

/// Shared mutable state representing the current key and chord.
/// Emitters on independent timers mutate this:
///   - A scale emitter calls hierarchy.T(n, at: .scale) every ~20s
///   - A chord emitter calls hierarchy.T(n, at: .chord) every ~4s
///   - A melody emitter produces MelodyNote values, resolved via hierarchy.resolve()
///
/// Multiple tracks can read the same PitchHierarchy, so a melody track and a
/// chord-pad track share harmonic context automatically.
class PitchHierarchy {
  var key: Key                // (root, scale) — the rooted pair
  var chord: ChordInScale     // degrees within the key

  init(key: Key, chord: ChordInScale) {
    self.key = key
    self.chord = chord
  }

  // Convenience: major with a I chord
  convenience init(root: NoteClass) {
    self.init(
      key: Key(root: root, scale: .major),
      chord: ChordInScale(degrees: [0, 2, 4], inversion: 0)
    )
  }

  // MARK: Transformations parameterized by level

  /// T (extrinsic): shift the root through the parent space.
  /// At .scale: moves the key root by n semitones (C major -> C# major -> D major ...).
  /// At .chord: shifts chord degrees within the scale (I -> ii -> iii).
  func T(_ n: Int, at level: HierarchyLevel) { // swiftlint:disable:this identifier_name
    switch level {
    case .scale:
      let semitones = ((n % 12) + 12) % 12
      guard semitones != 0 else { return }
      if let interval = Tonic.Interval.semitonesMap[semitones],
         let newRoot = key.root.canonicalNote.shiftUp(interval)?.noteClass {
        key = Key(root: newRoot, scale: key.scale)
      }
    case .chord:
      chord.T(n)
    }
  }

  /// t (intrinsic): rotate within the level.
  /// At .scale: rotate the mode by cyclically permuting the step intervals.
  ///   t(1) on Ionian [W W H W W W H] → Dorian [W H W W W H W].
  ///   The root advances to the next scale degree so the pitch content stays the same.
  /// At .chord: rotate inversion (root -> 1st -> 2nd).
  func t(_ n: Int, at level: HierarchyLevel) { // swiftlint:disable:this identifier_name
    switch level {
    case .scale:
      let intervals = key.scale.intervals
      let count = intervals.count
      guard count > 0 else { return }
      let steps = ((n % count) + count) % count
      guard steps > 0 else { return }

      // Convert absolute intervals to step sizes in semitones
      let semitones = intervals.map { $0.semitones }
      var stepSizes: [Int] = []
      for idx in 0..<count {
        let next = (idx + 1) % count
        let step = next > 0 ? semitones[next] - semitones[idx] : 12 - semitones[idx]
        stepSizes.append(step)
      }

      // Cyclically permute the step sizes
      let rotated = Array(stepSizes[steps...]) + Array(stepSizes[..<steps])

      // Convert back to absolute intervals from root (cumulative sum)
      var cumulative = [0]
      for step in rotated.dropLast() {
        cumulative.append(cumulative.last! + step)
      }

      // Map semitone values back to Interval enums
      let newIntervals = cumulative.compactMap { Tonic.Interval.semitonesMap[$0] }
      guard newIntervals.count == count else { return }

      // Build the new scale and look up its name from known scales
      var newScale = Scale(intervals: newIntervals, description: "")
      if let named = Scale.allCases.first(where: { $0.rawValue == newScale.rawValue }) {
        newScale = named
      }

      // Advance the root to the scale degree that becomes the new "degree 0".
      // e.g. C Ionian t(1) → D Dorian: root moves from C to D.
      let rootSemitoneShift = semitones[steps]
      if let interval = Tonic.Interval.semitonesMap[rootSemitoneShift],
         let newRoot = key.root.canonicalNote.shiftUp(interval)?.noteClass {
        key = Key(root: newRoot, scale: newScale)
      }
    case .chord:
      chord.t(n)
    }
  }

  /// L (lattice): the minimal voice-leading step for this chord type in this scale.
  /// For triads in a 7-note scale, L = T(-2)t(1) at the chord level.
  /// For seventh chords in a 7-note scale, L = T(-3)t(1) at the chord level.
  func L(_ n: Int) { // swiftlint:disable:this identifier_name
    let chordSize = chord.degrees.count
    let scaleSize = key.scale.intervals.count
    // Compute the lattice step: for coprime (chordSize, scaleSize),
    // find T,t such that T*chordSize + t*scaleSize = 1 (extended Euclidean).
    // For 3-in-7: T=5, t=-1 (equivalently T=-2, t=1).
    // For 4-in-7: T=5, t=-3 (equivalently T=-2, t=-3... check signs).
    let (bigT, littleT) = latticeStep(chordSize: chordSize, scaleSize: scaleSize)
    for _ in 0..<abs(n) {
      let sign = n > 0 ? 1 : -1
      T(sign * bigT, at: .chord)
      t(sign * littleT, at: .chord)
    }
  }

  /// Compute the basic lattice step for an n-note chord in an o-note scale.
  /// Returns (T, t) such that applying T then t moves one step along the
  /// voice-leading lattice (circle of thirds for triads in diatonic).
  private func latticeStep(chordSize: Int, scaleSize: Int) -> (Int, Int) {
    // For the common coprime cases, hardcoded from extended Euclidean:
    //   3-in-7: T=-2, t=1  (one step along the circle of thirds)
    //   4-in-7: T=5, t=-3  (one step for seventh chords)
    if chordSize == 3 && scaleSize == 7 { return (-2, 1) }
    if chordSize == 4 && scaleSize == 7 { return (5, -3) }
    return (1, 0)
  }

  // MARK: Chord identification for UI display

  /// Returns a Tonic.Chord representing the current chord in the hierarchy,
  /// identified via Tonic's chord recognition. Useful for displaying "Dm", "G/B", etc.
  /// The octave parameter places the chord in a register for pitch recognition
  /// (the result is independent of octave choice).
  func identifyChord(octave: Int = 4) -> Chord? {
    let pitches = chord.degrees.compactMap { degree -> Pitch? in
      // Resolve the degree directly rather than going through voicedDegrees,
      // since we want the chord's identity independent of inversion.
      let scaleSize = key.scale.intervals.count
      let octaveShift: Int
      if degree >= 0 {
        octaveShift = degree / scaleSize
      } else {
        octaveShift = (degree - scaleSize + 1) / scaleSize
      }
      let degreeInScale = ((degree % scaleSize) + scaleSize) % scaleSize
      let intervals = key.scale.intervals
      let semitones = intervals[degreeInScale].semitones
      let rootPitchClass = Int(key.root.canonicalNote.noteNumber) % 12
      let rootMidi = rootPitchClass + ((octave + 1) * 12)
      let midi = rootMidi + semitones + (octaveShift * 12)
      guard midi >= 0, midi <= 127 else { return nil }
      return Pitch(Int8(midi))
    }
    let pitchSet = PitchSet(pitches: pitches)
    let ranked = Chord.getRankedChords(from: pitchSet)
    return ranked.first
  }

  /// Human-readable chord name, e.g. "Dm", "G/B", "Cmaj7".
  /// Returns nil if the chord can't be identified.
  var chordName: String? {
    identifyChord()?.slashDescription
  }

  /// Roman numeral notation for the current chord, e.g. "I", "ii⁶", "V⁶₅", "viiø⁷".
  var romanNumeralName: String? {
    identifyChord()?.romanNumeralNotation(in: key, inversion: chord.inversion)
  }

  // MARK: Resolution — melody note to MIDI

  /// Resolve a MelodyNote through the hierarchy to a concrete MIDI pitch.
  /// octave: the reference octave (e.g. 4 for middle C region).
  func resolve(_ note: MelodyNote, octave: Int) -> UInt8? {
    let voiced = chord.voicedDegrees
    guard note.chordToneIndex >= 0, note.chordToneIndex < voiced.count else {
      return nil
    }

    // Step 1: chord tone index -> scale degree
    var scaleDegree = voiced[note.chordToneIndex]

    // Step 2: apply perturbation
    switch note.perturbation {
    case .none:
      break
    case .scaleDegree(let steps):
      // Move by scale steps — stays diatonic
      scaleDegree += steps
    case .chromatic:
      // Chromatic perturbation is applied after scale resolution (below)
      break
    }

    // Step 3: scale degree -> MIDI pitch (with octave wrapping)
    let scaleSize = key.scale.intervals.count
    let octaveShift: Int
    if scaleDegree >= 0 {
      octaveShift = scaleDegree / scaleSize
    } else {
      octaveShift = (scaleDegree - scaleSize + 1) / scaleSize
    }
    let degreeInScale = ((scaleDegree % scaleSize) + scaleSize) % scaleSize

    // Look up the interval from root for this scale degree.
    // Tonic's Scale.intervals are absolute from the root (P1, M2, M3, P4, ...).
    let intervals = key.scale.intervals
    let semitones = intervals[degreeInScale].semitones

    // Root MIDI note in the given octave.
    // canonicalNote.noteNumber includes an octave (e.g. C -> 60 for C4),
    // so extract just the pitch class (0-11) and place it in the requested octave.
    let rootPitchClass = Int(key.root.canonicalNote.noteNumber) % 12
    let rootMidi = rootPitchClass + ((octave + 1) * 12)
    var midi = rootMidi + semitones + (octaveShift * 12)

    // Step 4: apply chromatic perturbation (post-resolution)
    if case .chromatic(let delta) = note.perturbation {
      midi += delta
    }

    guard midi >= 0, midi <= 127 else { return nil }
    return UInt8(midi)
  }
}
