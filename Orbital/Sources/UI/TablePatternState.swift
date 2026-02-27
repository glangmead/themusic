//
//  TablePatternState.swift
//  Orbital
//
//  State bridge types for the table pattern form editor.
//  Each mirrors its Codable counterpart with mutable @State-friendly properties.
//

import Foundation

// MARK: - Emitter Row State

struct EmitterRowState: Identifiable, Equatable {
  let id: UUID
  var name: String
  var outputType: EmitterOutputType
  var function: EmitterFunction
  var arg1: CoreFloat
  var arg2: CoreFloat
  var candidates: [String]
  var inputEmitters: [String]
  var fragments: [[Int]]
  var updateMode: EmitterUpdateMode

  init(from syntax: EmitterRowSyntax) {
    id = syntax.id
    name = syntax.name
    outputType = syntax.outputType
    function = syntax.function
    arg1 = syntax.arg1 ?? 0
    arg2 = syntax.arg2 ?? 1
    candidates = syntax.candidates ?? []
    inputEmitters = syntax.inputEmitters ?? []
    fragments = syntax.fragments ?? []
    updateMode = syntax.updateMode
  }

  init() {
    id = UUID()
    name = ""
    outputType = .float
    function = .randFloat
    arg1 = 0
    arg2 = 1
    candidates = []
    inputEmitters = []
    fragments = []
    updateMode = .each
  }

  func toSyntax() -> EmitterRowSyntax {
    EmitterRowSyntax(
      id: id,
      name: name,
      outputType: outputType,
      function: function,
      arg1: needsArgs ? arg1 : nil,
      arg2: needsArgs ? arg2 : nil,
      candidates: needsCandidates ? candidates : nil,
      inputEmitters: needsInputEmitters ? inputEmitters : nil,
      fragments: needsFragments ? fragments : nil,
      updateMode: updateMode
    )
  }

  /// Whether this function uses a fragments list.
  var needsFragments: Bool {
    if case .fragmentPool = function { return true }
    return false
  }

  /// Whether this function uses arg1/arg2 (min/max numeric params).
  var needsArgs: Bool {
    switch function {
    case .randFloat, .exponentialRandFloat, .randInt: return true
    default: return false
    }
  }

  /// Whether this function uses a candidates list.
  var needsCandidates: Bool {
    switch function {
    case .shuffle, .cyclic, .random: return true
    case .indexPicker: return true
    default: return false
    }
  }

  /// Whether this function references other emitters via inputEmitters.
  var needsInputEmitters: Bool {
    switch function {
    case .sum, .reciprocal: return true
    default: return false
    }
  }
}

// MARK: - Note Material Row State

/// A lightweight state wrapper for a NoteMaterialSyntax entry.
/// The note material type is shown for reference; deep editing of hierarchy types
/// is handled via JSON editing rather than in-form controls.
struct NoteMaterialRowState: Identifiable, Equatable {
  let id: UUID
  var name: String
  /// The full syntax, preserved for round-tripping.
  var syntax: NoteMaterialSyntax

  var typeName: String {
    switch syntax {
    case .scaleMaterial:   return "Scale Material"
    case .hierarchyMelody: return "Hierarchy Melody"
    case .hierarchyChord:  return "Hierarchy Chord"
    case .hierarchyBass:   return "Hierarchy Bass"
    }
  }

  init(from syntax: NoteMaterialSyntax) {
    self.id = syntax.id
    self.name = syntax.name
    self.syntax = syntax
  }

  init() {
    let defaultSyntax = NoteMaterialSyntax.scaleMaterial(
      ScaleMaterialSyntax(name: "", root: "C", scale: "major", intervalPickerEmitter: "", octaveEmitter: "")
    )
    self.id = defaultSyntax.id
    self.name = ""
    self.syntax = defaultSyntax
  }

  func toSyntax() -> NoteMaterialSyntax {
    syntax
  }
}

// MARK: - Preset Modulator Row State

enum ModulatorSourceKind: String, CaseIterable {
  case floatEmitter = "Float Emitter"
  case expression = "Expression"
}

struct TableModulatorRowState: Identifiable, Equatable {
  let id: UUID
  var name: String
  var targetHandle: String
  var floatEmitter: String
  /// Arrow-based modulation formula (optional). When present, takes precedence over floatEmitter.
  var arrow: ArrowSyntax?
  /// Quick expression text for arrow-based modulation, editable in the form.
  var quickExpressionText: String

  var sourceKind: ModulatorSourceKind {
    get {
      if arrow != nil || !quickExpressionText.isEmpty {
        return .expression
      }
      return .floatEmitter
    }
    set {
      switch newValue {
      case .floatEmitter:
        arrow = nil
        quickExpressionText = ""
      case .expression:
        floatEmitter = ""
      }
    }
  }

  init(from syntax: PresetModulatorRowSyntax) {
    id = syntax.id
    name = syntax.name
    targetHandle = syntax.targetHandle
    floatEmitter = syntax.floatEmitter ?? ""
    arrow = syntax.arrow
    if case .quickExpression(let expr) = syntax.arrow {
      quickExpressionText = expr
    } else {
      quickExpressionText = ""
    }
  }

  init() {
    id = UUID()
    name = ""
    targetHandle = "overallAmp"
    floatEmitter = ""
    arrow = nil
    quickExpressionText = ""
  }

  func toSyntax() -> PresetModulatorRowSyntax {
    let resolvedArrow: ArrowSyntax?
    if !quickExpressionText.isEmpty {
      resolvedArrow = .quickExpression(quickExpressionText)
    } else {
      resolvedArrow = arrow
    }
    return PresetModulatorRowSyntax(
      id: id,
      name: name,
      targetHandle: targetHandle,
      floatEmitter: resolvedArrow != nil ? nil : floatEmitter,
      arrow: resolvedArrow
    )
  }
}

// MARK: - Track Assembly Row State

struct TrackAssemblyRowState: Identifiable, Equatable {
  let id: UUID
  var name: String
  var presetFilename: String
  var numVoices: Int
  var presetModulatorNames: [String]
  var noteMaterial: String
  var sustainEmitter: String
  var gapEmitter: String

  init(from syntax: TrackAssemblyRowSyntax) {
    id = syntax.id
    name = syntax.name
    presetFilename = syntax.presetFilename
    numVoices = syntax.numVoices ?? 12
    presetModulatorNames = syntax.presetModulatorNames
    noteMaterial = syntax.noteMaterial
    sustainEmitter = syntax.sustainEmitter
    gapEmitter = syntax.gapEmitter
  }

  init() {
    id = UUID()
    name = ""
    presetFilename = ""
    numVoices = 12
    presetModulatorNames = []
    noteMaterial = ""
    sustainEmitter = ""
    gapEmitter = ""
  }

  func toSyntax() -> TrackAssemblyRowSyntax {
    TrackAssemblyRowSyntax(
      id: id,
      name: name,
      presetFilename: presetFilename,
      numVoices: numVoices,
      presetModulatorNames: presetModulatorNames,
      noteMaterial: noteMaterial,
      sustainEmitter: sustainEmitter,
      gapEmitter: gapEmitter
    )
  }
}
