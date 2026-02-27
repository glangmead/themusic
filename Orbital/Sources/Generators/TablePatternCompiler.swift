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
/// (CoreFloat, Int) depending on their outputType.
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
}

// MARK: - Compile Errors

enum TableCompileError: Error, CustomStringConvertible {
  case unknownEmitter(name: String, referencedBy: String)
  case cyclicDependency(chain: [String])
  case typeMismatch(emitter: String, expected: EmitterOutputType, got: EmitterOutputType)
  case unknownNoteMaterial(name: String, referencedBy: String)
  case unknownModulator(name: String, referencedBy: String)
  case missingHierarchy(referencedBy: String)

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
    case .missingHierarchy(let ref):
      return "Note material '\(ref)' requires a hierarchy, but none is defined in the pattern"
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
    clock: any Clock<Duration> = ContinuousClock(),
    resourceBaseURL: URL? = nil
  ) async throws -> PatternSyntax.CompileResult {
    // 1. Build and validate the emitter dependency graph
    let sortedEmitterNames = try topologicalSort(table.emitters)

    // 2. Instantiate emitters in dependency order (shared instances by name)
    var compiledEmitters: [String: CompiledEmitter] = [:]
    for name in sortedEmitterNames {
      guard let row = table.emitters.first(where: { $0.name == name }) else { continue }
      let emitter = try compileEmitter(row, allEmitters: compiledEmitters)
      compiledEmitters[name] = emitter
    }

    // 3. Build the shared PitchHierarchy (optional)
    let hierarchy: PitchHierarchy? = table.hierarchy.map { buildHierarchy($0) }

    // 4. Compile note materials
    var compiledNoteMaterials: [String: any IteratorProtocol<[MidiNote]>] = [:]
    for noteMat in table.noteMaterials {
      let gen = try compileNoteMaterial(noteMat, emitters: compiledEmitters, hierarchy: hierarchy)
      compiledNoteMaterials[noteMat.name] = gen
    }

    // 5. Compile preset modulators (including meta-modulation)
    var compiledModulators: [String: (target: String, arrow: Arrow11)] = [:]
    for mod in table.presetModulators {
      let result = try compilePresetModulator(mod, emitters: compiledEmitters)
      compiledModulators[mod.name] = result
    }

    // 6. Compile hierarchy modulators
    var compiledHierarchyMods: [CompiledHierarchyModulator] = []
    if let hierarchy {
      for mod in table.hierarchyModulators {
        let compiled = try compileHierarchyModulator(mod, emitters: compiledEmitters, hierarchy: hierarchy)
        compiledHierarchyMods.append(compiled)
      }
    }

    // 7. Collect all emitter shadows for annotation
    var allEmitterShadows: [String: ArrowConst] = [:]
    for (name, compiled) in compiledEmitters {
      allEmitterShadows[name] = compiled.lastValueShadow
    }

    // 8. Assemble tracks
    var musicTracks: [MusicPattern.Track] = []
    var trackInfos: [TrackInfo] = []
    var spatialPresets: [SpatialPreset] = []

    for (i, trackRow) in table.tracks.enumerated() {
      let presetFileName = trackRow.presetFilename + ".json"
      let presetSpec = decodeJSON(PresetSyntax.self, from: presetFileName, subdirectory: "presets", resourceBaseURL: resourceBaseURL)
      let voices = trackRow.numVoices ?? 12
      let sp = try await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: voices, resourceBaseURL: resourceBaseURL)

      // Look up note material
      guard let notes = compiledNoteMaterials[trackRow.noteMaterial] else {
        throw TableCompileError.unknownNoteMaterial(name: trackRow.noteMaterial, referencedBy: trackRow.name)
      }

      // Look up sustain and gap emitters
      let sustainEmitter = try requireFloatEmitter(trackRow.sustainEmitter, emitters: compiledEmitters, referencedBy: trackRow.name)
      let gapEmitter = try requireFloatEmitter(trackRow.gapEmitter, emitters: compiledEmitters, referencedBy: trackRow.name)

      // Collect preset modulators
      var modDict: [String: Arrow11] = [:]
      for modName in trackRow.presetModulatorNames {
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
        name: trackRow.name,
        emitterShadows: allEmitterShadows
      ))

      trackInfos.append(TrackInfo(
        id: i,
        patternName: trackRow.name,
        trackSpec: nil,
        presetSpec: presetSpec
      ))
      spatialPresets.append(sp)
    }

    let pattern = MusicPattern(tracks: musicTracks, hierarchyModulators: compiledHierarchyMods, clock: clock)
    return PatternSyntax.CompileResult(pattern: pattern, trackInfos: trackInfos, spatialPresets: spatialPresets)
  }

  /// Compile for UI-only display (no engine, no audio nodes).
  static func compileTrackInfoOnly(_ table: TablePatternSyntax, resourceBaseURL: URL? = nil) -> [TrackInfo] {
    var infos: [TrackInfo] = []
    for (i, trackRow) in table.tracks.enumerated() {
      let presetFileName = trackRow.presetFilename + ".json"
      let presetSpec = decodeJSON(PresetSyntax.self, from: presetFileName, subdirectory: "presets", resourceBaseURL: resourceBaseURL)
      infos.append(TrackInfo(
        id: i,
        patternName: trackRow.name,
        trackSpec: nil,
        presetSpec: presetSpec
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
    case .int, .octave:
      return try compileIntEmitter(row, allEmitters: allEmitters)
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

    case .fragmentPool:
      let frags = row.fragments ?? []
      iter = FragmentPoolIterator(fragments: frags)

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
    return CompiledEmitter(outputType: row.outputType, iterator: capturing, lastValueShadow: shadow)
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

  // MARK: - Hierarchy Construction

  /// Build a PitchHierarchy from its JSON description.
  private static func buildHierarchy(_ syntax: HierarchySyntax) -> PitchHierarchy {
    let root = NoteGeneratorSyntax.resolveNoteClass(syntax.root)
    let scale = NoteGeneratorSyntax.resolveScale(syntax.scale)
    let key = Key(root: root, scale: scale)
    let chord = ChordInScale(degrees: syntax.chord.degrees, inversion: syntax.chord.inversion)
    return PitchHierarchy(key: key, chord: chord)
  }

  // MARK: - Hierarchy Modulator Compilation

  private static func compileHierarchyModulator(
    _ mod: HierarchyModulatorRowSyntax,
    emitters: [String: CompiledEmitter],
    hierarchy: PitchHierarchy
  ) throws -> CompiledHierarchyModulator {
    let intervalIter = try requireFloatEmitter(mod.fireIntervalEmitter, emitters: emitters, referencedBy: mod.name)
    return CompiledHierarchyModulator(
      hierarchy: hierarchy,
      level: mod.level,
      operation: mod.operation,
      n: mod.n,
      intervalEmitter: intervalIter
    )
  }

  // MARK: - Note Material Compilation

  private static func compileNoteMaterial(
    _ noteMat: NoteMaterialSyntax,
    emitters: [String: CompiledEmitter],
    hierarchy: PitchHierarchy?
  ) throws -> any IteratorProtocol<[MidiNote]> {
    switch noteMat {
    case .scaleMaterial(let s):
      return try compileScaleMaterial(s, emitters: emitters)
    case .hierarchyMelody(let s):
      guard let h = hierarchy else { throw TableCompileError.missingHierarchy(referencedBy: s.name) }
      return try compileHierarchyMelody(s, emitters: emitters, hierarchy: h)
    case .hierarchyChord(let s):
      guard let h = hierarchy else { throw TableCompileError.missingHierarchy(referencedBy: s.name) }
      return compileHierarchyChord(s, hierarchy: h)
    case .hierarchyBass(let s):
      guard let h = hierarchy else { throw TableCompileError.missingHierarchy(referencedBy: s.name) }
      return compileHierarchyBass(s, hierarchy: h)
    }
  }

  private static func compileScaleMaterial(
    _ noteMat: ScaleMaterialSyntax,
    emitters: [String: CompiledEmitter]
  ) throws -> any IteratorProtocol<[MidiNote]> {
    let scale = NoteGeneratorSyntax.resolveScale(noteMat.scale)
    let root = NoteGeneratorSyntax.resolveNoteClass(noteMat.root)

    guard let pickerEmitter = emitters[noteMat.intervalPickerEmitter],
          let pickerIter = pickerEmitter.intIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.intervalPickerEmitter, referencedBy: noteMat.name)
    }
    guard let octEmitter = emitters[noteMat.octaveEmitter],
          let octIter = octEmitter.intIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.octaveEmitter, referencedBy: noteMat.name)
    }

    return ScaleMaterialGenerator(
      scale: scale,
      root: root,
      intervals: noteMat.intervals,
      intervalPicker: pickerIter,
      octaveEmitter: octIter
    )
  }

  private static func compileHierarchyMelody(
    _ noteMat: HierarchyMelodySyntax,
    emitters: [String: CompiledEmitter],
    hierarchy: PitchHierarchy
  ) throws -> any IteratorProtocol<[MidiNote]> {
    guard let octEmitter = emitters[noteMat.octaveEmitter],
          let octIter = octEmitter.intIterator() else {
      throw TableCompileError.unknownEmitter(name: noteMat.octaveEmitter, referencedBy: noteMat.name)
    }
    let melodyNotes = noteMat.notes.compactMap { $0.toMelodyNote() }
    return HierarchyMelodyGenerator(
      hierarchy: hierarchy,
      level: noteMat.level,
      melodyNotes: melodyNotes,
      ordering: noteMat.ordering,
      octaveEmitter: octIter
    )
  }

  private static func compileHierarchyChord(
    _ noteMat: HierarchyChordSyntax,
    hierarchy: PitchHierarchy
  ) -> any IteratorProtocol<[MidiNote]> {
    HierarchyChordGenerator(hierarchy: hierarchy, voicing: noteMat.voicing, baseOctave: noteMat.baseOctave)
  }

  private static func compileHierarchyBass(
    _ noteMat: HierarchyBassSyntax,
    hierarchy: PitchHierarchy
  ) -> any IteratorProtocol<[MidiNote]> {
    HierarchyBassGenerator(hierarchy: hierarchy, baseOctave: noteMat.baseOctave)
  }

  // MARK: - Preset Modulator Compilation

  private static func compilePresetModulator(
    _ mod: PresetModulatorRowSyntax,
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
