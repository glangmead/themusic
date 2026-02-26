//
//  QuadHierarchy.swift
//  Orbital
//
//  Created by Greg Langmead on 1/13/26.
//

import Foundation
import Tonic

/// A type theory for musical space

/// MidiPitch: 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72
/// CMaj:      D2    E2 F2    G2    A3    B3 C3    D3    E3 F3    G3    A4    B4 C4
/// CMaj:      -6    -5 -4    -3    -2    -1  0     1     2  3     4     5     6  7
/// I:               -2       -1              0           1        2              3
/// Bass:                                     X

// CMaj is a Z/7-torsor of Z-torsors.
// CMaj is a scale, a subset of the chromatic MidiPitch universe.
// CMaj has a 0th element, its origin C3.
// CMaj has a 0th pitch class, the C pitch class.
// CMaj is a disjoint union of 7 Z-torsors, with a designated Z-torsor (the C class).
// CMaj is given a Z/7 structure by ordering the Z-torsors.
// The Z/7 structure is how we can index into it.

// The I chord's pitch collection is "the 0, 2, 4 +/- 7Z of CMaj" with origin CMaj.0.
// It is given a Z/3 structure by ordering the pitch classes.
// This Z/3 structure allows us to index into it.

// The Bass note is to be 0 in I. A single Z-torsor.

// What are T, t, L, J, K as types?

// We want music to take place just in the types, but at any time be able to render to MIDI notes.

// How does a torsor-chord specify which notes in the torsor-scale it contains? It can't be via integer offsets as these are absolute. Or am I being overly pedantic? What advantage do we gain from leaving things as torsors for a long time?

// maybe all that matters is that i implement T and t and so on, regardless of how clever I'm being with torsors.

// Tonic.Letter:    enum of A, B, C, D, E, F, G
// Tonic.NoteClass: pitch class
// Tonic.Note:      absolute: NoteClass + octave
// Tonic.Pitch:     midi value UInt8
// Tonic.Interval:  enum of minor second, perfect fifth and so on
// Tonic.Scale:     list of Intervals
// Tonic.NoteSet/PitchSet/NoteClassSet
// Tonic.Key:       root NoteClass + Scale
// Tonic.ChordType: enum of 29 values: majorTriad, minorEleventh, ...
// Tonic.Chord:     absolute or not: from (NoteClass, ChordType, Inversion) or NoteSet, or [Note]
//                  Inversion is an index of which chord note is the bass (so usually 0-3)

// Embrace Tonic and implement the quadruple hierarchy with types:
// chromatic -> scale -> chord -> melodyNote
// then I'd use Pitch -> Key -> Chord -> Interval? Inversion?
// Arca and Harmonia index into the Chord with an integer, like Inversion.
// Which means which Pitch that is will change if the inversion changes.
// So if Inversion is metadata on top of Chord, then a melody note is an offset from Inversion.
// i.e. an offset of 0 means "the bass note of the chord, whichever that is in the current inversion."
// But what about effects that desire to use the same absolute pitch while the inversion changes?
// I guess we could have a data structure that is an (Int, Bool) where the bool says "absolute in chord or +Inversion"

// A PitchCollection is a set of indices into a parent pitch collection.
// If parent == nil then the pitches are assumed to be MidiValues (cast to Int), else
// indices into parent.pitches.
class PitchCollection {
  let pitches: [Int]
  let parent: PitchCollection?
  
  init(pitches: [Int], parent: PitchCollection?) {
    self.pitches = pitches
    self.parent = parent
  }
}


