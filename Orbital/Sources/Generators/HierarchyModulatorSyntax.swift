//
//  HierarchyModulatorSyntax.swift
//  Orbital
//
//  Codable types for the shared PitchHierarchy and its modulator table.
//  Extracted from TablePatternSyntax.swift.
//

import Foundation

// MARK: - Hierarchy

/// The initial state of the shared PitchHierarchy for this pattern.
struct HierarchySyntax: Codable, Equatable {
  var root: String    // NoteClass name, e.g. "C"
  var scale: String   // Scale name, e.g. "major"
  var chord: ChordInScaleSyntax
}

/// Initial chord expressed as scale degrees, with optional per-degree perturbations.
struct ChordInScaleSyntax: Codable, Equatable {
  var degrees: [Int]
  var inversion: Int
  var perturbations: [PerturbationSyntax?]?
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
