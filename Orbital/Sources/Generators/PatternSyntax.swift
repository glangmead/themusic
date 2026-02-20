//
//  PatternSyntax.swift
//  Orbital
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

  /// Resolve a MIDI filename to a bundle URL.
  static func midiFileURL(filename: String) -> URL? {
    let name = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
      print("MidiFile not found in bundle: \(filename)")
      return nil
    }
    return url
  }

  private static func parseMidiFile(filename: String, track: Int?, loop: Bool) -> MidiEventSequence? {
    guard let url = midiFileURL(filename: filename) else { return nil }
    return MidiEventSequence.from(url: url, trackIndex: track, loop: loop)
  }

  // MARK: - Name Resolution

  /// All Tonic scales with display names, ordered for UI pickers.
  static let allScales: [(name: String, scale: Scale)] = [
    // Common modes
    ("Major", .major),
    ("Minor", .minor),
    ("Natural Minor", .naturalMinor),
    ("Harmonic Minor", .harmonicMinor),
    ("Melodic Minor", .melodicMinor),
    // Church modes
    ("Ionian", .ionian),
    ("Dorian", .dorian),
    ("Phrygian", .phrygian),
    ("Lydian", .lydian),
    ("Mixolydian", .mixolydian),
    ("Aeolian", .aeolian),
    ("Locrian", .locrian),
    // Pentatonic & Blues
    ("Pentatonic Major", .pentatonicMajor),
    ("Pentatonic Minor", .pentatonicMinor),
    ("Pentatonic Neutral", .pentatonicNeutral),
    ("Blues", .blues),
    ("Major Blues Hexatonic", .majorBluesHexatonic),
    ("Minor Blues Hexatonic", .minorBluesHexatonic),
    // Bebop
    ("Major Bebop", .majorBebop),
    ("Minor Bebop", .minorBebop),
    ("Bebop Dominant", .bebopDominant),
    // Jazz
    ("Jazz Melodic Minor", .jazzMelodicMinor),
    ("Altered", .altered),
    ("Dominant 7th", .dominant7th),
    // Diminished & Augmented
    ("Half Diminished", .halfDiminished),
    ("Whole Diminished", .wholeDiminished),
    ("Diminished Whole Tone", .diminishedWholeTone),
    ("Augmented", .augmented),
    ("Auxiliary Diminished", .auxiliaryDiminished),
    ("Auxiliary Augmented", .auxiliaryAugmented),
    ("Auxiliary Diminished Blues", .auxiliaryDimBlues),
    // Whole & Chromatic
    ("Whole", .whole),
    ("Chromatic", .chromatic),
    ("Diatonic", .diatonic),
    // Extended modes
    ("Dorian \u{266F}4", .dorianSharp4),
    ("Dorian \u{266D}2", .dorianFlat2),
    ("Dorian \u{266D}5", .dorianFlat5),
    ("Phrygian Dominant", .phrygianDominant),
    ("Phrygian \u{266D}4", .phrygianFlat4),
    ("Lydian Minor", .lydianMinor),
    ("Lydian Diminished", .lydianDiminished),
    ("Lydian \u{266F}2", .lydianSharp2),
    ("Lydian \u{266F}6", .lydianSharp6),
    ("Lydian \u{266F}2 \u{266F}6", .lydianSharp2Sharp6),
    ("Lydian \u{266D}3", .lydianFlat3),
    ("Lydian \u{266D}6", .lydianFlat6),
    ("Lydian \u{266D}7", .lydianFlat7),
    ("Lydian Augmented", .lydianAugmented),
    ("Lydian Augmented \u{266F}2", .lydianAugmentedSharp2),
    ("Lydian Augmented \u{266F}6", .lydianAugmentedSharp6),
    ("Mixolydian \u{266D}2", .mixolydianFlat2),
    ("Mixolydian \u{266D}6", .mixolydianFlat6),
    ("Mixolydian Augmented", .mixolydianAugmented),
    ("Locrian 2", .locrian2),
    ("Locrian 3", .locrian3),
    ("Locrian 6", .locrian6),
    ("Major Locrian", .majorLocrian),
    ("Locrian Diminished", .locrianDiminished),
    ("Locrian Diminished \u{266D}\u{266D}3", .locrianDiminishedFlatFlat3),
    ("Super Locrian", .superLocrian),
    ("Super Locrian Diminished \u{266D}\u{266D}3", .superLocrianDiminshedFlatFlat3),
    ("Ionian \u{266F}2", .ionianSharp2),
    ("Ionian Augmented", .ionianAugmented),
    ("Ionian Augmented \u{266F}2", .ionianAugmentedSharp2),
    ("Ultraphrygian", .ultraphrygian),
    // World scales
    ("Spanish Gypsy", .spanishGypsy),
    ("Gypsy", .gypsy),
    ("Flamenco", .flamenco),
    ("Romanian Minor", .romanianMinor),
    ("Hungarian Major", .hungarianMajor),
    ("Hungarian Minor", .hungarianMinor),
    ("Double Harmonic", .doubleHarmonic),
    ("Byzantine", .byzantine),
    ("Arabian", .arabian),
    ("Persian", .persian),
    ("Maqam", .maqam),
    ("Algerian", .algerian),
    ("Balinese", .balinese),
    ("Chinese", .chinese),
    ("Hirajoshi", .hirajoshi),
    ("Kumoi", .kumoi),
    ("Yo", .yo),
    ("Iwato", .iwato),
    ("Insen", .insen),
    ("Mongolian", .mongolian),
    ("Hindu", .hindu),
    ("Mohammedan", .mohammedan),
    ("Oriental", .oriental),
    ("Hawaiian", .hawaiian),
    ("Pelog", .pelog),
    // Other
    ("Eight Tone Spanish", .eightToneSpanish),
    ("Enigmatic", .enigmatic),
    ("Leading Whole Tone", .leadingWholeTone),
    ("Neopolitan", .neopolitan),
    ("Neopolitan Major", .neopolitanMajor),
    ("Neopolitan Minor", .neopolitanMinor),
    ("Nine Tone", .nineTone),
    ("Overtone", .overtone),
    ("Prometheus", .prometheus),
    ("Prometheus Neopolitan", .prometheusNeopolitan),
    ("Purvi Theta", .purviTheta),
    ("Todi Theta", .todiTheta),
    ("Six Tone Symmetrical", .sixToneSymmetrical),
    ("Tritone", .tritone),
    ("Istrian", .istrian),
    ("Pfluke", .pfluke),
    ("Ukrainian Dorian", .ukrainianDorian),
    ("Man Gong", .manGong),
    ("Ritsusen", .ritsusen),
  ]

  /// Lookup table built from `allScales`. Maps lowercased names (with and without spaces) to Scale.
  private static let scaleTable: [String: Scale] = {
    var table: [String: Scale] = [:]
    for (name, scale) in allScales {
      let lower = name.lowercased()
      table[lower] = scale
      // Also add the no-spaces form for backward compat with JSON like "harmonicminor"
      let noSpaces = lower.replacingOccurrences(of: " ", with: "")
      table[noSpaces] = scale
    }
    // Extra aliases
    table["minor"] = .minor
    table["aeolian"] = .aeolian
    return table
  }()

  static func resolveScale(_ name: String) -> Scale {
    scaleTable[name.lowercased()] ?? .major
  }

  /// All Tonic note classes with display names, ordered chromatically for UI pickers.
  static let allNoteClasses: [(name: String, noteClass: NoteClass)] = [
    ("C", .C),
    ("C\u{266F} / D\u{266D}", .Cs),
    ("D", .D),
    ("D\u{266F} / E\u{266D}", .Ds),
    ("E", .E),
    ("F", .F),
    ("F\u{266F} / G\u{266D}", .Fs),
    ("G", .G),
    ("G\u{266F} / A\u{266D}", .Gs),
    ("A", .A),
    ("A\u{266F} / B\u{266D}", .As),
    ("B", .B),
  ]

  /// Lookup table for note class resolution from JSON strings.
  private static let noteClassTable: [String: NoteClass] = [
    "c": .C, "cb": .Cb, "cs": .Cs, "c#": .Cs,
    "d": .D, "db": .Db, "ds": .Ds, "d#": .Ds,
    "e": .E, "eb": .Eb, "es": .Es, "e#": .Es,
    "f": .F, "fb": .Fb, "fs": .Fs, "f#": .Fs,
    "g": .G, "gb": .Gb, "gs": .Gs, "g#": .Gs,
    "a": .A, "ab": .Ab, "as": .As, "a#": .As,
    "b": .B, "bb": .Bb, "bs": .Bs, "b#": .Bs,
  ]

  static func resolveNoteClass(_ name: String) -> NoteClass {
    noteClassTable[name.lowercased()] ?? .C
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
  /// Optional per-track preset overrides for multi-track MIDI files.
  /// Track N uses trackPresetFilenames[N] if available, otherwise presetFilename.
  let trackPresetFilenames: [String]?

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

  /// For MIDI files with no track specified, compile ALL nonempty tracks into separate
  /// MusicPatterns, each with its own SpatialPreset. Returns an array of (pattern, spatialPreset, trackName).
  /// Returns nil if this isn't a multi-track MIDI pattern (i.e. noteGenerator is not .midiFile or has a specific track).
  func compileMultiTrack(presetSpec: PresetSyntax, engine: SpatialAudioEngine, clock: any Clock<Duration> = ContinuousClock()) -> [(pattern: MusicPattern, spatialPreset: SpatialPreset, trackName: String)]? {
    guard case .midiFile(let filename, let track, let loop) = noteGenerator else { return nil }
    // Only expand when track is nil (no specific track requested)
    guard track == nil else { return nil }
    guard let url = NoteGeneratorSyntax.midiFileURL(filename: filename) else { return nil }

    let loopVal = loop ?? true
    let allSeqs = MidiEventSequence.allTracks(url: url, loop: loopVal)
    guard allSeqs.count > 0 else { return nil }

    let modulatorDict: [String: Arrow11]
    if let mods = modulators {
      modulatorDict = Dictionary(mods.map { $0.compile() }, uniquingKeysWith: { first, _ in first })
    } else {
      modulatorDict = [:]
    }

    let voices = numVoices ?? 12

    return allSeqs.enumerated().map { (i, entry) in
      // Use per-track preset if specified, otherwise the shared one
      let trackPresetSpec: PresetSyntax
      if let trackPresets = trackPresetFilenames, i < trackPresets.count {
        let trackPresetFileName = trackPresets[i] + ".json"
        trackPresetSpec = Bundle.main.decode(PresetSyntax.self, from: trackPresetFileName, subdirectory: "presets")
      } else {
        trackPresetSpec = presetSpec
      }
      let sp = SpatialPreset(presetSpec: trackPresetSpec, engine: engine, numVoices: voices)
      let iters = entry.sequence.makeIterators(loop: loopVal)
      let pattern = MusicPattern(
        spatialPreset: sp,
        modulators: modulatorDict,
        notes: iters.notes,
        sustains: iters.sustains,
        gaps: iters.gaps,
        clock: clock
      )
      let name = entry.trackName.isEmpty ? "Track \(entry.trackIndex)" : entry.trackName
      return (pattern: pattern, spatialPreset: sp, trackName: name)
    }
  }
}
// MARK: - GeneratorType

/// Enum for the type-switching picker in the pattern editor UI.
enum GeneratorType: String, CaseIterable, Identifiable {
  case melodic = "Melodic"
  case scaleSampler = "Scale Sampler"
  case chordProgression = "Chord Progression"
  case fixed = "Fixed"
  case midiFile = "MIDI File"
  var id: String { rawValue }
}

extension NoteGeneratorSyntax {
  /// The generator type of this instance.
  var generatorType: GeneratorType {
    switch self {
    case .melodic:          return .melodic
    case .scaleSampler:     return .scaleSampler
    case .chordProgression: return .chordProgression
    case .fixed:            return .fixed
    case .midiFile:         return .midiFile
    }
  }

  /// Create a default instance for the given generator type.
  static func defaultGenerator(for type: GeneratorType) -> NoteGeneratorSyntax {
    switch type {
    case .melodic:
      return .melodic(
        scales: IteratedListSyntax(candidates: ["Major"], emission: .cyclic),
        roots: IteratedListSyntax(candidates: ["C"], emission: .cyclic),
        octaves: IteratedListSyntax(candidates: [4], emission: .cyclic),
        degrees: IteratedListSyntax(candidates: [1, 3, 5], emission: .cyclic),
        ordering: .cyclic
      )
    case .scaleSampler:
      return .scaleSampler(scale: "Major", root: "C", octaves: [3, 4, 5])
    case .chordProgression:
      return .chordProgression(scale: "Major", root: "C", style: "baroque")
    case .fixed:
      return .fixed(events: [ChordSyntax(notes: [NoteSyntax(midi: 60, velocity: 100)])])
    case .midiFile:
      return .midiFile(filename: "", track: nil, loop: true)
    }
  }
}

// MARK: - PatternFile

/// Decodes a pattern JSON file that is either a single PatternSyntax object
/// or an array of PatternSyntax objects (multi-track generative patterns).
enum PatternFile: Decodable {
  case single(PatternSyntax)
  case multi([PatternSyntax])

  var patterns: [PatternSyntax] {
    switch self {
    case .single(let p): return [p]
    case .multi(let ps): return ps
    }
  }

  init(from decoder: Decoder) throws {
    if let array = try? [PatternSyntax](from: decoder) {
      self = .multi(array)
    } else {
      self = .single(try PatternSyntax(from: decoder))
    }
  }
}

// MARK: - NoteGeneratorSyntax Display Helpers

extension NoteGeneratorSyntax {
  /// Human-readable type name for display in the pattern list.
  var displayTypeName: String {
    switch self {
    case .fixed:            return "Fixed"
    case .scaleSampler:     return "Scale Sampler"
    case .chordProgression: return "Chord Progression"
    case .melodic:          return "Melodic"
    case .midiFile:         return "MIDI File"
    }
  }

  /// Short summary of the key musical parameters.
  var displaySummary: String {
    switch self {
    case .fixed(let events):
      return "\(events.count) chord\(events.count == 1 ? "" : "s")"
    case .scaleSampler(let scale, let root, _):
      return "\(root) \(scale)"
    case .chordProgression(let scale, let root, let style):
      return "\(root) \(scale)" + (style.map { " (\($0))" } ?? "")
    case .melodic(let scales, let roots, _, _, _):
      let scaleStr = scales.candidates.first ?? "?"
      let rootStr = roots.candidates.first ?? "?"
      return "\(rootStr) \(scaleStr)" + (scales.candidates.count > 1 ? " +\(scales.candidates.count - 1)" : "")
    case .midiFile(let filename, _, _):
      return (filename as NSString).lastPathComponent
    }
  }
}

