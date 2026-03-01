//
//  QuadHierarchy.swift
//  Orbital
//
//  Created by Greg Langmead on 1/13/26.
//
//  Tonic framework extensions → TonicExtensions.swift
//

import Foundation
import Tonic

// MARK: - Chord as relative scale degrees
// See docs/hierarchical_pitch_design_notes.md for the full design rationale.

/// A chord expressed as scale degrees within a key, not absolute pitch classes.
/// e.g. [0, 2, 4] = triad built on the root (I chord).
/// T(1) shifts all degrees by 1: [0, 2, 4] -> [1, 3, 5] (ii chord).
/// t(1) rotates the ordering: bass moves from degree 0 to degree 2 (first inversion).
struct ChordInScale {
  var degrees: [Int]      // scale degrees, e.g. [0, 2, 4]
  var inversion: Int      // rotation: which degree is the bass (0 = root position)
  var perturbations: [Perturbation]?  // per-degree chromatic offsets, parallel to degrees

  init(degrees: [Int], inversion: Int, perturbations: [Perturbation]? = nil) {
    self.degrees = degrees
    self.inversion = inversion
    self.perturbations = perturbations
  }

  /// The degrees in voiced order (bass note first), accounting for inversion.
  var voicedDegrees: [Int] {
    guard !degrees.isEmpty else { return [] }
    let count = degrees.count
    let inv = ((inversion % count) + count) % count
    return Array(degrees[inv...]) + Array(degrees[..<inv])
  }

  /// Perturbations in voiced order (bass first), rotating in lockstep with voicedDegrees.
  /// Pads with .none if perturbations array is shorter than degrees.
  var voicedPerturbations: [Perturbation]? {
    guard let perturbs = perturbations, !degrees.isEmpty else { return nil }
    let count = degrees.count
    let inv = ((inversion % count) + count) % count
    var padded = Array(perturbs.prefix(count))
    while padded.count < count { padded.append(.none) }
    return Array(padded[inv...]) + Array(padded[..<inv])
  }

  /// T: shift all degrees by n steps in the parent scale.
  /// I [0,2,4] -> T(1) -> ii [1,3,5] -> T(1) -> iii [2,4,6] ...
  mutating func T(_ n: Int) {
    degrees = degrees.map { $0 + n }
  }

  /// t: rotate the voicing. t(1) = first inversion, t(2) = second inversion.
  mutating func t(_ n: Int) {
    inversion += n
  }
}

// MARK: Melody note as a query against the hierarchy

/// How a melody note departs from a chord tone.
/// A note is either a plain chord tone, or a chord tone perturbed by a
/// neighbor — either chromatically (semitones) or within the scale (steps).
enum Perturbation: Equatable {
  case none
  case chromatic(Int)      // semitones from the chord tone
  case scaleDegree(Int)    // scale steps from the chord tone
}

/// Codable representation of a Perturbation for JSON storage.
/// - `{}` or both fields nil → .none
/// - `{"chromatic": N}` → .chromatic(N)
/// - `{"scaleDegree": N}` → .scaleDegree(N)
struct PerturbationSyntax: Codable, Equatable {
  let chromatic: Int?
  let scaleDegree: Int?

  init(chromatic: Int? = nil, scaleDegree: Int? = nil) {
    self.chromatic = chromatic
    self.scaleDegree = scaleDegree
  }

  func toPerturbation() -> Perturbation {
    if let c = chromatic { return .chromatic(c) }
    if let s = scaleDegree { return .scaleDegree(s) }
    return .none
  }
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
enum HierarchyLevel: String, Codable, CaseIterable {
  case scale
  case chord
}

// MARK: - Voicing

/// How to distribute chord voices vertically above (and including) the bass note.
enum VoicingStyle: String, Codable, CaseIterable {
  /// All voices packed upward from the bass within one octave span.
  case closed
  /// Every other voice raised an octave — classical open position (~10th span).
  case open
  /// Drop-2: second-from-top voice drops an octave. Classic jazz piano texture.
  case dropTwo
  /// Voices spread evenly across a ~2-octave range.
  case spread
  /// Third + seventh only, omit the fifth (jazz shell).
  case shell
  /// Root + fifth only, no third — ambiguous quality.
  case fifthsOnly
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
  func T(_ n: Int, at level: HierarchyLevel) {
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
  func t(_ n: Int, at level: HierarchyLevel) {
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
  func L(_ n: Int) {
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

  /// Resolve a scale degree directly to a MIDI pitch, ignoring the chord layer.
  /// Use this for scale-relative melodies that follow key/mode but not chord.
  private func resolveScaleDegree(_ degree: Int, octave: Int) -> UInt8? {
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
    let rootPC = Int(key.root.canonicalNote.noteNumber) % 12
    let midi = rootPC + ((octave + 1) * 12) + semitones + (octaveShift * 12)
    guard midi >= 0, midi <= 127 else { return nil }
    return UInt8(midi)
  }

  /// Resolve a MelodyNote through the hierarchy to a concrete MIDI pitch.
  /// - at .chord: chordToneIndex indexes into voicedDegrees; supports perturbation.
  /// - at .scale: chordToneIndex is used directly as a scale degree; supports perturbation.
  /// octave: the reference octave (e.g. 4 for middle C region).
  func resolve(_ note: MelodyNote, at level: HierarchyLevel = .chord, octave: Int) -> UInt8? {
    switch level {
    case .scale:
      var degree = note.chordToneIndex
      switch note.perturbation {
      case .none: break
      case .scaleDegree(let steps): degree += steps
      case .chromatic: break
      }
      var midi = Int(resolveScaleDegree(degree, octave: octave) ?? 0)
      if case .chromatic(let delta) = note.perturbation { midi += delta }
      guard midi >= 0, midi <= 127 else { return nil }
      return UInt8(midi)
    case .chord:
      break
    }
    // .chord path — original implementation below
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

    // Step 3.5: apply the chord's own chromatic perturbation for this voice slot
    if let vp = chord.voicedPerturbations, note.chordToneIndex < vp.count,
       case .chromatic(let delta) = vp[note.chordToneIndex] {
      midi += delta
    }

    // Step 4: apply MelodyNote's chromatic perturbation (post-resolution)
    if case .chromatic(let delta) = note.perturbation {
      midi += delta
    }

    guard midi >= 0, midi <= 127 else { return nil }
    return UInt8(midi)
  }

  // MARK: Chord voicing for chord-track output

  /// MIDI pitch of the bass note (voicedDegrees[0]) at the given octave.
  func bassMidi(baseOctave: Int) -> UInt8? {
    guard let degree = chord.voicedDegrees.first else { return nil }
    var midi = Int(resolveScaleDegree(degree, octave: baseOctave) ?? 0)
    if let vp = chord.voicedPerturbations, let first = vp.first,
       case .chromatic(let delta) = first {
      midi += delta
    }
    guard midi >= 0, midi <= 127 else { return nil }
    return UInt8(midi)
  }

  /// All chord voices as MIDI pitches, distributed according to the VoicingStyle.
  /// The bass note (voicedDegrees[0]) anchors at baseOctave; upper voices are
  /// arranged above it.
  func voicedMidi(voicing: VoicingStyle, baseOctave: Int) -> [UInt8] {
    let degrees = chord.voicedDegrees
    guard !degrees.isEmpty else { return [] }

    // Resolve all degrees in closed position (bass at baseOctave, each subsequent
    // voice placed just above the previous).
    var closed: [Int] = []
    let voicedPerturbs = chord.voicedPerturbations
    for (i, degree) in degrees.enumerated() {
      guard var midi = resolveScaleDegree(degree, octave: baseOctave).map(Int.init) else { continue }
      // Apply chromatic perturbation for this voice (before octave bumping)
      if let vp = voicedPerturbs, i < vp.count, case .chromatic(let delta) = vp[i] {
        midi += delta
      }
      // Bump up until it's above the previous note
      if let prev = closed.last {
        while midi <= prev { midi += 12 }
      }
      if i == 0 { /* bass stays at baseOctave */ }
      closed.append(midi)
    }
    guard !closed.isEmpty else { return [] }

    var result: [Int]
    switch voicing {
    case .closed:
      result = closed

    case .open:
      // Raise every other upper voice by an octave (classic open position)
      result = closed
      for i in stride(from: 2, to: result.count, by: 2) {
        result[i] += 12
      }

    case .dropTwo:
      // Drop the second-from-top voice down an octave
      result = closed
      if result.count >= 2 {
        result[result.count - 2] -= 12
        result.sort()
      }

    case .spread:
      // Distribute voices evenly across a 2-octave range above bass
      result = closed
      let n = result.count
      if n > 1 {
        let bass = result[0]
        let span = 24  // 2 octaves
        for i in 1..<n {
          result[i] = bass + (span * i / (n - 1))
        }
      }

    case .shell:
      // Root + third + seventh (indices 0, 1, 3 for a seventh chord; 0,1 for triad)
      let keep: [Int] = degrees.count >= 4
        ? [0, 1, 3]
        : [0, 1]
      result = keep.compactMap { i in i < closed.count ? closed[i] : nil }

    case .fifthsOnly:
      // Root + fifth (indices 0, 2 in a triad; 0, 2 in a seventh)
      let keep = [0, 2]
      result = keep.compactMap { i in i < closed.count ? closed[i] : nil }
    }

    return result.compactMap { midi in
      guard midi >= 0, midi <= 127 else { return nil }
      return UInt8(midi)
    }
  }
}
