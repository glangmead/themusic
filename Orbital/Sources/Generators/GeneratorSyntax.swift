//
//  GeneratorSyntax.swift
//  Orbital
//
//  Codable parameter types for the chorale-based high-level pattern generator.
//  GeneratorSyntax is the persisted format; GeneratorEngine.generate() converts
//  it to a ScorePatternSyntax at compile time.
//
//  The generator produces bass + N upper voices (N = 2, 3, or 4 depending on
//  chord type). Voice leading follows Tymoczko's chorale model: chord progression
//  as L-powers on the diatonic spiral, upper-voice spacing via the OUCH state
//  machine (for triads) or solver-driven (for dyads and sevenths).
//

import Foundation

// MARK: - GeneratorMotion

/// The harmonic motion strategy: how the chord root changes over time.
enum GeneratorMotion: String, Codable, CaseIterable {
  // Functional (diatonic, chord-level T/setRoman operations):
  case drone               // Static — no chord changes
  case shuttle             // I ↔ V
  case plagal              // I ↔ IV
  case fourChords          // I – V – vi – IV (pop axis)
  case oneLoop             // I – V – IV
  case twoLoop             // I – bVII – bVI – IV (borrowing from parallel minor)
  case descendingThirds    // I – vi – IV – ii
  case descendingFifths    // I – IV – vii – iii – vi – ii – V – I (full circle)

  // Stochastic / open-ended:
  case randomWalk          // T(±1) each chord change, seeded
  case shepardDescent      // Endlessly T(−1) — Shepard-tone feel

  // Debussy: parallel motion within a (possibly non-diatonic) scale:
  case parallelAscending   // T(+1) every beatsPerChord
  case parallelDescending  // T(−1) every beatsPerChord
  case parallelRandom      // T(±1) seeded random walk, no tonal center

  // Debussy: macro-level scale navigation:
  case acousticBridge      // diatonic → acoustic → whole-tone → acoustic → diatonic
  case octatonicImmersion  // diatonic → octatonic → diatonic

  // Explicit sequence of T-powers (scale-step transpositions; uses tPowerSequence).
  case tPowers
  // Explicit sequence of TT-powers (chromatic-semitone transpositions; uses ttPowerSequence).
  case ttPowers

  var displayName: String {
    switch self {
    case .drone:              return "Drone"
    case .shuttle:            return "Shuttle (I↔V)"
    case .plagal:             return "Plagal (I↔IV)"
    case .fourChords:         return "Four Chords (I–V–vi–IV)"
    case .oneLoop:            return "One-Loop (I–V–IV)"
    case .twoLoop:            return "Two-Loop (I–♭VII–♭VI–IV)"
    case .descendingThirds:   return "Descending Thirds"
    case .descendingFifths:   return "Circle of Fifths"
    case .randomWalk:         return "Random Walk"
    case .shepardDescent:     return "Shepard Descent"
    case .parallelAscending:  return "Parallel Motion ↑"
    case .parallelDescending: return "Parallel Motion ↓"
    case .parallelRandom:     return "Parallel Random"
    case .acousticBridge:     return "Acoustic Bridge"
    case .octatonicImmersion: return "Octatonic Immersion"
    case .tPowers:            return "T-Power Sequence (scale steps)"
    case .ttPowers:           return "TT-Power Sequence (semitones)"
    }
  }
}

// MARK: - GeneratorChordType

/// The size of the chord being voiced. Determines the total number of Presets:
/// bass + chordSize upper voices = chordSize + 1 total.
enum GeneratorChordType: String, Codable, CaseIterable {
  case dyad     // [0, 4]       — bass + 2 upper voices
  case triad    // [0, 2, 4]    — bass + 3 upper voices (OUCH applies)
  case seventh  // [0, 2, 4, 6] — bass + 4 upper voices

  var displayName: String {
    switch self {
    case .dyad:    return "Dyad (bass + 2)"
    case .triad:   return "Triad (bass + 3)"
    case .seventh: return "7th Chord (bass + 4)"
    }
  }

  /// Scale degrees for the chord, relative to the chord root.
  var degrees: [Int] {
    switch self {
    case .dyad:    return [0, 4]
    case .triad:   return [0, 2, 4]
    case .seventh: return [0, 2, 4, 6]
    }
  }

  /// Number of upper-voice Presets (and therefore the chord-tone count).
  var upperVoiceCount: Int { degrees.count }
}

// MARK: - GeneratorScaleType

/// The macroharmony: which scale family is active.
enum GeneratorScaleType: String, Codable, CaseIterable {
  // Diatonic family:
  case major
  case naturalMinor
  case harmonicMinor
  case dorian
  case phrygian
  case lydian
  case mixolydian
  // Pentatonic:
  case pentatonicMajor
  case pentatonicMinor
  // Debussy palette (non-diatonic):
  case acoustic   // Lydian ♭7 = W W W H W H H
  case wholeTone  // W W W W W W
  case octatonic  // W H W H W H W H
  case hexatonic  // H m3 H m3 H m3 (alternating semitone and minor third)

  var displayName: String {
    switch self {
    case .major:         return "Major"
    case .naturalMinor:  return "Natural Minor"
    case .harmonicMinor: return "Harmonic Minor"
    case .dorian:        return "Dorian"
    case .phrygian:      return "Phrygian"
    case .lydian:        return "Lydian"
    case .mixolydian:    return "Mixolydian"
    case .pentatonicMajor: return "Pentatonic Major"
    case .pentatonicMinor: return "Pentatonic Minor"
    case .acoustic:      return "Acoustic (Lydian ♭7)"
    case .wholeTone:     return "Whole Tone"
    case .octatonic:     return "Octatonic"
    case .hexatonic:     return "Hexatonic"
    }
  }

  /// The Tonic scale name string used in ScoreKeySyntax / setKey events.
  var tonicScaleName: String {
    switch self {
    case .major:           return "major"
    case .naturalMinor:    return "minor"
    case .harmonicMinor:   return "harmonicMinor"
    case .dorian:          return "dorian"
    case .phrygian:        return "phrygian"
    case .lydian:          return "lydian"
    case .mixolydian:      return "mixolydian"
    case .pentatonicMajor: return "pentatonicMajor"
    case .pentatonicMinor: return "pentatonicMinor"
    case .acoustic:        return "lydianFlat7"
    case .wholeTone:       return "whole"
    case .octatonic:       return "wholeDiminished"
    case .hexatonic:       return "augmented"
    }
  }

  /// Whether this scale type supports conventional Roman-numeral functional progressions.
  var supportsFunctionalMotion: Bool {
    switch self {
    case .acoustic, .wholeTone, .octatonic, .hexatonic,
         .pentatonicMajor, .pentatonicMinor:
      return false
    default:
      return true
    }
  }
}

// MARK: - GeneratorSyntax

/// Top-level Codable specification for the chorale-based generator.
/// Persisted in the `generatorTracks` field of PatternSyntax.
/// At compile time, GeneratorEngine.generate() converts this to ScorePatternSyntax.
struct GeneratorSyntax: Codable, Equatable {
  var rootNote: String                 // "C", "Bb", "F#", …
  var scaleType: GeneratorScaleType
  var motion: GeneratorMotion
  var chordType: GeneratorChordType
  var bpm: Double
  var beatsPerChord: Double            // rate knob: 1–16
  var bassOctave: Int                  // bass preset's base octave
  var upperVoiceLowOctave: Int         // lower bound for upper-voice MIDI range
  var upperVoiceHighOctave: Int        // upper bound for upper-voice MIDI range
  var bassPresetName: String?          // nil → random pad
  var upperPresetNames: [String]?      // nil → random pads; count should match chord size
  var tPowerSequence: [Int]?           // used when motion == .tPowers
  var ttPowerSequence: [Int]?          // used when motion == .ttPowers
  var randomSeed: Int?                 // nil → pick new seed at generation time

  init(
    rootNote: String = "C",
    scaleType: GeneratorScaleType = .major,
    motion: GeneratorMotion = .fourChords,
    chordType: GeneratorChordType = .triad,
    bpm: Double = 10,
    beatsPerChord: Double = 4,
    bassOctave: Int = 2,
    upperVoiceLowOctave: Int = 3,
    upperVoiceHighOctave: Int = 5,
    bassPresetName: String? = nil,
    upperPresetNames: [String]? = nil,
    tPowerSequence: [Int]? = nil,
    ttPowerSequence: [Int]? = nil,
    randomSeed: Int? = nil
  ) {
    self.rootNote = rootNote
    self.scaleType = scaleType
    self.motion = motion
    self.chordType = chordType
    self.bpm = bpm
    self.beatsPerChord = beatsPerChord
    self.bassOctave = bassOctave
    self.upperVoiceLowOctave = upperVoiceLowOctave
    self.upperVoiceHighOctave = upperVoiceHighOctave
    self.bassPresetName = bassPresetName
    self.upperPresetNames = upperPresetNames
    self.tPowerSequence = tPowerSequence
    self.ttPowerSequence = ttPowerSequence
    self.randomSeed = randomSeed
  }
}
