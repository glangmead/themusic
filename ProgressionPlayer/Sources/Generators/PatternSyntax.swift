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

// MARK: - IteratorSyntax

/// Compositional specification for how to iterate over a list of values.
/// Decodes from JSON as either a bare string ("cyclic", "shuffled", "random")
/// or a nested object for composed iterators like "waiting".
///
/// Examples:
///   "cyclic"
///   "shuffled"
///   "random"
///   { "waiting": { "iterator": "cyclic", "timeBetweenChanges": { "exponentialRand": { "min": 10, "max": 25 } } } }
///   { "waiting": { "iterator": "shuffled", "timeBetweenChanges": { "rand": { "min": 5, "max": 15 } } } }
enum IteratorSyntax: Codable {
  case cyclic
  case shuffled
  case random
  indirect case waiting(iterator: IteratorSyntax, timeBetweenChanges: ArrowSyntax)

  /// Compile this syntax into a live iterator over the given items.
  func compile<T>(_ items: [T]) -> any IteratorProtocol<T> {
    switch self {
    case .cyclic:
      return items.cyclicIterator()
    case .shuffled:
      return items.shuffledIterator()
    case .random:
      return items.randomIterator()
    case .waiting(let innerSyntax, let arrowSyntax):
      let inner = innerSyntax.compile(items)
      let arrow = arrowSyntax.compile().wrappedArrow
      return WaitingIterator(iterator: inner, timeBetweenChanges: arrow)
    }
  }

  // MARK: - Custom Codable

  private struct WaitingPayload: Codable {
    let iterator: IteratorSyntax
    let timeBetweenChanges: ArrowSyntax
  }

  init(from decoder: Decoder) throws {
    // Try bare string first: "cyclic", "shuffled", "random"
    if let container = try? decoder.singleValueContainer(),
       let str = try? container.decode(String.self) {
      switch str.lowercased() {
      case "cyclic":   self = .cyclic
      case "shuffled": self = .shuffled
      case "random":   self = .random
      default:         self = .cyclic
      }
      return
    }

    // Try keyed container for composed iterators: { "waiting": { ... } }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let payload = try container.decodeIfPresent(WaitingPayload.self, forKey: .waiting) {
      self = .waiting(iterator: payload.iterator, timeBetweenChanges: payload.timeBetweenChanges)
      return
    }

    self = .cyclic
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .cyclic:
      var container = encoder.singleValueContainer()
      try container.encode("cyclic")
    case .shuffled:
      var container = encoder.singleValueContainer()
      try container.encode("shuffled")
    case .random:
      var container = encoder.singleValueContainer()
      try container.encode("random")
    case .waiting(let inner, let arrow):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(WaitingPayload(iterator: inner, timeBetweenChanges: arrow), forKey: .waiting)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case waiting
  }
}

// MARK: - IteratedListSyntax

/// A list of candidate values paired with an emission strategy.
/// JSON: { "candidates": [...], "emission": <IteratorSyntax> }
/// The emission defaults to "cyclic" if omitted.
struct IteratedListSyntax<T: Codable>: Codable {
  let candidates: [T]
  let emission: IteratorSyntax?

  /// Compile into a live iterator, applying `transform` to resolve each candidate.
  func compile<U>(default defaultEmission: IteratorSyntax, transform: (T) -> U) -> any IteratorProtocol<U> {
    let resolved = candidates.map(transform)
    return (emission ?? defaultEmission).compile(resolved)
  }

  /// Compile directly when no transformation is needed (T == U).
  func compile(default defaultEmission: IteratorSyntax) -> any IteratorProtocol<T> {
    (emission ?? defaultEmission).compile(candidates)
  }
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

  /// Single-note melody from scale degrees with compositional iterator control.
  /// Each parameter is an `IteratedListSyntax` bundling candidates + emission strategy.
  /// The `ordering` field sets the default emission for any field that omits its own.
  case melodic(
    scales: IteratedListSyntax<String>,
    roots: IteratedListSyntax<String>,
    octaves: IteratedListSyntax<Int>,
    degrees: IteratedListSyntax<Int>,
    ordering: IteratorSyntax?
  )

  /// Notes from a MIDI file track. Timing (sustain/gap) is derived from the file.
  /// JSON: { "midiFile": { "filename": "BachInvention1.mid", "track": 0, "loop": true } }
  case midiFile(filename: String, track: Int?, loop: Bool?)

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

    case .melodic(let scales, let roots, let octaves, let degrees, let ordering):
      let defaultOrder: IteratorSyntax = ordering ?? .shuffled

      let scaleIter = scales.compile(default: defaultOrder, transform: Self.resolveScale)
      let rootIter = roots.compile(default: defaultOrder, transform: Self.resolveNoteClass)
      let octaveIter = octaves.compile(default: defaultOrder)
      let degreeIter = degrees.compile(default: defaultOrder)

      return MidiPitchAsChordGenerator(
        pitchGenerator: MidiPitchGenerator(
          scaleGenerator: scaleIter,
          degreeGenerator: degreeIter,
          rootNoteGenerator: rootIter,
          octaveGenerator: octaveIter
        )
      )

    case .midiFile(let filename, let track, let loop):
      let seq = Self.parseMidiFile(filename: filename, track: track, loop: loop ?? true)
      return seq?.makeIterators(loop: loop ?? true).notes ?? [[MidiNote]]().makeIterator()
    }
  }

  /// For MIDI files, compile all three iterators (notes + timing) from the file.
  /// Returns nil for non-MIDI generators.
  func compileMidiSequence() -> MidiEventSequence? {
    guard case .midiFile(let filename, let track, let loop) = self else { return nil }
    return Self.parseMidiFile(filename: filename, track: track, loop: loop ?? true)
  }

  private static func parseMidiFile(filename: String, track: Int?, loop: Bool) -> MidiEventSequence? {
    let name = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
      print("MidiFile not found in bundle: \(filename)")
      return nil
    }
    return MidiEventSequence.from(url: url, trackIndex: track, loop: loop)
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


}

// MARK: - PatternSyntax

/// Top-level Codable specification for a generative music pattern.
/// Parallels PresetSyntax: decode from JSON, then compile() to get a runtime MusicPattern.
struct PatternSyntax: Codable {
  let name: String
  let presetFilename: String
  let numVoices: Int?
  let noteGenerator: NoteGeneratorSyntax
  let sustain: TimingSyntax?
  let gap: TimingSyntax?
  let modulators: [ModulatorSyntax]?

  /// Compile into a MusicPattern using an already-constructed SpatialPreset.
  /// The caller is responsible for resolving the presetFilename and creating
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

    // For MIDI files, timing comes from the file itself
    if let midiSeq = noteGenerator.compileMidiSequence() {
      let loop: Bool
      if case .midiFile(_, _, let l) = noteGenerator { loop = l ?? true } else { loop = true }
      let iters = midiSeq.makeIterators(loop: loop)
      return MusicPattern(
        spatialPreset: spatialPreset,
        modulators: modulatorDict,
        notes: iters.notes,
        sustains: iters.sustains,
        gaps: iters.gaps,
        clock: clock
      )
    }

    // For generative patterns, use the sustain/gap fields (default to 1s fixed if missing)
    let sustainIter = (sustain ?? .fixed(value: 1.0)).compile()
    let gapIter = (gap ?? .fixed(value: 1.0)).compile()

    return MusicPattern(
      spatialPreset: spatialPreset,
      modulators: modulatorDict,
      notes: noteGenerator.compile(),
      sustains: sustainIter,
      gaps: gapIter,
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
