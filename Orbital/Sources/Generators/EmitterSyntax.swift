//
//  EmitterSyntax.swift
//  Orbital
//
//  Codable types for the Emitters table: EmitterOutputType, EmitterFunction,
//  EmitterUpdateMode, and EmitterRowSyntax. Extracted from TablePatternSyntax.swift.
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
