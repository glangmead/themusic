//
//  NoteGeneratorSyntax.swift
//  Orbital
//
//  Extracted from PatternSyntax.swift
//

import Foundation
import Tonic

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

  func compile(resourceBaseURL: URL? = nil) -> any IteratorProtocol<[MidiNote]> {
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
      let seq = Self.parseMidiFile(filename: filename, track: track, loop: loop ?? true, resourceBaseURL: resourceBaseURL)
      return seq?.makeIterators(loop: loop ?? true).notes ?? [[MidiNote]]().makeIterator()
    }
  }

  /// For MIDI files, compile all three iterators (notes + timing) from the file.
  /// Returns nil for non-MIDI generators.
  func compileMidiSequence(resourceBaseURL: URL? = nil) -> MidiEventSequence? {
    guard case .midiFile(let filename, let track, let loop) = self else { return nil }
    return Self.parseMidiFile(filename: filename, track: track, loop: loop ?? true, resourceBaseURL: resourceBaseURL)
  }

  /// Resolve a MIDI filename to a bundle URL, or to a file under `resourceBaseURL` if provided.
  static func midiFileURL(filename: String, resourceBaseURL: URL? = nil) -> URL? {
    if let base = resourceBaseURL {
      let url = base.appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: url.path) { return url }
      print("MidiFile not found at \(url.path)")
      return nil
    }
    let name = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
      print("MidiFile not found in bundle: \(filename)")
      return nil
    }
    return url
  }

  private static func parseMidiFile(filename: String, track: Int?, loop: Bool, resourceBaseURL: URL? = nil) -> MidiEventSequence? {
    guard let url = midiFileURL(filename: filename, resourceBaseURL: resourceBaseURL) else { return nil }
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



