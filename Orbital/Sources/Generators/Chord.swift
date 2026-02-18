//
//  Chord.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/13/26.
//

import Foundation
import Tonic

// For us a chord is a small scale, usually striving for consonance when sounded together.
// As such it is just a set of N pitch classes, with no octave or voicing information.
// If it has 3 pitch classes, then we can indicate a voicing with a list like 1,2,3,4,5,6,7,8,9,... if all three notes are sounded in every octave.
// A smaller list like 1,3,5 says to play the root and fifth in the lowest octave, and play the third in the second lowest octave).
// These lists just need a specification of which octave their numbering starts from, i.e. what MIDI note is "1".
enum Voicing {
  
  case tight // [1, 2, 3]
}
