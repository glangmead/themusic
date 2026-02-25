//
//  TablePatternSyntax.swift
//  Orbital
//
//  Codable types for the table-based pattern definition system.
//  Four interconnected tables: Emitters, Note Material, Modulators, Track Assembly.
//

import Foundation

// MARK: - Emitter Output Type

/// The semantic output type of an emitter. Determines what it can be wired to.
enum EmitterOutputType: String, Codable, CaseIterable, Equatable {
  case float
  case int
  case root
  case octave
  case scale
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

  // Markov chord progression (Tymoczko baroque/classical major)
  case markovChord

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
      case "markovChord":          self = .markovChord
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
    case .sum:
      var c = encoder.singleValueContainer(); try c.encode("sum")
    case .reciprocal:
      var c = encoder.singleValueContainer(); try c.encode("reciprocal")
    case .markovChord:
      var c = encoder.singleValueContainer(); try c.encode("markovChord")
    case .fragmentPool:
      var c = encoder.singleValueContainer(); try c.encode("fragmentPool")
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

// MARK: - Table 2: Note Material Row

/// A row in the Note Material table. Matches emitters with interval lists
/// to emit notes via music-theoretic data.
struct NoteMaterialRowSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  /// Each entry is a list of scale degrees. Single-element = melody note,
  /// multi-element = chord (e.g. [[0], [1], [0,2,4], [1,3,5]]).
  var intervalMaterial: [[Int]]
  /// Name of an int-output emitter that picks which interval entry to use.
  var intervalPicker: String
  /// Name of an octave-output emitter.
  var octaveEmitter: String
  /// Name of a scale-output emitter.
  var scaleEmitter: String
  /// Name of a root-output emitter.
  var scaleRootEmitter: String

  init(
    id: UUID = UUID(),
    name: String,
    intervalMaterial: [[Int]],
    intervalPicker: String,
    octaveEmitter: String,
    scaleEmitter: String,
    scaleRootEmitter: String
  ) {
    self.id = id
    self.name = name
    self.intervalMaterial = intervalMaterial
    self.intervalPicker = intervalPicker
    self.octaveEmitter = octaveEmitter
    self.scaleEmitter = scaleEmitter
    self.scaleRootEmitter = scaleRootEmitter
  }

  enum CodingKeys: String, CodingKey {
    case id, name, intervalMaterial, intervalPicker, octaveEmitter, scaleEmitter, scaleRootEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    intervalMaterial = try c.decode([[Int]].self, forKey: .intervalMaterial)
    intervalPicker = try c.decode(String.self, forKey: .intervalPicker)
    octaveEmitter = try c.decode(String.self, forKey: .octaveEmitter)
    scaleEmitter = try c.decode(String.self, forKey: .scaleEmitter)
    scaleRootEmitter = try c.decode(String.self, forKey: .scaleRootEmitter)
  }
}

// MARK: - Table 3: Modulator Row

/// A row in the Modulators table. Wires a float emitter or an ArrowSyntax formula to a target handle.
struct ModulatorRowSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  /// The target parameter handle (e.g. "overallAmp", or "♦️.max" for meta-modulation).
  var targetHandle: String
  /// Name of a float-output emitter that drives this modulator (simple path).
  var floatEmitter: String?
  /// An ArrowSyntax formula for computing the modulation value (arrow path).
  /// Can reference emitter values via `.emitterValue(name:)`.
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
  /// Names from ModulatorRowSyntax.
  var modulatorNames: [String]
  /// Name from NoteMaterialRowSyntax.
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
    modulatorNames: [String] = [],
    noteMaterial: String,
    sustainEmitter: String,
    gapEmitter: String
  ) {
    self.id = id
    self.name = name
    self.presetFilename = presetFilename
    self.numVoices = numVoices
    self.modulatorNames = modulatorNames
    self.noteMaterial = noteMaterial
    self.sustainEmitter = sustainEmitter
    self.gapEmitter = gapEmitter
  }

  enum CodingKeys: String, CodingKey {
    case id, name, presetFilename, numVoices, modulatorNames, noteMaterial
    case sustainEmitter, gapEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    presetFilename = try c.decode(String.self, forKey: .presetFilename)
    numVoices = try c.decodeIfPresent(Int.self, forKey: .numVoices)
    modulatorNames = try c.decodeIfPresent([String].self, forKey: .modulatorNames) ?? []
    noteMaterial = try c.decode(String.self, forKey: .noteMaterial)
    sustainEmitter = try c.decode(String.self, forKey: .sustainEmitter)
    gapEmitter = try c.decode(String.self, forKey: .gapEmitter)
  }
}

// MARK: - Top-Level Container

/// Top-level container for the table-based pattern definition.
/// Contains all four tables that together define a generative music pattern.
struct TablePatternSyntax: Codable, Equatable {
  var name: String
  var emitters: [EmitterRowSyntax]
  var noteMaterials: [NoteMaterialRowSyntax]
  var modulators: [ModulatorRowSyntax]
  var tracks: [TrackAssemblyRowSyntax]
}
