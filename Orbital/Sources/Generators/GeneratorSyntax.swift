//
//  GeneratorSyntax.swift
//  Orbital
//
//  Codable parameter types for the high-level pattern generator.
//  GeneratorSyntax is the persisted format; GeneratorEngine.generate()
//  converts it to a ScorePatternSyntax at compile time.
//

import Foundation

// MARK: - GeneratorMotion

/// The harmonic motion strategy: how the chord changes over time.
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
    }
  }
}

// MARK: - GeneratorChordType

/// The intervallic structure of the chord built on each scale degree.
enum GeneratorChordType: String, Codable, CaseIterable {
  case triad      // [0, 2, 4]        — three-note chord
  case seventh    // [0, 2, 4, 6]     — four-note seventh chord
  case ninth      // [0, 2, 4, 6, 8]  — five-note ninth chord
  case shell      // [0, 2, 6]        — jazz shell: root + third + seventh
  case powerChord // [0, 4]           — root + fifth, no third

  var displayName: String {
    switch self {
    case .triad:      return "Triad"
    case .seventh:    return "7th Chord"
    case .ninth:      return "9th Chord"
    case .shell:      return "Shell (root+3rd+7th)"
    case .powerChord: return "Power Chord"
    }
  }

  /// Scale degrees for the chord (relative to the chord root = degree 0).
  var degrees: [Int] {
    switch self {
    case .triad:      return [0, 2, 4]
    case .seventh:    return [0, 2, 4, 6]
    case .ninth:      return [0, 2, 4, 6, 8]
    case .shell:      return [0, 2, 6]
    case .powerChord: return [0, 4]
    }
  }
}

// MARK: - GeneratorTexture

/// The vertical/rhythmic texture of the output tracks.
enum GeneratorTexture: String, Codable, CaseIterable {
  case pad           // 1 track: all chord voices simultaneous (currentChord)
  case arpeggio      // 1 track: chord tones in rising sequence
  case melody        // 1 track: single melodic line through chord tones (seeded)
  case satb          // 4 tracks: bass, tenor, alto, soprano — each one voice
  case bassAndMelody // 2 tracks: bass + melody
  case full          // 3 tracks: bass + pad + melody

  var displayName: String {
    switch self {
    case .pad:           return "Pad (chord)"
    case .arpeggio:      return "Arpeggio"
    case .melody:        return "Melody"
    case .satb:          return "SATB (4 voices)"
    case .bassAndMelody: return "Bass + Melody"
    case .full:          return "Full (bass+pad+melody)"
    }
  }
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

/// Top-level Codable specification for the high-level pattern generator.
/// Persisted in the `generatorTracks` field of PatternSyntax.
/// At compile time, GeneratorEngine.generate() converts this to a ScorePatternSyntax.
struct GeneratorSyntax: Codable, Equatable {
  let rootNote: String            // "C", "Bb", "F#", …
  let scaleType: GeneratorScaleType
  let motion: GeneratorMotion
  let chordType: GeneratorChordType
  let texture: GeneratorTexture
  let bpm: Double
  let beatsPerChord: Double       // rate knob: 1–16
  let voicing: VoicingStyle?      // nil → engine picks sensible default per texture
  let randomSeed: Int?            // nil → pick new seed at generation time
  // Instrument preset filenames per logical role [pad/bass/melody/upperVoices…].
  // nil → engine uses defaults per texture.
  let presetNames: [String]?

  init(
    rootNote: String = "C",
    scaleType: GeneratorScaleType = .major,
    motion: GeneratorMotion = .fourChords,
    chordType: GeneratorChordType = .triad,
    texture: GeneratorTexture = .pad,
    bpm: Double = 90,
    beatsPerChord: Double = 4,
    voicing: VoicingStyle? = nil,
    randomSeed: Int? = nil,
    presetNames: [String]? = nil
  ) {
    self.rootNote = rootNote
    self.scaleType = scaleType
    self.motion = motion
    self.chordType = chordType
    self.texture = texture
    self.bpm = bpm
    self.beatsPerChord = beatsPerChord
    self.voicing = voicing
    self.randomSeed = randomSeed
    self.presetNames = presetNames
  }
}
