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

// MARK: - ProceduralTrackSyntax

/// A single procedural track within a pattern.
struct ProceduralTrackSyntax: Codable {
  let name: String
  let presetFilename: String
  let numVoices: Int?
  let noteGenerator: NoteGeneratorSyntax
  let sustain: TimingSyntax?
  let gap: TimingSyntax?
  let modulators: [ModulatorSyntax]?
}

// MARK: - MidiTracksSyntax

/// Per-track configuration for a MIDI pattern (preset + voice count).
struct MidiTrackEntry: Codable {
  let presetFilename: String
  let numVoices: Int?
  let modulators: [ModulatorSyntax]?
}

/// Multi-track MIDI specification. A single MIDI file that auto-expands
/// into one track per nonempty MIDI track at compile time.
struct MidiTracksSyntax: Codable {
  let filename: String
  let loop: Bool?
  let tracks: [MidiTrackEntry]
}

// MARK: - PatternSyntax

/// Top-level Codable specification for a generative music pattern.
/// A pattern has a name and either `proceduralTracks` (generative) or
/// `midiTracks` (MIDI file). Exactly one must be present.
struct PatternSyntax: Codable {
  let name: String
  let proceduralTracks: [ProceduralTrackSyntax]?
  let midiTracks: MidiTracksSyntax?
  let tableTracks: TablePatternSyntax?

  /// Compile all tracks into a single MusicPattern. Returns the pattern
  /// plus a TrackInfo array for the UI (built at compile time so
  /// SongPlaybackState can access it without awaiting the actor).
  func compile(engine: SpatialAudioEngine, clock: any Clock<Duration> = ContinuousClock()) async throws -> (MusicPattern, [TrackInfo]) {
    if let procedural = proceduralTracks {
      return try await compileProceduralTracks(procedural, engine: engine, clock: clock)
    } else if let midi = midiTracks {
      return try await compileMidiTracks(midi, engine: engine, clock: clock)
    } else if let table = tableTracks {
      return try await TablePatternCompiler.compile(table, engine: engine, clock: clock)
    } else {
      fatalError("PatternSyntax '\(name)' has no tracks")
    }
  }

  /// Compile without an engine — produces TrackInfo for UI-only display.
  func compileTrackInfoOnly() -> [TrackInfo] {
    var infos: [TrackInfo] = []
    var nextId = 0
    if let procedural = proceduralTracks {
      for track in procedural {
        let presetFileName = track.presetFilename + ".json"
        let presetSpec = Bundle.main.decode(PresetSyntax.self, from: presetFileName, subdirectory: "presets")
        let sp = SpatialPreset(presetSpec: presetSpec, numVoices: track.numVoices ?? 12)
        infos.append(TrackInfo(
          id: nextId,
          patternName: track.name,
          trackSpec: track,
          presetSpec: presetSpec,
          spatialPreset: sp
        ))
        nextId += 1
      }
    } else if let midi = midiTracks {
      for (i, entry) in midi.tracks.enumerated() {
        let presetFileName = entry.presetFilename + ".json"
        let presetSpec = Bundle.main.decode(PresetSyntax.self, from: presetFileName, subdirectory: "presets")
        let sp = SpatialPreset(presetSpec: presetSpec, numVoices: entry.numVoices ?? 12)
        infos.append(TrackInfo(
          id: nextId,
          patternName: "Track \(i)",
          trackSpec: nil,
          presetSpec: presetSpec,
          spatialPreset: sp
        ))
        nextId += 1
      }
    } else if let table = tableTracks {
      return TablePatternCompiler.compileTrackInfoOnly(table)
    }
    return infos
  }

  // MARK: - Private compilation helpers

  private func compileProceduralTracks(
    _ procedural: [ProceduralTrackSyntax],
    engine: SpatialAudioEngine,
    clock: any Clock<Duration>
  ) async throws -> (MusicPattern, [TrackInfo]) {
    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []

    for (i, trackSpec) in procedural.enumerated() {
      let presetFileName = trackSpec.presetFilename + ".json"
      let presetSpec = Bundle.main.decode(PresetSyntax.self, from: presetFileName, subdirectory: "presets")
      let voices = trackSpec.numVoices ?? 12
      let sp = try await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: voices)

      let modulatorDict = Self.compileModulators(trackSpec.modulators)

      let noteGen = trackSpec.noteGenerator
      let notes: any IteratorProtocol<[MidiNote]>
      let sustains: any IteratorProtocol<CoreFloat>
      let gaps: any IteratorProtocol<CoreFloat>

      if let midiSeq = noteGen.compileMidiSequence() {
        let loop: Bool
        if case .midiFile(_, _, let l) = noteGen { loop = l ?? true } else { loop = true }
        let iters = midiSeq.makeIterators(loop: loop)
        notes = iters.notes
        sustains = iters.sustains
        gaps = iters.gaps
      } else {
        notes = noteGen.compile()
        sustains = (trackSpec.sustain ?? .fixed(value: 1.0)).compile()
        gaps = (trackSpec.gap ?? .fixed(value: 1.0)).compile()
      }

      musicTracks.append(MusicPattern.Track(
        spatialPreset: sp,
        modulators: modulatorDict,
        notes: notes,
        sustains: sustains,
        gaps: gaps,
        name: trackSpec.name
      ))

      trackInfos.append(TrackInfo(
        id: i,
        patternName: trackSpec.name,
        trackSpec: trackSpec,
        presetSpec: presetSpec,
        spatialPreset: sp
      ))
    }

    let pattern = MusicPattern(tracks: musicTracks, clock: clock)
    return (pattern, trackInfos)
  }

  private func compileMidiTracks(
    _ midi: MidiTracksSyntax,
    engine: SpatialAudioEngine,
    clock: any Clock<Duration>
  ) async throws -> (MusicPattern, [TrackInfo]) {
    guard let url = NoteGeneratorSyntax.midiFileURL(filename: midi.filename) else {
      fatalError("MIDI file not found: \(midi.filename)")
    }

    let loopVal = midi.loop ?? true
    let allSeqs = MidiEventSequence.allTracks(url: url, loop: loopVal)

    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []

    for (i, entry) in allSeqs.enumerated() {
      // Use per-track entry if available, otherwise fall back to first entry
      let trackEntry = i < midi.tracks.count ? midi.tracks[i] : midi.tracks[0]
      let presetFileName = trackEntry.presetFilename + ".json"
      let presetSpec = Bundle.main.decode(PresetSyntax.self, from: presetFileName, subdirectory: "presets")
      let voices = trackEntry.numVoices ?? 12
      let sp = try await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: voices)

      let modulatorDict = Self.compileModulators(trackEntry.modulators)
      let iters = entry.sequence.makeIterators(loop: loopVal)
      let trackName = entry.trackName.isEmpty ? "Track \(entry.trackIndex)" : entry.trackName

      musicTracks.append(MusicPattern.Track(
        spatialPreset: sp,
        modulators: modulatorDict,
        notes: iters.notes,
        sustains: iters.sustains,
        gaps: iters.gaps,
        name: trackName
      ))

      trackInfos.append(TrackInfo(
        id: i,
        patternName: trackName,
        trackSpec: nil,
        presetSpec: presetSpec,
        spatialPreset: sp
      ))
    }

    let pattern = MusicPattern(tracks: musicTracks, clock: clock)
    return (pattern, trackInfos)
  }

  private static func compileModulators(_ modulators: [ModulatorSyntax]?) -> [String: Arrow11] {
    guard let mods = modulators else { return [:] }
    return Dictionary(
      mods.map { $0.compile() },
      uniquingKeysWith: { first, _ in first }
    )
  }
}

