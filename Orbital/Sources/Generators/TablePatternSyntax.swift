//
//  TablePatternSyntax.swift
//  Orbital
//
//  Codable types for the table-based pattern definition system.
//  Four interconnected tables: Emitters, Note Material, Modulators, Track Assembly.
//  Plus an optional shared PitchHierarchy with its own modulators.
//
//  Emitter types        → EmitterSyntax.swift
//  Hierarchy/modulator  → HierarchyModulatorSyntax.swift
//  Note material        → NoteMaterialSyntax.swift
//  Assembly + top-level → TablePatternSyntax.swift (this file)
//

import Foundation

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
