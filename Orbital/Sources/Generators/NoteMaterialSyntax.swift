//
//  NoteMaterialSyntax.swift
//  Orbital
//
//  Codable types for the Note Material table: NoteMaterialSyntax (discriminated enum),
//  HierarchyMelodySyntax, and HierarchyChordSyntax. Extracted from TablePatternSyntax.swift.
//

import Foundation

// MARK: - Table 2: Note Material (polymorphic)

/// A row in the Note Material table. Unified enum covering all note material strategies.
/// The JSON `type` field selects the case.
/// All note materials require the pattern-level `hierarchy` to be defined.
enum NoteMaterialSyntax: Codable, Equatable {

  /// Single-note melody resolved through the shared PitchHierarchy.
  /// At .scale level, degreeEmitter emits scale degree values directly.
  /// At .chord level, degreeEmitter emits chord-tone indices into voicedDegrees.
  case hierarchyMelody(HierarchyMelodySyntax)

  /// Voiced chord from all of the hierarchy's current chord degrees.
  case hierarchyChord(HierarchyChordSyntax)

  // MARK: Forwarded properties

  var name: String {
    switch self {
    case .hierarchyMelody(let s): return s.name
    case .hierarchyChord(let s):  return s.name
    }
  }

  var id: UUID {
    switch self {
    case .hierarchyMelody(let s): return s.id
    case .hierarchyChord(let s):  return s.id
    }
  }

  // MARK: Discriminated Codable

  private enum TypeKey: String, CodingKey { case type }

  private enum MaterialType: String, Codable {
    case hierarchyMelody, hierarchyChord
  }

  init(from decoder: Decoder) throws {
    let typeContainer = try decoder.container(keyedBy: TypeKey.self)
    let materialType = try typeContainer.decode(MaterialType.self, forKey: .type)
    switch materialType {
    case .hierarchyMelody:
      self = .hierarchyMelody(try HierarchyMelodySyntax(from: decoder))
    case .hierarchyChord:
      self = .hierarchyChord(try HierarchyChordSyntax(from: decoder))
    }
  }

  func encode(to encoder: Encoder) throws {
    var typeContainer = encoder.container(keyedBy: TypeKey.self)
    switch self {
    case .hierarchyMelody(let s):
      try typeContainer.encode(MaterialType.hierarchyMelody, forKey: .type)
      try s.encode(to: encoder)
    case .hierarchyChord(let s):
      try typeContainer.encode(MaterialType.hierarchyChord, forKey: .type)
      try s.encode(to: encoder)
    }
  }
}

// MARK: - Hierarchy Melody

/// Note material that produces single notes by resolving degrees through the shared PitchHierarchy.
/// At .scale level, degreeEmitter emits scale degree values directly (supports large ranges with
/// octave wrapping, e.g. chromatic scale with fragment-pool emitter).
/// At .chord level, degreeEmitter emits chord-tone indices into the hierarchy's voicedDegrees.
struct HierarchyMelodySyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var level: HierarchyLevel
  /// Name of an int-output emitter that emits scale degrees (.scale) or chord-tone indices (.chord).
  var degreeEmitter: String
  /// Name of an int/octave-output emitter for the base octave.
  var octaveEmitter: String

  enum CodingKeys: String, CodingKey {
    case id, name, level, degreeEmitter, octaveEmitter, type
  }

  init(
    id: UUID = UUID(),
    name: String,
    level: HierarchyLevel,
    degreeEmitter: String,
    octaveEmitter: String
  ) {
    self.id = id
    self.name = name
    self.level = level
    self.degreeEmitter = degreeEmitter
    self.octaveEmitter = octaveEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    level = try c.decode(HierarchyLevel.self, forKey: .level)
    degreeEmitter = try c.decode(String.self, forKey: .degreeEmitter)
    octaveEmitter = try c.decode(String.self, forKey: .octaveEmitter)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(level, forKey: .level)
    try c.encode(degreeEmitter, forKey: .degreeEmitter)
    try c.encode(octaveEmitter, forKey: .octaveEmitter)
  }
}

// MARK: - Hierarchy Chord

/// Note material that emits the hierarchy's current chord as a voiced set of MIDI notes.
struct HierarchyChordSyntax: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var voicing: VoicingStyle
  /// Name of an int/octave-output emitter for the base octave.
  var octaveEmitter: String

  enum CodingKeys: String, CodingKey {
    case id, name, voicing, octaveEmitter, type
  }

  init(
    id: UUID = UUID(),
    name: String,
    voicing: VoicingStyle = .closed,
    octaveEmitter: String
  ) {
    self.id = id
    self.name = name
    self.voicing = voicing
    self.octaveEmitter = octaveEmitter
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decode(String.self, forKey: .name)
    voicing = try c.decodeIfPresent(VoicingStyle.self, forKey: .voicing) ?? .closed
    octaveEmitter = try c.decode(String.self, forKey: .octaveEmitter)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(voicing, forKey: .voicing)
    try c.encode(octaveEmitter, forKey: .octaveEmitter)
  }
}
