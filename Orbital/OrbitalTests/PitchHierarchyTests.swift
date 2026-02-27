//
//  PitchHierarchyTests.swift
//  OrbitalTests
//
//  Tests for PitchHierarchy: resolve, T, t, L, chord identification, roman numerals.
//

import Testing
import Foundation
import Tonic
@testable import Orbital

// MARK: - Resolution

@Suite("PitchHierarchy resolution", .serialized)
struct ResolutionTests {

  @Test("C major I chord resolves to C4 E4 G4")
  func cMajorIChord() {
    let h = PitchHierarchy(root: .C)
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 60)
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 64)
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 67)
  }

  @Test("D major I chord resolves to D4 F#4 A4")
  func dMajorIChord() {
    let h = PitchHierarchy(root: .C)
    h.T(2, at: .scale)
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 62)
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 66)
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 69)
  }

  @Test("Out-of-range chord tone index returns nil")
  func outOfRange() {
    let h = PitchHierarchy(root: .C)
    #expect(h.resolve(MelodyNote(chordToneIndex: 3, perturbation: .none), octave: 4) == nil)
    #expect(h.resolve(MelodyNote(chordToneIndex: -1, perturbation: .none), octave: 4) == nil)
  }
}

// MARK: - Perturbation (NHT)

@Suite("Non-harmonic tone perturbation")
struct PerturbationTests {

  @Test("Scale-degree perturbation: passing tone above chord tone")
  func scaleDegreeUp() {
    let h = PitchHierarchy(root: .C)
    // Chord tone 0 is scale degree 0 = C (60). +1 scale step = D (62).
    let note = MelodyNote(chordToneIndex: 0, perturbation: .scaleDegree(1))
    #expect(h.resolve(note, octave: 4) == 62)
  }

  @Test("Chromatic perturbation: sharp neighbor")
  func chromaticUp() {
    let h = PitchHierarchy(root: .C)
    // Chord tone 0 = C (60). +1 chromatic = C# (61).
    let note = MelodyNote(chordToneIndex: 0, perturbation: .chromatic(1))
    #expect(h.resolve(note, octave: 4) == 61)
  }

  @Test("Negative scale-degree perturbation wraps octave")
  func negativeDegree() {
    let h = PitchHierarchy(root: .C)
    // Chord tone 0 = scale degree 0 = C (60). -1 scale step = B below (59).
    let note = MelodyNote(chordToneIndex: 0, perturbation: .scaleDegree(-1))
    #expect(h.resolve(note, octave: 4) == 59)
  }
}

// MARK: - Chord-level T and t

@Suite("Chord-level transformations", .serialized)
struct ChordTransformTests {

  @Test("T(1) at chord: I → ii (D F A)")
  func chordT1() {
    let h = PitchHierarchy(root: .C)
    h.T(1, at: .chord)
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 62)  // D
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 65)  // F
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 69)  // A
  }

  @Test("t(1) at chord: first inversion reorders to E G C")
  func chordInversion() {
    let h = PitchHierarchy(root: .C)
    h.t(1, at: .chord)
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 64)  // E
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 67)  // G
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 60)  // C
  }
}

// MARK: - Scale-level T

@Suite("Scale-level T (transposition)", .serialized)
struct ScaleTTests {

  @Test("T(2) at scale: C major → D major")
  func twoSemitones() {
    let h = PitchHierarchy(root: .C)
    h.T(2, at: .scale)
    #expect(h.key.root == .D)
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 62)
  }

  @Test("T(7) at scale: C major → G major")
  func sevenSemitones() {
    let h = PitchHierarchy(root: .C)
    h.T(7, at: .scale)
    #expect(h.key.root == .G)
    // G major I = G B D
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 67)
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 71)
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 74)
  }

  @Test("T(0) at scale is a no-op")
  func zeroIsNoop() {
    let h = PitchHierarchy(root: .C)
    h.T(0, at: .scale)
    #expect(h.key.root == .C)
  }
}

// MARK: - Scale-level t (modal rotation)

@Suite("Scale-level t (modal rotation)", .serialized)
struct ScaletTests {

  @Test("t(1) at scale: C Ionian → D Dorian")
  func dorian() {
    let h = PitchHierarchy(root: .C)
    h.t(1, at: .scale)
    #expect(h.key.root == .D)
    #expect(h.key.scale == .dorian)
    // D Dorian i = D F A (all natural, same white keys as C major)
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 62)
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 65)
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 69)
  }

  @Test("t(2) at scale: C Ionian → E Phrygian")
  func phrygian() {
    let h = PitchHierarchy(root: .C)
    h.t(2, at: .scale)
    #expect(h.key.root == .E)
    #expect(h.key.scale == .phrygian)
    // E Phrygian i = E G B
    #expect(h.resolve(MelodyNote(chordToneIndex: 0, perturbation: .none), octave: 4) == 64)
    #expect(h.resolve(MelodyNote(chordToneIndex: 1, perturbation: .none), octave: 4) == 67)
    #expect(h.resolve(MelodyNote(chordToneIndex: 2, perturbation: .none), octave: 4) == 71)
  }

  @Test("t(0) at scale is a no-op")
  func zeroIsNoop() {
    let h = PitchHierarchy(root: .C)
    h.t(0, at: .scale)
    #expect(h.key.root == .C)
    #expect(h.key.scale == .major)
  }
}

// MARK: - Chord identification

@Suite("Chord identification", .serialized)
struct ChordIdentificationTests {

  @Test("All diatonic triads in C major")
  func diatonicTriads() {
    let expected = ["C", "Dm", "Em", "F", "G", "Am", "B°"]
    let h = PitchHierarchy(root: .C)
    for i in 0..<7 {
      if i > 0 { h.T(1, at: .chord) }
      #expect(h.chordName == expected[i], "Degree \(i): expected \(expected[i]), got \(h.chordName ?? "nil")")
    }
  }

  @Test("Inversion doesn't change chord identity")
  func inversionIdentity() {
    let h = PitchHierarchy(root: .C)
    h.t(1, at: .chord)
    #expect(h.chordName == "C")
    h.t(1, at: .chord)
    #expect(h.chordName == "C")
  }

  @Test("Seventh chord identification")
  func seventhChord() {
    let h = PitchHierarchy(
      key: Key(root: .C, scale: .major),
      chord: ChordInScale(degrees: [4, 6, 8, 10], inversion: 0)
    )
    #expect(h.chordName == "G7")
  }
}

// MARK: - Roman numeral notation

@Suite("Roman numeral notation", .serialized)
struct RomanNumeralTests {

  @Test("Diatonic triads in C major")
  func diatonicTriads() {
    let expected = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
    let h = PitchHierarchy(root: .C)
    for i in 0..<7 {
      if i > 0 { h.T(1, at: .chord) }
      #expect(h.romanNumeralName == expected[i],
              "Degree \(i): expected \(expected[i]), got \(h.romanNumeralName ?? "nil")")
    }
  }

  @Test("Diatonic seventh chords in C major")
  func diatonicSevenths() {
    let expected = ["IM⁷", "ii⁷", "iii⁷", "IVM⁷", "V⁷", "vi⁷", "viiø⁷"]
    let h = PitchHierarchy(
      key: Key(root: .C, scale: .major),
      chord: ChordInScale(degrees: [0, 2, 4, 6], inversion: 0)
    )
    for i in 0..<7 {
      if i > 0 { h.T(1, at: .chord) }
      #expect(h.romanNumeralName == expected[i],
              "Degree \(i): expected \(expected[i]), got \(h.romanNumeralName ?? "nil")")
    }
  }

  @Test("D Dorian i chord shows lowercase")
  func dorianMinor() {
    let h = PitchHierarchy(root: .C)
    h.t(1, at: .scale)
    #expect(h.romanNumeralName == "i")
  }
}

// MARK: - Figured bass (inversion notation)

@Suite("Figured bass notation", .serialized)
struct FiguredBassTests {

  @Test("Triad inversions: I → I⁶ → I⁶₄")
  func triadInversions() {
    let h = PitchHierarchy(root: .C)
    #expect(h.romanNumeralName == "I")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "I⁶")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "I⁶₄")
  }

  @Test("Diminished triad inversions preserve °")
  func dimTriadInversions() {
    let h = PitchHierarchy(root: .C)
    h.T(6, at: .chord)  // vii°
    #expect(h.romanNumeralName == "vii°")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "vii°⁶")
  }

  @Test("Seventh chord inversions: V⁷ → V⁶₅ → V⁴₃ → V⁴₂")
  func seventhInversions() {
    let h = PitchHierarchy(
      key: Key(root: .C, scale: .major),
      chord: ChordInScale(degrees: [4, 6, 8, 10], inversion: 0)
    )
    #expect(h.romanNumeralName == "V⁷")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "V⁶₅")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "V⁴₃")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "V⁴₂")
  }

  @Test("Half-diminished seventh inversions preserve ø")
  func halfDimInversions() {
    let h = PitchHierarchy(
      key: Key(root: .C, scale: .major),
      chord: ChordInScale(degrees: [6, 8, 10, 12], inversion: 0)
    )
    #expect(h.romanNumeralName == "viiø⁷")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "viiø⁶₅")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "viiø⁴₃")
    h.t(1, at: .chord)
    #expect(h.romanNumeralName == "viiø⁴₂")
  }
}

// MARK: - Lattice step (L)

@Suite("Lattice step L")
struct LatticeTests {

  @Test("L(1) on I triad in C major: I → vi (circle of thirds)")
  func latticeStep() {
    let h = PitchHierarchy(root: .C)
    h.L(1)
    // L = T(-2)t(1): degrees [0,2,4] → T(-2) → [-2,0,2] → t(1) → inv 1
    // That's vi chord in first inversion. The chord identity is Am.
    #expect(h.chordName == "Am")
  }
}
