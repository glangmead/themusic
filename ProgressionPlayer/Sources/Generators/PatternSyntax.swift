//
//  PatternSyntax.swift
//  ProgressionPlayer
//
//  Codable serialization layer for MusicPattern.
//  PatternSyntax -> compile() -> MusicPattern
//  Parallels PresetSyntax -> compile() -> Preset.
//

import Foundation
import Tonic

// MARK: - NoteSyntax

/// A single MIDI note specification in JSON.
struct NoteSyntax: Codable {
  let midi: UInt8
  let velocity: UInt8?

  var midiNote: MidiNote {
    MidiNote(note: midi, velocity: velocity ?? 127)
  }
}

// MARK: - ChordSyntax

/// A simultaneous group of notes.
struct ChordSyntax: Codable {
  let notes: [NoteSyntax]

  var midiNotes: [MidiNote] {
    notes.map { $0.midiNote }
  }
}

// MARK: - TimingSyntax

/// Controls sustain or gap duration generation.
enum TimingSyntax: Codable {
  case fixed(value: CoreFloat)
  case random(min: CoreFloat, max: CoreFloat)
  case list(values: [CoreFloat])

  func compile() -> any IteratorProtocol<CoreFloat> {
    switch self {
    case .fixed(let value):
      return [value].cyclicIterator()
    case .random(let min, let max):
      return FloatSampler(min: min, max: max)
    case .list(let values):
      return values.cyclicIterator()
    }
  }
}

// MARK: - ModulatorSyntax

/// A parameter modulator: targets a named constant in the preset and drives it with an arrow.
struct ModulatorSyntax: Codable {
  let target: String
  let arrow: ArrowSyntax

  func compile() -> (String, Arrow11) {
    (target, arrow.compile())
  }
}

// MARK: - RootProgressionSyntax

/// A time-varying sequence of root notes, cycled with a random wait between changes.
struct RootProgressionSyntax: Codable {
  let roots: [String]
  let waitMin: CoreFloat
  let waitMax: CoreFloat
}

// MARK: - NoteGeneratorSyntax

/// Different strategies for generating sequences of [MidiNote].
enum NoteGeneratorSyntax: Codable {
  /// Explicit list of chords, cycled forever.
  case fixed(events: [ChordSyntax])

  /// Random notes sampled from a scale.
  case scaleSampler(scale: String, root: String, octaves: [Int]?)

  /// Chord progressions from a Markov model (e.g., Tymoczko baroque style).
  case chordProgression(scale: String, root: String, style: String?)

  /// Single-note melody from scale degrees with configurable traversal order.
  /// When `rootProgression` is provided, the root cycles through the list
  /// with a random wait (in seconds) between changes.
  case melodic(
    scale: String,
    root: String,
    octaves: [Int],
    degrees: [Int],
    ordering: String?,
    rootProgression: RootProgressionSyntax?
  )

  func compile() -> any IteratorProtocol<[MidiNote]> {
    switch self {
    case .fixed(let events):
      let chords = events.map { $0.midiNotes }
      return chords.cyclicIterator()

    case .scaleSampler(let scaleName, _, _):
      let scale = Self.resolveScale(scaleName)
      return ScaleSampler(scale: scale)

    case .chordProgression(let scaleName, let rootName, _):
      let scale = Self.resolveScale(scaleName)
      let root = Self.resolveNoteClass(rootName)
      return Midi1700sChordGenerator(
        scaleGenerator: [scale].cyclicIterator(),
        rootNoteGenerator: [root].cyclicIterator()
      )

    case .melodic(let scaleName, let rootName, let octaves, let degrees, let ordering, let rootProgression):
      let scale = Self.resolveScale(scaleName)
      let order = ordering ?? "shuffled"

      let degreeIter: any IteratorProtocol<Int> = Self.makeOrdering(degrees, order: order)
      let octaveIter: any IteratorProtocol<Int> = Self.makeOrdering(octaves, order: "random")

      let rootIter: any IteratorProtocol<NoteClass>
      if let prog = rootProgression {
        let roots = prog.roots.map { Self.resolveNoteClass($0) }
        rootIter = WaitingIterator(
          iterator: roots.cyclicIterator(),
          timeBetweenChanges: ArrowRandom(min: prog.waitMin, max: prog.waitMax)
        )
      } else {
        let root = Self.resolveNoteClass(rootName)
        rootIter = [root].cyclicIterator()
      }

      return MidiPitchAsChordGenerator(
        pitchGenerator: MidiPitchGenerator(
          scaleGenerator: [scale].cyclicIterator(),
          degreeGenerator: degreeIter,
          rootNoteGenerator: rootIter,
          octaveGenerator: octaveIter
        )
      )
    }
  }

  // MARK: - Name Resolution

  static func resolveScale(_ name: String) -> Scale {
    switch name.lowercased() {
    case "major":          return .major
    case "minor", "aeolian": return .aeolian
    case "lydian":         return .lydian
    case "dorian":         return .dorian
    case "mixolydian":     return .mixolydian
    case "phrygian":       return .phrygian
    case "locrian":        return .locrian
    case "harmonicminor":  return .harmonicMinor
    case "melodicminor":   return .melodicMinor
    case "pentatonicmajor": return .pentatonicMajor
    case "pentatonicminor": return .pentatonicMinor
    case "chromatic":      return .chromatic
    default:               return .major
    }
  }

  static func resolveNoteClass(_ name: String) -> NoteClass {
    switch name {
    case "C":        return .C
    case "Cs", "C#": return .Cs
    case "Db":       return .Db
    case "D":        return .D
    case "Ds", "D#": return .Ds
    case "Eb":       return .Eb
    case "E":        return .E
    case "F":        return .F
    case "Fs", "F#": return .Fs
    case "Gb":       return .Gb
    case "G":        return .G
    case "Gs", "G#": return .Gs
    case "Ab":       return .Ab
    case "A":        return .A
    case "As", "A#": return .As
    case "Bb":       return .Bb
    case "B":        return .B
    default:         return .C
    }
  }

  private static func makeOrdering<T>(_ items: [T], order: String) -> any IteratorProtocol<T> {
    switch order.lowercased() {
    case "cyclic":   return items.cyclicIterator()
    case "random":   return items.randomIterator()
    case "shuffled": return items.shuffledIterator()
    default:         return items.cyclicIterator()
    }
  }
}

// MARK: - PatternSyntax

/// Top-level Codable specification for a generative music pattern.
/// Parallels PresetSyntax: decode from JSON, then compile() to get a runtime MusicPattern.
struct PatternSyntax: Codable {
  let name: String
  let presetName: String
  let numVoices: Int?
  let noteGenerator: NoteGeneratorSyntax
  let sustain: TimingSyntax
  let gap: TimingSyntax
  let modulators: [ModulatorSyntax]?

  /// Compile into a MusicPattern using an already-constructed SpatialPreset.
  /// The caller is responsible for resolving the presetName and creating
  /// the SpatialPreset with the appropriate engine.
  func compile(spatialPreset: SpatialPreset, clock: any Clock<Duration> = ContinuousClock()) -> MusicPattern {
    let modulatorDict: [String: Arrow11]
    if let mods = modulators {
      modulatorDict = Dictionary(
        mods.map { $0.compile() },
        uniquingKeysWith: { first, _ in first }
      )
    } else {
      modulatorDict = [:]
    }

    return MusicPattern(
      spatialPreset: spatialPreset,
      modulators: modulatorDict,
      notes: noteGenerator.compile(),
      sustains: sustain.compile(),
      gaps: gap.compile(),
      clock: clock
    )
  }

  /// Convenience: compile from a PresetSyntax and engine, creating the SpatialPreset internally.
  /// Returns both the MusicPattern and the SpatialPreset (caller must hold a reference to the
  /// SpatialPreset to keep the audio nodes alive, and must call cleanup() when done).
  func compile(presetSpec: PresetSyntax, engine: SpatialAudioEngine, clock: any Clock<Duration> = ContinuousClock()) -> (MusicPattern, SpatialPreset) {
    let voices = numVoices ?? 12
    let sp = SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: voices)
    let pattern = compile(spatialPreset: sp, clock: clock)
    return (pattern, sp)
  }
}
