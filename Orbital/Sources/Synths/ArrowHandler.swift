//
//  ArrowHandler.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

// MARK: - ArrowHandler

/// An @Observable class that provides dynamic, bindable access to all editable
/// parameters in an ArrowSyntax tree. Constructed from the syntax for metadata,
/// then linked to compiled ArrowWithHandles for write-through to the DSP graph.
@MainActor @Observable
final class ArrowHandler {
  /// Parameter metadata, ordered as discovered by tree walk.
  let descriptors: [ArrowParamDescriptor]

  /// The aggregated handles from all voices across all spatial presets.
  private(set) var handles: ArrowWithHandles?

  /// Storage for float-valued parameters. Mutations trigger @Observable tracking.
  private(set) var floatValues: [String: CoreFloat] = [:]

  /// Storage for osc shape parameters. Mutations trigger @Observable tracking.
  private(set) var shapeValues: [String: BasicOscillator.OscShape] = [:]

  /// Lookup from id -> descriptor for fast access.
  private let _descriptorMap: [String: ArrowParamDescriptor]

  /// Look up a descriptor by its id.
  func descriptorMap(for id: String) -> ArrowParamDescriptor? {
    _descriptorMap[id]
  }

  init(syntax: ArrowSyntax) {
    let descs = syntax.parameterDescriptors()
    self.descriptors = descs

    var map = [String: ArrowParamDescriptor]()
    var floats = [String: CoreFloat]()
    var shapes = [String: BasicOscillator.OscShape]()
    for desc in descs {
      map[desc.id] = desc
      switch desc.kind {
      case .oscShape:
        shapes[desc.id] = desc.defaultShape ?? .sine
      default:
        floats[desc.id] = desc.defaultValue
      }
    }
    self._descriptorMap = map
    self.floatValues = floats
    self.shapeValues = shapes
  }

  /// Link this handler to live DSP objects. Called after SpatialPreset construction.
  func attachHandles(_ handles: ArrowWithHandles) {
    self.handles = handles
    readFromHandles()
  }

  /// Read current values from the compiled handles into storage.
  func readFromHandles() {
    guard let handles else { return }
    for desc in descriptors {
      switch desc.kind {
      case .constVal, .constOctave, .constCent:
        if let first = handles.namedConsts[desc.id]?.first {
          floatValues[desc.id] = first.val
        }
      case .envelopeAttack(let envName):
        if let first = handles.namedADSREnvelopes[envName]?.first {
          floatValues[desc.id] = first.env.attackTime
        }
      case .envelopeDecay(let envName):
        if let first = handles.namedADSREnvelopes[envName]?.first {
          floatValues[desc.id] = first.env.decayTime
        }
      case .envelopeSustain(let envName):
        if let first = handles.namedADSREnvelopes[envName]?.first {
          floatValues[desc.id] = first.env.sustainLevel
        }
      case .envelopeRelease(let envName):
        if let first = handles.namedADSREnvelopes[envName]?.first {
          floatValues[desc.id] = first.env.releaseTime
        }
      case .oscShape(let oscName):
        if let first = handles.namedBasicOscs[oscName]?.first {
          shapeValues[desc.id] = first.shape
        }
      case .chorusCentRadius(let choruserName):
        if let first = handles.namedChorusers[choruserName]?.first {
          floatValues[desc.id] = CoreFloat(first.chorusCentRadius)
        }
      case .chorusNumVoices(let choruserName):
        if let first = handles.namedChorusers[choruserName]?.first {
          floatValues[desc.id] = CoreFloat(first.chorusNumVoices)
        }
      }
    }
  }

  // MARK: - Setters with write-through

  /// Write a float value and propagate to all handle instances.
  func setFloat(_ id: String, to value: CoreFloat) {
    floatValues[id] = value
    guard let handles, let desc = _descriptorMap[id] else { return }
    switch desc.kind {
    case .constVal, .constOctave, .constCent:
      handles.namedConsts[id]?.forEach { $0.val = value }
    case .envelopeAttack(let envName):
      handles.namedADSREnvelopes[envName]?.forEach { $0.env.attackTime = value }
    case .envelopeDecay(let envName):
      handles.namedADSREnvelopes[envName]?.forEach { $0.env.decayTime = value }
    case .envelopeSustain(let envName):
      handles.namedADSREnvelopes[envName]?.forEach { $0.env.sustainLevel = value }
    case .envelopeRelease(let envName):
      handles.namedADSREnvelopes[envName]?.forEach { $0.env.releaseTime = value }
    case .oscShape:
      break // handled by setShape
    case .chorusCentRadius(let choruserName):
      handles.namedChorusers[choruserName]?.forEach { $0.chorusCentRadius = Int(value) }
    case .chorusNumVoices(let choruserName):
      handles.namedChorusers[choruserName]?.forEach { $0.chorusNumVoices = Int(value) }
    }
  }

  /// Write a shape value and propagate.
  func setShape(_ id: String, to shape: BasicOscillator.OscShape) {
    shapeValues[id] = shape
    guard let handles, let desc = _descriptorMap[id] else { return }
    if case .oscShape(let oscName) = desc.kind {
      handles.namedBasicOscs[oscName]?.forEach { $0.shape = shape }
    }
  }

  // MARK: - Binding Factories

  func floatBinding(for id: String) -> Binding<CoreFloat> {
    Binding(
      get: { [weak self] in self?.floatValues[id] ?? 0 },
      set: { [weak self] in self?.setFloat(id, to: $0) }
    )
  }

  func shapeBinding(for id: String) -> Binding<BasicOscillator.OscShape> {
    Binding(
      get: { [weak self] in self?.shapeValues[id] ?? .sine },
      set: { [weak self] in self?.setShape(id, to: $0) }
    )
  }

  // MARK: - Grouping for UI

  /// Group descriptors into sections for Form display, merging all descriptors
  /// with the same group name and preserving first-seen order of groups.
  func groupedDescriptors() -> [(String, [ArrowParamDescriptor])] {
    var order: [String] = []
    var map: [String: [ArrowParamDescriptor]] = [:]

    for desc in descriptors {
      if map[desc.group] == nil {
        order.append(desc.group)
        map[desc.group] = [desc]
      } else {
        map[desc.group]!.append(desc)
      }
    }
    return order.map { ($0, map[$0]!) }
  }
}
