//
//  TablePatternCompiler.swift
//  Orbital
//
//  Compiles a TablePatternSyntax into a MusicPattern by resolving
//  name references, building shared emitter instances, and assembling tracks.
//

import Foundation
import Tonic

// MARK: - Compiled Emitter Wrapper

/// Type-erased wrapper holding a compiled emitter's iterator and metadata.
/// The iterator is stored as `Any` because emitters produce different types
/// (CoreFloat, Int, Scale, NoteClass) depending on their outputType.
final class CompiledEmitter {
  let outputType: EmitterOutputType
  /// The underlying iterator, type-erased. Callers must cast based on outputType.
  let iterator: Any
  /// Mutable parameters exposed for meta-modulation (e.g. "arg1", "arg2").
  var mutableParams: [String: MutableParam]
  /// Shadow ArrowConst that holds the float-coerced last value from this emitter.
  /// Updated by CapturingIterator wrapper whenever next() is called.
  let lastValueShadow: ArrowConst

  init(outputType: EmitterOutputType, iterator: Any, mutableParams: [String: MutableParam] = [:], lastValueShadow: ArrowConst = ArrowConst(value: 0)) {
    self.outputType = outputType
    self.iterator = iterator
    self.mutableParams = mutableParams
    self.lastValueShadow = lastValueShadow
  }

  /// Convenience to get the iterator as a specific type.
  func floatIterator() -> (any IteratorProtocol<CoreFloat>)? {
    iterator as? any IteratorProtocol<CoreFloat>
  }

  func intIterator() -> (any IteratorProtocol<Int>)? {
    iterator as? any IteratorProtocol<Int>
  }

  func scaleIterator() -> (any IteratorProtocol<Scale>)? {
    iterator as? any IteratorProtocol<Scale>
  }

  func rootIterator() -> (any IteratorProtocol<NoteClass>)? {
    iterator as? any IteratorProtocol<NoteClass>
  }
}

// MARK: - Compile Errors

enum TableCompileError: Error, CustomStringConvertible {
  case unknownEmitter(name: String, referencedBy: String)
  case cyclicDependency(chain: [String])
  case typeMismatch(emitter: String, expected: EmitterOutputType, got: EmitterOutputType)
  case unknownNoteMaterial(name: String, referencedBy: String)
  case unknownModulator(name: String, referencedBy: String)
  case emptyIntervalMaterial(noteMaterial: String)

  var description: String {
    switch self {
    case .unknownEmitter(let name, let ref):
      return "Unknown emitter '\(name)' referenced by '\(ref)'"
    case .cyclicDependency(let chain):
      return "Cyclic dependency: \(chain.joined(separator: " → "))"
    case .typeMismatch(let name, let expected, let got):
      return "Type mismatch for emitter '\(name)': expected \(expected), got \(got)"
    case .unknownNoteMaterial(let name, let ref):
      return "Unknown note material '\(name)' referenced by track '\(ref)'"
    case .unknownModulator(let name, let ref):
      return "Unknown modulator '\(name)' referenced by track '\(ref)'"
    case .emptyIntervalMaterial(let name):
      return "Note material '\(name)' has empty interval material"
    }
  }
}

// MARK: - TablePatternCompiler

enum TablePatternCompiler {

  // MARK: - Public Entry Point

  /// Compile a TablePatternSyntax into a MusicPattern + TrackInfo array.
  static func compile(
    _ table: TablePatternSyntax,
    engine: SpatialAudioEngine,
    clock: any Clock<Duration> = ContinuousClock()
  ) async throws -> (MusicPattern, [TrackInfo]) {
    // 1. Build and validate the emitter dependency graph
    let sortedEmitterNames = try topologicalSort(table.emitters)

    // 2. Instantiate emitters in dependency order (shared instances by name)
    var compiledEmitters: [String: CompiledEmitter] = [:]
    for name in sortedEmitterNames {
      guard let row = table.emitters.first(where: { $0.name == name }) else { continue }
      let emitter = try compileEmitter(row, allEmitters: compiledEmitters)
      compiledEmitters[name] = emitter
    }

    // 3. Compile note materials
    var compiledNoteMaterials: [String: any IteratorProtocol<[MidiNote]>] = [:]
    for noteMat in table.noteMaterials {
      let gen = try compileNoteMaterial(noteMat, emitters: compiledEmitters)
      compiledNoteMaterials[noteMat.name] = gen
    }

    // 4. Compile modulators (including meta-modulation)
    var compiledModulators: [String: (target: String, arrow: Arrow11)] = [:]
    for mod in table.modulators {
      let result = try compileModulator(mod, emitters: compiledEmitters)
      compiledModulators[mod.name] = result
    }

    // 5. Assemble tracks
    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []

    for (i, trackRow) in table.tracks.enumerated() {
      let presetFileName = trackRow.presetFilename + ".json"
      let presetSpec = Bundle.main.decode(PresetSyntax.self, from: presetFileName, subdirectory: "presets")
      let voices = trackRow.numVoices ?? 12
      let sp = try await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: voices)

      // Look up note material
      guard var notes = compiledNoteMaterials[trackRow.noteMaterial] else {
        throw TableCompileError.unknownNoteMaterial(name: trackRow.noteMaterial, referencedBy: trackRow.name)
      }

      // Look up sustain and gap emitters
      let sustainEmitter = try requireFloatEmitter(trackRow.sustainEmitter, emitters: compiledEmitters, referencedBy: trackRow.name)
      let gapEmitter = try requireFloatEmitter(trackRow.gapEmitter, emitters: compiledEmitters, referencedBy: trackRow.name)

      // Collect modulators
      var modDict: [String: Arrow11] = [:]
      for modName in trackRow.modulatorNames {
        guard let mod = compiledModulators[modName] else {
          throw TableCompileError.unknownModulator(name: modName, referencedBy: trackRow.name)
        }
        modDict[mod.target] = mod.arrow
      }

      musicTracks.append(MusicPattern.Track(
        spatialPreset: sp,
        modulators: modDict,
        notes: notes,
        sustains: sustainEmitter,
        gaps: gapEmitter,
        name: trackRow.name
      ))

      trackInfos.append(TrackInfo(
        id: i,
        patternName: trackRow.name,
        trackSpec: nil,
        presetSpec: presetSpec,
        spatialPreset: sp
      ))
    }

    let pattern = MusicPattern(tracks: musicTracks, clock: clock)
    return (pattern, trackInfos)
  }

  /// Compile for UI-only display (no engine, no audio nodes).
  static func compileTrackInfoOnly(_ table: TablePatternSyntax) -> [TrackInfo] {
    var infos: [TrackInfo] = []
    for (i, trackRow) in table.tracks.enumerated() {
      let presetFileName = trackRow.presetFilename + ".json"
      let presetSpec = Bundle.main.decode(PresetSyntax.self, from: presetFileName, subdirectory: "presets")
      let sp = SpatialPreset(presetSpec: presetSpec, numVoices: trackRow.numVoices ?? 12)
      infos.append(TrackInfo(
        id: i,
        patternName: trackRow.name,
        trackSpec: nil,
        presetSpec: presetSpec,
        spatialPreset: sp
      ))
    }
    return infos
  }

  // MARK: - Topological Sort

  /// Build dependency graph from emitter cross-references and sort topologically.
  /// Returns emitter names in safe instantiation order.
  static func topologicalSort(_ emitters: [EmitterRowSyntax]) throws -> [String] {
    // Build adjacency: edges point from dependency → dependent
    var inDegree: [String: Int] = [:]
    var dependents: [String: [String]] = [:]

    // Initialize all emitters
    for e in emitters {
      inDegree[e.name] = 0
      dependents[e.name] = []
    }

    // Add edges for each dependency
    for e in emitters {
      let deps = dependencies(of: e)
      // Only count deps that are emitter names (not external references)
      let emitterNames = Set(emitters.map(\.name))
      for dep in deps where emitterNames.contains(dep) {
        inDegree[e.name, default: 0] += 1
        dependents[dep, default: []].append(e.name)
      }
    }

    // Kahn's algorithm
    var queue = emitters.map(\.name).filter { inDegree[$0, default: 0] == 0 }
    var sorted: [String] = []

    while !queue.isEmpty {
      let node = queue.removeFirst()
      sorted.append(node)
      for dependent in dependents[node, default: []] {
        inDegree[dependent, default: 0] -= 1
        if inDegree[dependent, default: 0] == 0 {
          queue.append(dependent)
        }
      }
    }

    if sorted.count < emitters.count {
      // Find a cycle for error reporting
      let unsorted = Set(emitters.map(\.name)).subtracting(sorted)
      throw TableCompileError.cyclicDependency(chain: Array(unsorted))
    }

    return sorted
  }

  /// Extract the names of emitters that a given emitter depends on.
  private static func dependencies(of emitter: EmitterRowSyntax) -> [String] {
    var deps: [String] = []

    // inputEmitters (for sum, reciprocal)
    if let inputs = emitter.inputEmitters {
      deps.append(contentsOf: inputs)
    }

    // indexPicker emitter reference
    if case .indexPicker(let emitterName) = emitter.function {
      deps.append(emitterName)
    }

    // waiting update mode reference
    if case .waiting(let emitterName) = emitter.updateMode {
      deps.append(emitterName)
    }

    return deps
  }

  // MARK: - Emitter Compilation

  private static func compileEmitter(
    _ row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) throws -> CompiledEmitter {
    switch row.outputType {
    case .float:
      return try compileFloatEmitter(row, allEmitters: allEmitters)
    case .int:
      return try compileIntEmitter(row, allEmitters: allEmitters)
    case .root:
      return try compileRootEmitter(row, allEmitters: allEmitters)
    case .octave:
      return try compileOctaveEmitter(row, allEmitters: allEmitters)
    case .scale:
      return try compileScaleEmitter(row, allEmitters: allEmitters)
    }
  }

  private static func compileFloatEmitter(
    _ row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) throws -> CompiledEmitter {
    let minVal = row.arg1 ?? 0
    let maxVal = row.arg2 ?? 1
    var mutableParams: [String: MutableParam] = [:]

    var iter: any IteratorProtocol<CoreFloat>

    switch row.function {
    case .randFloat:
      let minP = MutableParam(minVal)
      let maxP = MutableParam(maxVal)
      mutableParams["arg1"] = minP
      mutableParams["arg2"] = maxP
      iter = MutableFloatSampler(minParam: minP, maxParam: maxP)

    case .exponentialRandFloat:
      iter = FloatSampler(min: minVal, max: maxVal, dist: .exponential)

    case .sum:
      guard let inputs = row.inputEmitters, !inputs.isEmpty else {
        iter = FloatSampler(min: 0, max: 0)
        break
      }
      var sources: [any IteratorProtocol<CoreFloat>] = []
      for inputName in inputs {
        if let compiled = allEmitters[inputName], let fi = compiled.floatIterator() {
          sources.append(fi)
        } else if let compiled = allEmitters[inputName], let ii = compiled.intIterator() {
          // Allow int→float coercion for sum
          sources.append(IntToFloatIterator(source: ii))
        } else {
          throw TableCompileError.unknownEmitter(name: inputName, referencedBy: row.name)
        }
      }
      iter = SumIterator(sources: sources)

    case .reciprocal:
      guard let inputs = row.inputEmitters, let inputName = inputs.first,
            let compiled = allEmitters[inputName] else {
        iter = FloatSampler(min: 0, max: 0)
        break
      }
      if let fi = compiled.floatIterator() {
        iter = ReciprocalIterator(source: fi)
      } else if let ii = compiled.intIterator() {
        iter = ReciprocalIterator(source: IntToFloatIterator(source: ii))
      } else {
        throw TableCompileError.typeMismatch(emitter: inputName, expected: .float, got: compiled.outputType)
      }

    default:
      // List-based functions on float candidates
      if let candidates = row.candidates {
        let floats = candidates.compactMap { CoreFloat($0) }
        iter = applyListFunction(row.function, to: floats)
      } else {
        iter = FloatSampler(min: minVal, max: maxVal)
      }
    }

    iter = wrapUpdateMode(iter, row: row, allEmitters: allEmitters)
    let shadow = ArrowConst(value: 0)
    let capturing = CapturingIterator(inner: iter, shadow: shadow, toFloat: { $0 })
    return CompiledEmitter(outputType: .float, iterator: capturing, mutableParams: mutableParams, lastValueShadow: shadow)
  }

  private static func compileIntEmitter(
    _ row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) throws -> CompiledEmitter {
    var iter: any IteratorProtocol<Int>

    switch row.function {
    case .randInt:
      let minVal = Int(row.arg1 ?? 0)
      let maxVal = Int(row.arg2 ?? 1)
      iter = IntSampler(min: minVal, max: maxVal)

    case .indexPicker(let emitterName):
      guard let compiled = allEmitters[emitterName], let indexIter = compiled.intIterator() else {
        throw TableCompileError.unknownEmitter(name: emitterName, referencedBy: row.name)
      }
      let candidates = row.candidates ?? []
      let ints = candidates.compactMap { Int($0) }
      iter = IndexPickerIterator(items: ints, indexEmitter: indexIter)

    default:
      // List-based functions on int candidates
      if let candidates = row.candidates {
        let ints = candidates.compactMap { Int($0) }
        iter = applyListFunction(row.function, to: ints)
      } else {
        iter = IntSampler(min: Int(row.arg1 ?? 0), max: Int(row.arg2 ?? 1))
      }
    }

    iter = wrapUpdateMode(iter, row: row, allEmitters: allEmitters)
    let shadow = ArrowConst(value: 0)
    let capturing = CapturingIterator(inner: iter, shadow: shadow, toFloat: { CoreFloat($0) })
    return CompiledEmitter(outputType: .int, iterator: capturing, lastValueShadow: shadow)
  }

  private static func compileRootEmitter(
    _ row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) throws -> CompiledEmitter {
    let candidates = (row.candidates ?? []).map { NoteGeneratorSyntax.resolveNoteClass($0) }
    var iter: any IteratorProtocol<NoteClass>

    switch row.function {
    case .indexPicker(let emitterName):
      guard let compiled = allEmitters[emitterName], let indexIter = compiled.intIterator() else {
        throw TableCompileError.unknownEmitter(name: emitterName, referencedBy: row.name)
      }
      iter = IndexPickerIterator(items: candidates, indexEmitter: indexIter)
    default:
      iter = applyListFunction(row.function, to: candidates)
    }

    iter = wrapUpdateMode(iter, row: row, allEmitters: allEmitters)
    let shadow = ArrowConst(value: 0)
    let capturing = CapturingIterator(inner: iter, shadow: shadow, toFloat: { _ in 0 })
    return CompiledEmitter(outputType: .root, iterator: capturing, lastValueShadow: shadow)
  }

  private static func compileOctaveEmitter(
    _ row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) throws -> CompiledEmitter {
    let candidates = (row.candidates ?? []).compactMap { Int($0) }
    var iter: any IteratorProtocol<Int>

    switch row.function {
    case .indexPicker(let emitterName):
      guard let compiled = allEmitters[emitterName], let indexIter = compiled.intIterator() else {
        throw TableCompileError.unknownEmitter(name: emitterName, referencedBy: row.name)
      }
      iter = IndexPickerIterator(items: candidates, indexEmitter: indexIter)
    default:
      iter = applyListFunction(row.function, to: candidates)
    }

    iter = wrapUpdateMode(iter, row: row, allEmitters: allEmitters)
    let shadow = ArrowConst(value: 0)
    let capturing = CapturingIterator(inner: iter, shadow: shadow, toFloat: { CoreFloat($0) })
    return CompiledEmitter(outputType: .octave, iterator: capturing, lastValueShadow: shadow)
  }

  private static func compileScaleEmitter(
    _ row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) throws -> CompiledEmitter {
    let candidates = (row.candidates ?? []).map { NoteGeneratorSyntax.resolveScale($0) }
    var iter: any IteratorProtocol<Scale>

    switch row.function {
    case .indexPicker(let emitterName):
      guard let compiled = allEmitters[emitterName], let indexIter = compiled.intIterator() else {
        throw TableCompileError.unknownEmitter(name: emitterName, referencedBy: row.name)
      }
      iter = IndexPickerIterator(items: candidates, indexEmitter: indexIter)
    default:
      iter = applyListFunction(row.function, to: candidates)
    }

    iter = wrapUpdateMode(iter, row: row, allEmitters: allEmitters)
    let shadow = ArrowConst(value: 0)
    let capturing = CapturingIterator(inner: iter, shadow: shadow, toFloat: { _ in 0 })
    return CompiledEmitter(outputType: .scale, iterator: capturing, lastValueShadow: shadow)
  }

  // MARK: - List Function Application

  /// Apply a list-based function (shuffle, cyclic, random) to a collection.
  private static func applyListFunction<T>(
    _ function: EmitterFunction,
    to items: [T]
  ) -> any IteratorProtocol<T> {
    switch function {
    case .shuffle:  return items.shuffledIterator()
    case .cyclic:   return items.cyclicIterator()
    case .random:   return items.randomIterator()
    default:        return items.cyclicIterator()
    }
  }

  // MARK: - Update Mode Wrapping

  /// Wrap an iterator based on the emitter's update mode.
  private static func wrapUpdateMode<T>(
    _ iter: any IteratorProtocol<T>,
    row: EmitterRowSyntax,
    allEmitters: [String: CompiledEmitter]
  ) -> any IteratorProtocol<T> {
    switch row.updateMode {
    case .each:
      return LatchingIterator(inner: iter)
    case .waiting(let emitterName):
      if let compiled = allEmitters[emitterName], let fi = compiled.floatIterator() {
        let arrow = EmitterArrow(emitter: fi)
        return WaitingIterator(iterator: iter, timeBetweenChanges: arrow)
      }
      // Fallback: latch if the referenced emitter isn't found
      return LatchingIterator(inner: iter)
    }
  }

  // MARK: - Note Material Compilation

  private static func compileNoteMaterial(
    _ noteMat: NoteMaterialRowSyntax,
    emitters: [String: CompiledEmitter]
  ) throws -> any IteratorProtocol<[MidiNote]> {
    guard !noteMat.intervalMaterial.isEmpty else {
      throw TableCompileError.emptyIntervalMaterial(noteMaterial: noteMat.name)
    }

    // Look up required emitters
    guard let pickerEmitter = emitters[noteMat.intervalPicker],
          let pickerIter = pickerEmitter.intIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.intervalPicker, referencedBy: noteMat.name)
    }
    guard let scaleEmitter = emitters[noteMat.scaleEmitter],
          let scaleIter = scaleEmitter.scaleIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.scaleEmitter, referencedBy: noteMat.name)
    }
    guard let rootEmitter = emitters[noteMat.scaleRootEmitter],
          let rootIter = rootEmitter.rootIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.scaleRootEmitter, referencedBy: noteMat.name)
    }
    guard let octEmitter = emitters[noteMat.octaveEmitter],
          let octIter = octEmitter.intIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.octaveEmitter, referencedBy: noteMat.name)
    }

    return TableNoteGenerator(
      intervalMaterial: noteMat.intervalMaterial,
      intervalPicker: pickerIter,
      scaleEmitter: scaleIter,
      rootEmitter: rootIter,
      octaveEmitter: octIter
    )
  }

  // MARK: - Modulator Compilation

  private static func compileModulator(
    _ mod: ModulatorRowSyntax,
    emitters: [String: CompiledEmitter]
  ) throws -> (target: String, arrow: Arrow11) {
    // Arrow-based modulator: compile the ArrowSyntax and wire emitterValue placeholders
    if let arrowSyntax = mod.arrow {
      let compiled = arrowSyntax.compile()
      // Wire emitter value placeholders to shadows
      for (emitterName, placeholders) in compiled.namedEmitterValues {
        guard let shadow = emitters[emitterName]?.lastValueShadow else {
          throw TableCompileError.unknownEmitter(name: emitterName, referencedBy: mod.name)
        }
        for placeholder in placeholders {
          placeholder.forwardTo = shadow
        }
      }
      return (target: mod.targetHandle, arrow: compiled)
    }

    // Float-emitter based modulation (existing path)
    guard let floatEmitterName = mod.floatEmitter, !floatEmitterName.isEmpty else {
      throw TableCompileError.unknownEmitter(name: "(none)", referencedBy: mod.name)
    }

    // Check for meta-modulation: "emitterName.paramName"
    if mod.targetHandle.contains(".") {
      let parts = mod.targetHandle.split(separator: ".", maxSplits: 1)
      if parts.count == 2 {
        let emitterName = String(parts[0])
        let paramName = String(parts[1])

        // Look up the target emitter's mutable param
        if let targetEmitter = emitters[emitterName],
           let param = targetEmitter.mutableParams[paramName] {
          // Create an arrow that writes to the mutable param
          guard let sourceEmitter = emitters[floatEmitterName],
                let sourceIter = sourceEmitter.floatIterator() else {
            throw TableCompileError.unknownEmitter(name: floatEmitterName, referencedBy: mod.name)
          }
          let arrow = MetaModulationArrow(source: sourceIter, target: param)
          // Return a dummy target — meta-modulation happens inside the arrow
          return (target: "__meta_\(mod.name)", arrow: arrow)
        }
      }
    }

    // Standard modulation: target is a preset handle name
    guard let sourceEmitter = emitters[floatEmitterName],
          let sourceIter = sourceEmitter.floatIterator() else {
      throw TableCompileError.unknownEmitter(name: floatEmitterName, referencedBy: mod.name)
    }
    return (target: mod.targetHandle, arrow: EmitterArrow(emitter: sourceIter))
  }

  // MARK: - Helpers

  private static func requireFloatEmitter(
    _ name: String,
    emitters: [String: CompiledEmitter],
    referencedBy: String
  ) throws -> any IteratorProtocol<CoreFloat> {
    guard let compiled = emitters[name], let fi = compiled.floatIterator() else {
      throw TableCompileError.unknownEmitter(name: name, referencedBy: referencedBy)
    }
    return fi
  }
}
