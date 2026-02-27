//
//  TablePatternSyntax.swift
//  Orbital
//
//  Codable types for the table-based pattern definition system.
//  Four interconnected tables: Emitters, Note Material, Modulators, Track Assembly.
//  Plus an optional shared PitchHierarchy with its own modulators.
//

import Foundation

// MARK: - Emitter Output Type

/// The semantic output type of an emitter. Determines what it can be wired to.
enum EmitterOutputType: String, Codable, CaseIterable, Equatable {
  case float
  case int
  case octave
}

// MARK: - Emitter Function

/// The generation strategy for an emitter.
enum EmitterFunction: Codable, Equatable, Hashable {
  // Stateless generators (safe with any update mode)
  case randFloat
  case exponentialRandFloat
  case randInt

  // Stateful list-based generators (spoiled by waiting update mode)
  case shuffle
  case cyclic
  case random

  // Fragment pool: pick a random fragment, yield its values sequentially, repeat
  case fragmentPool

  // Composition operators
  case sum
  case reciprocal
  case indexPicker(emitter: String)

  // MARK: - Custom Codable

  private enum CodingKeys: String, CodingKey {
    case indexPicker
  }

  private struct IndexPickerPayload: Codable, Equatable {
    let emitter: String
  }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
       let str = try? container.decode(String.self) {
      switch str {
      case "randFloat":            self = .randFloat
      case "exponentialRandFloat": self = .exponentialRandFloat
      case "randInt":              self = .randInt
      case "shuffle":              self = .shuffle
      case "cyclic":               self = .cyclic
      case "random":               self = .random
      case "fragmentPool":         self = .fragmentPool
      case "sum":                  self = .sum
      case "reciprocal":           self = .reciprocal
      default:                     self = .randFloat
      }
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let payload = try container.decodeIfPresent(IndexPickerPayload.self, forKey: .indexPicker) {
      self = .indexPicker(emitter: payload.emitter)
      return
    }

    self = .randFloat
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .randFloat:
      var c = encoder.singleValueContainer(); try c.encode("randFloat")
    case .exponentialRandFloat:
      var c = encoder.singleValueContainer(); try c.encode("exponentialRandFloat")
    case .randInt:
      var c = encoder.singleValueContainer(); try c.encode("randInt")
    case .shuffle:
      var c = encoder.singleValueContainer(); try c.encode("shuffle")
    case .cyclic:
      var c = encoder.singleValueContainer(); try c.encode("cyclic")
    case .random:
      var c = encoder.singleValueContainer(); try c.encode("random")
    case .fragmentPool:
      var c = encoder.singleValueContainer(); try c.encode("fragmentPool")
    case .sum:
      var c = encoder.singleValueContainer(); try c.encode("sum")
    case .reciprocal:
      var c = encoder.singleValueContainer(); try c.encode("reciprocal")
    case .indexPicker(let emitter):
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(IndexPickerPayload(emitter: emitter), forKey: .indexPicker)
    }
  }
}

// MARK: - Emitter Update Mode

/// Controls when an emitter advances to a new value.
enum EmitterUpdateMode: Codable, Equatable, Hashable {
  /// Advance every call, with ~15ms latch for shared-instance deduplication.
  case each
  /// Advance when the referenced float emitter's time-gate fires.
  case waiting(emitter: String)

  // MARK: - Custom Codable

  private enum CodingKeys: String, CodingKey {
    case waiting
  }

  private struct WaitingPayload: Codable, Equatable {
    let emitter: String
  }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
       let str = try? container.decode(String.self),
       str == "each" {
      self = .each
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let payload = try container.decodeIfPresent(WaitingPayload.self, forKey: .waiting) {
      self = .waiting(emitter: payload.emitter)
      return
    }

    self = .each
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .each:
      var c = encoder.singleValueContainer(); try c.encode("each")
    case .waiting(let emitter):
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(WaitingPayload(emitter: emitter), forKey: .waiting)
    }
  }
}

// MARK: - Table 1: Emitter Row

/// A single row in the Emitters table. Named iterators that produce values via next().
struct EmitterRowSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var outputType: EmitterOutputType
  var function: EmitterFunction
  var arg1: Double?
  var arg2: Double?
  /// List of candidate values (strings resolved by outputType at compile time).
  var candidates: [String]?
  /// References to other emitters used as inputs (for sum, reciprocal).
  var inputEmitters: [String]?
  /// Fragment lists for the fragmentPool function. Each inner array is a melody fragment.
  var fragments: [[Int]]?
  var updateMode: EmitterUpdateMode

  init(
    id: UUID = UUID(),
    name: String,
    outputType: EmitterOutputType,
    function: EmitterFunction,
    arg1: Double? = nil,
    arg2: Double? = nil,
    candidates: [String]? = nil,
    inputEmitters: [String]? = nil,
    fragments: [[Int]]? = nil,
    updateMode: EmitterUpdateMode = .each
  ) {
    self.id = id
    self.name = name
    self.outputType = outputType
    self.function = function
    self.arg1 = arg1
    self.arg2 = arg2
    self.candidates = candidates
    self.inputEmitters = inputEmitters
    self.fragments = fragments
    self.updateMode = updateMode
  }

  // Default id from UUID() if absent in JSON
  enum CodingKeys: String, CodingKey {
    case id, name, outputType, function, arg1, arg2, candidates, inputEmitters, fragments, updateMode
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    outputType = try c.decode(EmitterOutputType.self, forKey: .outputType)
    function = try c.decode(EmitterFunction.self, forKey: .function)
    arg1 = try c.decodeIfPresent(Double.self, forKey: .arg1)
    arg2 = try c.decodeIfPresent(Double.self, forKey: .arg2)
    candidates = try c.decodeIfPresent([String].self, forKey: .candidates)
    inputEmitters = try c.decodeIfPresent([String].self, forKey: .inputEmitters)
    fragments = try c.decodeIfPresent([[Int]].self, forKey: .fragments)
    updateMode = try c.decodeIfPresent(EmitterUpdateMode.self, forKey: .updateMode) ?? .each
  }
}

// MARK: - Hierarchy

/// The initial state of the shared PitchHierarchy for this pattern.
struct HierarchySyntax: Codable, Equatable {
  var root: String    // NoteClass name, e.g. "C"
  var scale: String   // Scale name, e.g. "major"
  var chord: ChordInScaleSyntax
}

/// Initial chord expressed as scale degrees.
struct ChordInScaleSyntax: Codable, Equatable {
  var degrees: [Int]
  var inversion: Int
}

// MARK: - Hierarchy Modulator Row

/// A modulator that fires on a timer and applies a T/t/L operation to the shared hierarchy.
struct HierarchyModulatorRowSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  /// Level at which to apply the operation.
  var level: HierarchyLevel
  /// "T", "t", or "L"
  var operation: String
  /// Step count for the operation.
  var n: Int
  /// Name of a float emitter whose value determines the firing interval (seconds).
  var fireIntervalEmitter: String

  enum CodingKeys: String, CodingKey {
    case id, name, level, operation, n, fireIntervalEmitter
  }

  init(
    id: UUID = UUID(),
    name: String,
    level: HierarchyLevel,
    operation: String,
    n: Int,
    fireIntervalEmitter: String
  ) {
    self.id = id
    self.name = name
    self.level = level
    self.operation = operation
    self.n = n
    self.fireIntervalEmitter = fireIntervalEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    level = try c.decode(HierarchyLevel.self, forKey: .level)
    operation = try c.decode(String.self, forKey: .operation)
    n = try c.decode(Int.self, forKey: .n)
    fireIntervalEmitter = try c.decode(String.self, forKey: .fireIntervalEmitter)
  }
}

// MARK: - Table 2: Note Material (polymorphic)

/// A row in the Note Material table. Unified enum covering all note material strategies.
/// The JSON `type` field selects the case.
enum NoteMaterialSyntax: Codable, Equatable {

  /// Scale-degree–based melody/chord material. Degrees are resolved against a fixed
  /// root + scale (not the hierarchy chord layer).
  case scaleMaterial(ScaleMaterialSyntax)

  /// Chord-relative or scale-relative melody using MelodyNotes resolved via the hierarchy.
  case hierarchyMelody(HierarchyMelodySyntax)

  /// Voiced chord from all of the hierarchy's current chord degrees.
  case hierarchyChord(HierarchyChordSyntax)

  /// Single bass note — the hierarchy's inversion-determined lowest degree.
  case hierarchyBass(HierarchyBassSyntax)

  // MARK: Forwarded properties

  var name: String {
    switch self {
    case .scaleMaterial(let s):   return s.name
    case .hierarchyMelody(let s): return s.name
    case .hierarchyChord(let s):  return s.name
    case .hierarchyBass(let s):   return s.name
    }
  }

  var id: UUID {
    switch self {
    case .scaleMaterial(let s):   return s.id
    case .hierarchyMelody(let s): return s.id
    case .hierarchyChord(let s):  return s.id
    case .hierarchyBass(let s):   return s.id
    }
  }

  // MARK: Discriminated Codable

  private enum TypeKey: String, CodingKey { case type }

  private enum MaterialType: String, Codable {
    case scaleMaterial, hierarchyMelody, hierarchyChord, hierarchyBass
  }

  init(from decoder: Decoder) throws {
    let typeContainer = try decoder.container(keyedBy: TypeKey.self)
    let materialType = try typeContainer.decode(MaterialType.self, forKey: .type)
    switch materialType {
    case .scaleMaterial:
      self = .scaleMaterial(try ScaleMaterialSyntax(from: decoder))
    case .hierarchyMelody:
      self = .hierarchyMelody(try HierarchyMelodySyntax(from: decoder))
    case .hierarchyChord:
      self = .hierarchyChord(try HierarchyChordSyntax(from: decoder))
    case .hierarchyBass:
      self = .hierarchyBass(try HierarchyBassSyntax(from: decoder))
    }
  }

  func encode(to encoder: Encoder) throws {
    var typeContainer = encoder.container(keyedBy: TypeKey.self)
    switch self {
    case .scaleMaterial(let s):
      try typeContainer.encode(MaterialType.scaleMaterial, forKey: .type)
      try s.encode(to: encoder)
    case .hierarchyMelody(let s):
      try typeContainer.encode(MaterialType.hierarchyMelody, forKey: .type)
      try s.encode(to: encoder)
    case .hierarchyChord(let s):
      try typeContainer.encode(MaterialType.hierarchyChord, forKey: .type)
      try s.encode(to: encoder)
    case .hierarchyBass(let s):
      try typeContainer.encode(MaterialType.hierarchyBass, forKey: .type)
      try s.encode(to: encoder)
    }
  }
}

// MARK: - Scale Material

/// Note material that resolves scale degrees against a fixed root + scale.
/// If `intervals` is nil, the picker emitter emits scale degree values directly.
/// If `intervals` is present, the picker emitter emits an index into that array.
struct ScaleMaterialSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var root: String             // NoteClass name, e.g. "A"
  var scale: String            // Scale name, e.g. "chromatic"
  /// Each entry is a list of scale degrees (single = melody note, multi = chord).
  /// Absent means the picker emitter emits degree values directly.
  var intervals: [[Int]]?
  /// Name of an int-output emitter that either picks an index (when intervals present)
  /// or emits degree values directly (when intervals absent).
  var intervalPickerEmitter: String
  /// Name of an int/octave-output emitter for the base octave.
  var octaveEmitter: String

  enum CodingKeys: String, CodingKey {
    case id, name, root, scale, intervals, intervalPickerEmitter, octaveEmitter, type
  }

  init(
    id: UUID = UUID(),
    name: String,
    root: String,
    scale: String,
    intervals: [[Int]]? = nil,
    intervalPickerEmitter: String,
    octaveEmitter: String
  ) {
    self.id = id
    self.name = name
    self.root = root
    self.scale = scale
    self.intervals = intervals
    self.intervalPickerEmitter = intervalPickerEmitter
    self.octaveEmitter = octaveEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    root = try c.decode(String.self, forKey: .root)
    scale = try c.decode(String.self, forKey: .scale)
    intervals = try c.decodeIfPresent([[Int]].self, forKey: .intervals)
    intervalPickerEmitter = try c.decode(String.self, forKey: .intervalPickerEmitter)
    octaveEmitter = try c.decode(String.self, forKey: .octaveEmitter)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(root, forKey: .root)
    try c.encode(scale, forKey: .scale)
    try c.encodeIfPresent(intervals, forKey: .intervals)
    try c.encode(intervalPickerEmitter, forKey: .intervalPickerEmitter)
    try c.encode(octaveEmitter, forKey: .octaveEmitter)
  }
}

// MARK: - Hierarchy Melody

/// Note material that resolves MelodyNotes through the shared PitchHierarchy.
struct HierarchyMelodySyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  /// .chord: chordTone field indexes into voicedDegrees.
  /// .scale: degree field is used directly as a scale degree.
  var level: HierarchyLevel
  var notes: [HierarchyMelodyNoteSyntax]
  var ordering: String   // "cyclic", "shuffle", or "random"
  var octaveEmitter: String

  enum CodingKeys: String, CodingKey {
    case id, name, level, notes, ordering, octaveEmitter, type
  }

  init(
    id: UUID = UUID(),
    name: String,
    level: HierarchyLevel,
    notes: [HierarchyMelodyNoteSyntax],
    ordering: String = "cyclic",
    octaveEmitter: String
  ) {
    self.id = id
    self.name = name
    self.level = level
    self.notes = notes
    self.ordering = ordering
    self.octaveEmitter = octaveEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    level = try c.decode(HierarchyLevel.self, forKey: .level)
    notes = try c.decode([HierarchyMelodyNoteSyntax].self, forKey: .notes)
    ordering = try c.decodeIfPresent(String.self, forKey: .ordering) ?? "cyclic"
    octaveEmitter = try c.decode(String.self, forKey: .octaveEmitter)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(level, forKey: .level)
    try c.encode(notes, forKey: .notes)
    try c.encode(ordering, forKey: .ordering)
    try c.encode(octaveEmitter, forKey: .octaveEmitter)
  }
}

/// A single note spec within a HierarchyMelody.
struct HierarchyMelodyNoteSyntax: Codable, Equatable {
  /// Chord-tone index (used at .chord level). Index into voicedDegrees.
  var chordTone: Int?
  /// Scale degree (used at .scale level).
  var degree: Int?
  /// Optional perturbation relative to the resolved tone.
  var perturbation: PerturbationSyntax?

  /// Convert to a MelodyNote, using chordToneIndex for both chord and scale levels
  /// (at scale level, chordToneIndex IS the scale degree — resolve() handles the distinction).
  func toMelodyNote() -> MelodyNote? {
    let idx = chordTone ?? degree
    guard let idx else { return nil }
    let pert = perturbation?.toPerturbation() ?? .none
    return MelodyNote(chordToneIndex: idx, perturbation: pert)
  }
}

/// Optional perturbation applied after resolving a chord tone or scale degree.
struct PerturbationSyntax: Codable, Equatable {
  var scaleDegree: Int?
  var chromatic: Int?

  func toPerturbation() -> Perturbation {
    if let sd = scaleDegree { return .scaleDegree(sd) }
    if let ch = chromatic { return .chromatic(ch) }
    return .none
  }
}

// MARK: - Hierarchy Chord

/// Note material that emits the hierarchy's current chord as a voiced set of MIDI notes.
struct HierarchyChordSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var voicing: VoicingStyle
  var baseOctave: Int

  enum CodingKeys: String, CodingKey {
    case id, name, voicing, baseOctave, type
  }

  init(
    id: UUID = UUID(),
    name: String,
    voicing: VoicingStyle = .closed,
    baseOctave: Int = 4
  ) {
    self.id = id
    self.name = name
    self.voicing = voicing
    self.baseOctave = baseOctave
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    voicing = try c.decodeIfPresent(VoicingStyle.self, forKey: .voicing) ?? .closed
    baseOctave = try c.decodeIfPresent(Int.self, forKey: .baseOctave) ?? 4
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(voicing, forKey: .voicing)
    try c.encode(baseOctave, forKey: .baseOctave)
  }
}

// MARK: - Hierarchy Bass

/// Note material that emits a single bass note — the hierarchy's inversion-determined lowest degree.
struct HierarchyBassSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var baseOctave: Int

  enum CodingKeys: String, CodingKey {
    case id, name, baseOctave, type
  }

  init(id: UUID = UUID(), name: String, baseOctave: Int = 2) {
    self.id = id
    self.name = name
    self.baseOctave = baseOctave
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    baseOctave = try c.decodeIfPresent(Int.self, forKey: .baseOctave) ?? 2
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(baseOctave, forKey: .baseOctave)
  }
}

// MARK: - Table 3: Preset Modulator Row

/// A row in the Preset Modulators table. Wires a float emitter or ArrowSyntax formula
/// to a target synth handle on a specific track's preset.
struct PresetModulatorRowSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  /// The target parameter handle (e.g. "overallAmp", or "♦️.max" for meta-modulation).
  var targetHandle: String
  /// Name of a float-output emitter that drives this modulator (simple path).
  var floatEmitter: String?
  /// An ArrowSyntax formula for computing the modulation value (arrow path).
  var arrow: ArrowSyntax?

  init(
    id: UUID = UUID(),
    name: String,
    targetHandle: String,
    floatEmitter: String? = nil,
    arrow: ArrowSyntax? = nil
  ) {
    self.id = id
    self.name = name
    self.targetHandle = targetHandle
    self.floatEmitter = floatEmitter
    self.arrow = arrow
  }

  enum CodingKeys: String, CodingKey {
    case id, name, targetHandle, floatEmitter, arrow
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    targetHandle = try c.decode(String.self, forKey: .targetHandle)
    floatEmitter = try c.decodeIfPresent(String.self, forKey: .floatEmitter)
    arrow = try c.decodeIfPresent(ArrowSyntax.self, forKey: .arrow)
  }
}

// MARK: - Table 4: Track Assembly Row

/// A row in the Track Assembly table. Assembles emitters, note material,
/// and modulators into a playable track with a preset.
struct TrackAssemblyRowSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var presetFilename: String
  var numVoices: Int?
  /// Names from PresetModulatorRowSyntax.
  var presetModulatorNames: [String]
  /// Name from NoteMaterialSyntax.
  var noteMaterial: String
  /// Name of a float-output emitter for sustain duration.
  var sustainEmitter: String
  /// Name of a float-output emitter for gap duration.
  var gapEmitter: String

  init(
    id: UUID = UUID(),
    name: String,
    presetFilename: String,
    numVoices: Int? = nil,
    presetModulatorNames: [String] = [],
    noteMaterial: String,
    sustainEmitter: String,
    gapEmitter: String
  ) {
    self.id = id
    self.name = name
    self.presetFilename = presetFilename
    self.numVoices = numVoices
    self.presetModulatorNames = presetModulatorNames
    self.noteMaterial = noteMaterial
    self.sustainEmitter = sustainEmitter
    self.gapEmitter = gapEmitter
  }

  enum CodingKeys: String, CodingKey {
    case id, name, presetFilename, numVoices, presetModulatorNames
    case noteMaterial, sustainEmitter, gapEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    presetFilename = try c.decode(String.self, forKey: .presetFilename)
    numVoices = try c.decodeIfPresent(Int.self, forKey: .numVoices)
    presetModulatorNames = try c.decodeIfPresent([String].self, forKey: .presetModulatorNames) ?? []
    noteMaterial = try c.decode(String.self, forKey: .noteMaterial)
    sustainEmitter = try c.decode(String.self, forKey: .sustainEmitter)
    gapEmitter = try c.decode(String.self, forKey: .gapEmitter)
  }
}

// MARK: - Top-Level Container

/// Top-level container for the table-based pattern definition.
struct TablePatternSyntax: Codable, Equatable {
  var name: String
  /// Optional shared pitch hierarchy. Required for hierarchyMelody/hierarchyChord/hierarchyBass materials.
  var hierarchy: HierarchySyntax?
  var emitters: [EmitterRowSyntax]
  var noteMaterials: [NoteMaterialSyntax]
  /// Modulators that target synth parameter handles on specific tracks' presets.
  var presetModulators: [PresetModulatorRowSyntax]
  /// Modulators that fire on independent timers and mutate the shared hierarchy.
  var hierarchyModulators: [HierarchyModulatorRowSyntax]
  var tracks: [TrackAssemblyRowSyntax]

  init(
    name: String,
    hierarchy: HierarchySyntax? = nil,
    emitters: [EmitterRowSyntax] = [],
    noteMaterials: [NoteMaterialSyntax] = [],
    presetModulators: [PresetModulatorRowSyntax] = [],
    hierarchyModulators: [HierarchyModulatorRowSyntax] = [],
    tracks: [TrackAssemblyRowSyntax] = []
  ) {
    self.name = name
    self.hierarchy = hierarchy
    self.emitters = emitters
    self.noteMaterials = noteMaterials
    self.presetModulators = presetModulators
    self.hierarchyModulators = hierarchyModulators
    self.tracks = tracks
  }

  enum CodingKeys: String, CodingKey {
    case name, hierarchy, emitters, noteMaterials, presetModulators, hierarchyModulators, tracks
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    hierarchy = try c.decodeIfPresent(HierarchySyntax.self, forKey: .hierarchy)
    emitters = try c.decodeIfPresent([EmitterRowSyntax].self, forKey: .emitters) ?? []
    noteMaterials = try c.decodeIfPresent([NoteMaterialSyntax].self, forKey: .noteMaterials) ?? []
    presetModulators = try c.decodeIfPresent([PresetModulatorRowSyntax].self, forKey: .presetModulators) ?? []
    hierarchyModulators = try c.decodeIfPresent([HierarchyModulatorRowSyntax].self, forKey: .hierarchyModulators) ?? []
    tracks = try c.decodeIfPresent([TrackAssemblyRowSyntax].self, forKey: .tracks) ?? []
  }
}
