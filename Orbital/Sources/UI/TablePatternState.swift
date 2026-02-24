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
      updateMode: updateMode
    )
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

struct NoteMaterialRowState: Identifiable, Equatable {
  let id: UUID
  var name: String
  /// Each entry as a comma-separated string for editing (e.g. "0,2,4").
  var intervalStrings: [String]
  var intervalPicker: String
  var octaveEmitter: String
  var scaleEmitter: String
  var scaleRootEmitter: String

  init(from syntax: NoteMaterialRowSyntax) {
    id = syntax.id
    name = syntax.name
    intervalStrings = syntax.intervalMaterial.map { degrees in
      degrees.map(String.init).joined(separator: ",")
    }
    intervalPicker = syntax.intervalPicker
    octaveEmitter = syntax.octaveEmitter
    scaleEmitter = syntax.scaleEmitter
    scaleRootEmitter = syntax.scaleRootEmitter
  }

  init() {
    id = UUID()
    name = ""
    intervalStrings = ["0"]
    intervalPicker = ""
    octaveEmitter = ""
    scaleEmitter = ""
    scaleRootEmitter = ""
  }

  func toSyntax() -> NoteMaterialRowSyntax {
    let material = intervalStrings.map { str in
      str.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }.filter { !$0.isEmpty }
    return NoteMaterialRowSyntax(
      id: id,
      name: name,
      intervalMaterial: material.isEmpty ? [[0]] : material,
      intervalPicker: intervalPicker,
      octaveEmitter: octaveEmitter,
      scaleEmitter: scaleEmitter,
      scaleRootEmitter: scaleRootEmitter
    )
  }
}

// MARK: - Modulator Row State

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

  init(from syntax: ModulatorRowSyntax) {
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

  func toSyntax() -> ModulatorRowSyntax {
    let resolvedArrow: ArrowSyntax?
    if !quickExpressionText.isEmpty {
      resolvedArrow = .quickExpression(quickExpressionText)
    } else {
      resolvedArrow = arrow
    }
    return ModulatorRowSyntax(
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
  var modulatorNames: [String]
  var noteMaterial: String
  var sustainEmitter: String
  var gapEmitter: String

  init(from syntax: TrackAssemblyRowSyntax) {
    id = syntax.id
    name = syntax.name
    presetFilename = syntax.presetFilename
    numVoices = syntax.numVoices ?? 12
    modulatorNames = syntax.modulatorNames
    noteMaterial = syntax.noteMaterial
    sustainEmitter = syntax.sustainEmitter
    gapEmitter = syntax.gapEmitter
  }

  init() {
    id = UUID()
    name = ""
    presetFilename = ""
    numVoices = 12
    modulatorNames = []
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
      modulatorNames: modulatorNames,
      noteMaterial: noteMaterial,
      sustainEmitter: sustainEmitter,
      gapEmitter: gapEmitter
    )
  }
}
