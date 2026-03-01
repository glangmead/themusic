//
//  HierarchyGenerators.swift
//  Orbital
//
//  Hierarchy-aware note generators extracted from Iterators.swift.
//

import Foundation
import Tonic

// MARK: - MarkovChordIterator

/// Emits ChordInScale values following the Tymoczko baroque/classical major Markov chain
/// (diagram 7.1.3 of Tymoczko's "Tonality"). The first call always returns chord I.
/// Subsequent calls advance the chain probabilistically.
/// Used as the implementation for the "markovChord" hierarchy modulator operation.
struct MarkovChordIterator: Sequence, IteratorProtocol {
  private var current: ChordInScale.RomanNumerals = .I
  private var isFirstCall = true

  mutating func next() -> ChordInScale? {
    guard !isFirstCall else {
      isFirstCall = false
      return ChordInScale(romanNumeral: current)
    }
    let candidates = ChordInScale.RomanNumerals.stateTransitionsBaroqueClassicalMajor(current)
    guard let nextChord = ChordInScale.RomanNumerals.weightedDraw(items: candidates) else { return nil }
    current = nextChord
    print("MarkovChordIterator picked \(nextChord.displayName)")
    return ChordInScale(romanNumeral: nextChord)
  }
}

// generate an exact MidiValue
struct MidiPitchGenerator: Sequence, IteratorProtocol {
  var scaleGenerator: any IteratorProtocol<Scale>
  var degreeGenerator: any IteratorProtocol<Int>
  var rootNoteGenerator: any IteratorProtocol<NoteClass>
  var octaveGenerator: any IteratorProtocol<Int>

  mutating func next() -> MidiValue? {
    // a scale is a collection of intervals
    let scale = scaleGenerator.next()!
    // a degree is a position within the scale
    let degree = degreeGenerator.next()!
    // from these two we can get a specific interval
    let interval = scale.intervals[degree]

    let root = rootNoteGenerator.next()!
    let octave = octaveGenerator.next()!
    // knowing the root class and octave gives us the root note of this scale
    let note = Note(root.letter, accidental: root.accidental, octave: octave)
    return MidiValue(note.shiftUp(interval)!.noteNumber)
  }
}

// when velocity is not meaningful
struct MidiPitchAsChordGenerator: Sequence, IteratorProtocol {
  var pitchGenerator: MidiPitchGenerator
  mutating func next() -> [MidiNote]? {
    guard let pitch = pitchGenerator.next() else { return nil }
    return [MidiNote(note: pitch, velocity: 127)]
  }
}

// MARK: - HierarchyChordGenerator

/// Generates [MidiNote] from the shared hierarchy's current voiced chord.
/// The octave for the chord's bass note comes from the octaveEmitter.
struct HierarchyChordGenerator: Sequence, IteratorProtocol {
  let hierarchy: PitchHierarchy
  let voicing: VoicingStyle
  var octaveEmitter: any IteratorProtocol<Int>

  mutating func next() -> [MidiNote]? {
    guard let octave = octaveEmitter.next() else { return nil }
    let midis = hierarchy.voicedMidi(voicing: voicing, baseOctave: octave)
    guard !midis.isEmpty else { return nil }
    return midis.map { MidiNote(note: MidiValue($0), velocity: 127) }
  }
}

// MARK: - HierarchyMelodyGenerator

/// Generates single-note melodies by resolving degrees through the shared hierarchy.
/// The `level` parameter controls whether resolution uses the chord layer or scale layer:
///   - .scale: degreeEmitter emits scale degree values directly (supports large ranges with
///             octave wrapping, e.g. using a fragment-pool emitter over a chromatic scale).
///   - .chord: degreeEmitter emits chord-tone indices into the hierarchy's voicedDegrees.
struct HierarchyMelodyGenerator: Sequence, IteratorProtocol {
  let hierarchy: PitchHierarchy
  let level: HierarchyLevel
  var degreeEmitter: any IteratorProtocol<Int>
  var octaveEmitter: any IteratorProtocol<Int>

  mutating func next() -> [MidiNote]? {
    guard let degree = degreeEmitter.next() else { return nil }
    guard let octave = octaveEmitter.next() else { return nil }
    let note = MelodyNote(chordToneIndex: degree, perturbation: .none)
    guard let midi = hierarchy.resolve(note, at: level, octave: octave) else { return nil }
    return [MidiNote(note: MidiValue(midi), velocity: 127)]
  }
}
