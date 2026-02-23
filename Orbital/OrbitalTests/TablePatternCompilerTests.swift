//
//  TablePatternCompilerTests.swift
//  OrbitalTests
//
//  Tests for the table pattern compiler: topological sort, emitter compilation,
//  note material generation, Codable round-trips, and meta-modulation.
//

import Testing
import Foundation
import Tonic
@testable import Orbital

// MARK: - Topological Sort Tests

@Suite("Table Pattern Topological Sort", .serialized)
struct TopologicalSortTests {

  @Test("Independent emitters sort in declaration order")
  func independentEmitters() throws {
    let emitters = [
      EmitterRowSyntax(name: "A", outputType: .float, function: .randFloat, arg1: 0, arg2: 1),
      EmitterRowSyntax(name: "B", outputType: .int, function: .randInt, arg1: 0, arg2: 5),
      EmitterRowSyntax(name: "C", outputType: .float, function: .randFloat, arg1: 1, arg2: 2),
    ]
    let sorted = try TablePatternCompiler.topologicalSort(emitters)
    #expect(sorted.count == 3)
    #expect(Set(sorted) == Set(["A", "B", "C"]))
  }

  @Test("Dependent emitters sort after their dependencies")
  func dependentEmitters() throws {
    let emitters = [
      EmitterRowSyntax(name: "Sum", outputType: .float, function: .sum, inputEmitters: ["A", "B"]),
      EmitterRowSyntax(name: "A", outputType: .float, function: .randFloat, arg1: 0, arg2: 1),
      EmitterRowSyntax(name: "B", outputType: .float, function: .randFloat, arg1: 0, arg2: 1),
    ]
    let sorted = try TablePatternCompiler.topologicalSort(emitters)
    let sumIdx = sorted.firstIndex(of: "Sum")!
    let aIdx = sorted.firstIndex(of: "A")!
    let bIdx = sorted.firstIndex(of: "B")!
    #expect(aIdx < sumIdx, "A should come before Sum")
    #expect(bIdx < sumIdx, "B should come before Sum")
  }

  @Test("IndexPicker dependency is respected")
  func indexPickerDependency() throws {
    let emitters = [
      EmitterRowSyntax(name: "Roots", outputType: .root, function: .indexPicker(emitter: "Picker"),
                       candidates: ["C", "E", "G"]),
      EmitterRowSyntax(name: "Picker", outputType: .int, function: .randInt, arg1: 0, arg2: 2),
    ]
    let sorted = try TablePatternCompiler.topologicalSort(emitters)
    let rootsIdx = sorted.firstIndex(of: "Roots")!
    let pickerIdx = sorted.firstIndex(of: "Picker")!
    #expect(pickerIdx < rootsIdx)
  }

  @Test("Waiting dependency is respected")
  func waitingDependency() throws {
    let emitters = [
      EmitterRowSyntax(name: "Roots", outputType: .root, function: .cyclic,
                       candidates: ["C", "E"], updateMode: .waiting(emitter: "Timer")),
      EmitterRowSyntax(name: "Timer", outputType: .float, function: .randFloat, arg1: 5, arg2: 10),
    ]
    let sorted = try TablePatternCompiler.topologicalSort(emitters)
    let rootsIdx = sorted.firstIndex(of: "Roots")!
    let timerIdx = sorted.firstIndex(of: "Timer")!
    #expect(timerIdx < rootsIdx)
  }

  @Test("Cyclic dependency throws error")
  func cyclicDependency() throws {
    let emitters = [
      EmitterRowSyntax(name: "A", outputType: .float, function: .sum, inputEmitters: ["B"]),
      EmitterRowSyntax(name: "B", outputType: .float, function: .sum, inputEmitters: ["A"]),
    ]
    #expect(throws: TableCompileError.self) {
      _ = try TablePatternCompiler.topologicalSort(emitters)
    }
  }

  @Test("Chain of dependencies sorts correctly")
  func chainDependency() throws {
    // C depends on B, B depends on A
    let emitters = [
      EmitterRowSyntax(name: "C", outputType: .float, function: .reciprocal, inputEmitters: ["B"]),
      EmitterRowSyntax(name: "B", outputType: .float, function: .sum, inputEmitters: ["A"]),
      EmitterRowSyntax(name: "A", outputType: .float, function: .randFloat, arg1: 1, arg2: 2),
    ]
    let sorted = try TablePatternCompiler.topologicalSort(emitters)
    #expect(sorted == ["A", "B", "C"])
  }
}

// MARK: - Runtime Primitive Tests

@Suite("Table Pattern Runtime Primitives", .serialized)
struct RuntimePrimitiveTests {

  @Test("IntSampler produces values in range")
  func intSamplerRange() {
    let sampler = IntSampler(min: 3, max: 7)
    for _ in 0..<100 {
      let val = sampler.next()!
      #expect(val >= 3 && val <= 7, "IntSampler value \(val) should be in [3, 7]")
    }
  }

  @Test("FloatSampler with exponential distribution produces values in range")
  func exponentialFloatSamplerRange() {
    let sampler = FloatSampler(min: 0.001, max: 1.0, dist: .exponential)
    for _ in 0..<100 {
      let val = sampler.next()!
      #expect(val >= 0.001 && val <= 1.0,
              "Exponential FloatSampler value \(val) should be in [0.001, 1.0]")
    }
  }

  @Test("FloatSampler with exponential distribution and equal min/max returns that value")
  func exponentialDegenerateRange() {
    let sampler = FloatSampler(min: 0.5, max: 0.5, dist: .exponential)
    let val = sampler.next()!
    #expect(val == 0.5, "Exponential FloatSampler with min==max should return that value")
  }

  @Test("MutableParam updates are visible to MutableFloatSampler")
  func mutableParamUpdate() {
    let minP = MutableParam(5.0)
    let maxP = MutableParam(5.0)
    let sampler = MutableFloatSampler(minParam: minP, maxParam: maxP)
    // With min == max, should return that value
    let val = sampler.next()!
    #expect(val == 5.0, "Should return 5.0 when min==max")

    // Update params
    minP.val = 10.0
    maxP.val = 20.0
    for _ in 0..<50 {
      let v = sampler.next()!
      #expect(v >= 10.0 && v <= 20.0, "After update, value \(v) should be in [10, 20]")
    }
  }

  @Test("EmitterArrow bridges iterator to Arrow11")
  func emitterArrowBridge() {
    var values: [CoreFloat] = [1.0, 2.0, 3.0]
    let iter = values.cyclicIterator()
    let arrow = EmitterArrow(emitter: iter)
    let v1 = arrow.of(0)
    let v2 = arrow.of(0)
    let v3 = arrow.of(0)
    // Cyclic: 1, 2, 3
    #expect(v1 == 1.0)
    #expect(v2 == 2.0)
    #expect(v3 == 3.0)
  }

  @Test("SumIterator sums multiple sources")
  func sumIterator() {
    let a = [1.0, 2.0, 3.0].cyclicIterator()
    let b = [10.0, 20.0, 30.0].cyclicIterator()
    var sum = SumIterator(sources: [a, b])
    #expect(sum.next()! == 11.0)
    #expect(sum.next()! == 22.0)
    #expect(sum.next()! == 33.0)
  }

  @Test("ReciprocalIterator returns 1/x")
  func reciprocalIterator() {
    let source = [2.0, 4.0, 5.0].cyclicIterator()
    var recip = ReciprocalIterator(source: source)
    #expect(recip.next()! == 0.5)
    #expect(recip.next()! == 0.25)
    #expect(recip.next()! == 0.2)
  }

  @Test("ReciprocalIterator handles zero safely")
  func reciprocalZero() {
    let source = [0.0].cyclicIterator()
    var recip = ReciprocalIterator(source: source)
    #expect(recip.next()! == 0, "Reciprocal of 0 should return 0")
  }

  @Test("IndexPickerIterator picks by index with clamping")
  func indexPickerClamp() {
    let items = ["A", "B", "C"]
    let indices = [0, 1, 2, 5, -1].cyclicIterator()
    let picker = IndexPickerIterator(items: items, indexEmitter: indices)
    #expect(picker.next() == "A")
    #expect(picker.next() == "B")
    #expect(picker.next() == "C")
    #expect(picker.next() == "C") // clamped from 5
    #expect(picker.next() == "A") // clamped from -1
  }

  @Test("LatchingIterator returns same value within latch window")
  func latchingWithinWindow() {
    var counter = 0
    let counting = AnyIterator<Int> {
      counter += 1
      return counter
    }
    let latching = LatchingIterator(inner: counting, latchDuration: 1.0)
    let v1 = latching.next()!
    let v2 = latching.next()! // Should still be within the 1s window
    #expect(v1 == v2, "Within latch window, should return same value")
    #expect(v1 == 1, "First call should advance to 1")
  }

  @Test("LatchingIterator advances after latch window expires")
  func latchingAfterExpiry() {
    var counter = 0
    let counting = AnyIterator<Int> {
      counter += 1
      return counter
    }
    // Very short latch so it expires immediately
    let latching = LatchingIterator(inner: counting, latchDuration: 0)
    let v1 = latching.next()!
    // Even with latch=0, two calls in rapid succession might still latch.
    // Sleep a tiny bit to ensure expiry.
    Thread.sleep(forTimeInterval: 0.001)
    let v2 = latching.next()!
    #expect(v2 > v1, "After latch expires, should advance: v1=\(v1), v2=\(v2)")
  }
}

// MARK: - Note Material Tests

@Suite("Table Pattern Note Material", .serialized)
struct NoteMaterialTests {

  @Test("TableNoteGenerator produces single-note melodies")
  func singleNoteMelody() {
    var gen = TableNoteGenerator(
      intervalMaterial: [[0], [1], [2], [3], [4], [5], [6]],
      intervalPicker: [0, 1, 2].cyclicIterator(),
      scaleEmitter: [Scale.major].cyclicIterator(),
      rootEmitter: [NoteClass.C].cyclicIterator(),
      octaveEmitter: [4].cyclicIterator()
    )

    for _ in 0..<10 {
      let notes = gen.next()!
      #expect(notes.count == 1, "Single-degree interval should produce one note")
      #expect(notes[0].note <= 127, "MIDI note should be <= 127")
      #expect(notes[0].velocity == 127)
    }
  }

  @Test("TableNoteGenerator produces chords from multi-degree intervals")
  func chordGeneration() {
    var gen = TableNoteGenerator(
      intervalMaterial: [[0, 2, 4]], // single chord: root, third, fifth
      intervalPicker: [0].cyclicIterator(),
      scaleEmitter: [Scale.major].cyclicIterator(),
      rootEmitter: [NoteClass.C].cyclicIterator(),
      octaveEmitter: [4].cyclicIterator()
    )

    let chord = gen.next()!
    #expect(chord.count == 3, "Triad should produce 3 notes, got \(chord.count)")
    // C major triad in octave 4 (Tonic uses C4 = 72)
    // C4 = 72, E4 = 76, G4 = 79
    let pitches = chord.map { Int($0.note) }
    #expect(pitches[0] == 72, "Root should be C4 (72), got \(pitches[0])")
    #expect(pitches[1] == 76, "Third should be E4 (76), got \(pitches[1])")
    #expect(pitches[2] == 79, "Fifth should be G4 (79), got \(pitches[2])")
  }

  @Test("TableNoteGenerator respects changing root")
  func changingRoot() {
    var gen = TableNoteGenerator(
      intervalMaterial: [[0]], // just the root degree
      intervalPicker: [0].cyclicIterator(),
      scaleEmitter: [Scale.major].cyclicIterator(),
      rootEmitter: [NoteClass.C, NoteClass.E, NoteClass.G].cyclicIterator(),
      octaveEmitter: [4].cyclicIterator()
    )

    let note1 = gen.next()![0] // C4
    let note2 = gen.next()![0] // E4
    let note3 = gen.next()![0] // G4
    #expect(note1.note != note2.note, "Different roots should produce different notes")
    #expect(note2.note != note3.note, "Different roots should produce different notes")
    #expect(Int(note1.note) == 72, "C4 = 72 (Tonic convention)")
    #expect(Int(note2.note) == 76, "E4 = 76 (Tonic convention)")
    #expect(Int(note3.note) == 79, "G4 = 79 (Tonic convention)")
  }

  @Test("TableNoteGenerator clamps out-of-range degree index")
  func clampsDegreeIndex() {
    var gen = TableNoteGenerator(
      intervalMaterial: [[0], [2], [4]],
      intervalPicker: [99].cyclicIterator(), // way out of range
      scaleEmitter: [Scale.major].cyclicIterator(),
      rootEmitter: [NoteClass.C].cyclicIterator(),
      octaveEmitter: [4].cyclicIterator()
    )

    let notes = gen.next()!
    #expect(notes.count == 1, "Should still produce a note despite clamped index")
  }
}

// MARK: - Codable Round-Trip Tests

@Suite("Table Pattern Codable", .serialized)
struct CodableTests {

  @Test("EmitterFunction round-trips for simple cases")
  func emitterFunctionSimple() throws {
    let cases: [EmitterFunction] = [
      .randFloat, .exponentialRandFloat, .randInt,
      .shuffle, .cyclic, .random, .sum, .reciprocal
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for fn in cases {
      let data = try encoder.encode(fn)
      let decoded = try decoder.decode(EmitterFunction.self, from: data)
      #expect(decoded == fn, "Round-trip failed for \(fn)")
    }
  }

  @Test("EmitterFunction round-trips for indexPicker")
  func emitterFunctionIndexPicker() throws {
    let fn = EmitterFunction.indexPicker(emitter: "myPicker")
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(fn)
    let decoded = try decoder.decode(EmitterFunction.self, from: data)
    #expect(decoded == fn)
  }

  @Test("EmitterUpdateMode round-trips")
  func updateModeRoundTrip() throws {
    let cases: [EmitterUpdateMode] = [.each, .waiting(emitter: "timer")]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for mode in cases {
      let data = try encoder.encode(mode)
      let decoded = try decoder.decode(EmitterUpdateMode.self, from: data)
      #expect(decoded == mode, "Round-trip failed for \(mode)")
    }
  }

  @Test("EmitterRowSyntax round-trips with optional fields")
  func emitterRowRoundTrip() throws {
    let row = EmitterRowSyntax(
      name: "test",
      outputType: .float,
      function: .randFloat,
      arg1: 1.0,
      arg2: 5.0,
      updateMode: .each
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(row)
    let decoded = try decoder.decode(EmitterRowSyntax.self, from: data)
    #expect(decoded.name == row.name)
    #expect(decoded.outputType == row.outputType)
    #expect(decoded.function == row.function)
    #expect(decoded.arg1 == row.arg1)
    #expect(decoded.arg2 == row.arg2)
    #expect(decoded.updateMode == row.updateMode)
  }

  @Test("EmitterRowSyntax decodes with default id when absent")
  func emitterRowDefaultId() throws {
    let json = """
    {"name":"X","outputType":"float","function":"randFloat","arg1":0,"arg2":1}
    """
    let decoded = try JSONDecoder().decode(EmitterRowSyntax.self, from: Data(json.utf8))
    #expect(decoded.name == "X")
    #expect(decoded.updateMode == .each, "Default updateMode should be .each")
  }

  @Test("NoteMaterialRowSyntax round-trips")
  func noteMaterialRoundTrip() throws {
    let row = NoteMaterialRowSyntax(
      name: "melody",
      intervalMaterial: [[0], [1], [0, 2, 4]],
      intervalPicker: "picker",
      octaveEmitter: "oct",
      scaleEmitter: "scale",
      scaleRootEmitter: "root"
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(row)
    let decoded = try decoder.decode(NoteMaterialRowSyntax.self, from: data)
    #expect(decoded.name == row.name)
    #expect(decoded.intervalMaterial == row.intervalMaterial)
    #expect(decoded.intervalPicker == row.intervalPicker)
    #expect(decoded.octaveEmitter == row.octaveEmitter)
    #expect(decoded.scaleEmitter == row.scaleEmitter)
    #expect(decoded.scaleRootEmitter == row.scaleRootEmitter)
  }

  @Test("TablePatternSyntax full round-trip")
  func fullTableRoundTrip() throws {
    let table = TablePatternSyntax(
      name: "Test Pattern",
      emitters: [
        EmitterRowSyntax(name: "gap", outputType: .float, function: .randFloat, arg1: 0.2, arg2: 0.5),
        EmitterRowSyntax(name: "sustain", outputType: .float, function: .randFloat, arg1: 1, arg2: 3),
        EmitterRowSyntax(name: "picker", outputType: .int, function: .randInt, arg1: 0, arg2: 2),
        EmitterRowSyntax(name: "oct", outputType: .octave, function: .random, candidates: ["3", "4"]),
        EmitterRowSyntax(name: "scale", outputType: .scale, function: .cyclic, candidates: ["lydian"]),
        EmitterRowSyntax(name: "root", outputType: .root, function: .cyclic, candidates: ["C"]),
      ],
      noteMaterials: [
        NoteMaterialRowSyntax(
          name: "melody",
          intervalMaterial: [[0], [1], [2]],
          intervalPicker: "picker",
          octaveEmitter: "oct",
          scaleEmitter: "scale",
          scaleRootEmitter: "root"
        )
      ],
      modulators: [],
      tracks: [
        TrackAssemblyRowSyntax(
          name: "Track 0",
          presetFilename: "auroraBorealis",
          noteMaterial: "melody",
          sustainEmitter: "sustain",
          gapEmitter: "gap"
        )
      ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(table)
    let decoded = try JSONDecoder().decode(TablePatternSyntax.self, from: data)
    #expect(decoded.name == table.name)
    #expect(decoded.emitters.count == table.emitters.count)
    #expect(decoded.noteMaterials.count == table.noteMaterials.count)
    #expect(decoded.modulators.count == table.modulators.count)
    #expect(decoded.tracks.count == table.tracks.count)
    #expect(decoded.tracks[0].presetFilename == "auroraBorealis")
  }
}

// MARK: - Meta-Modulation Tests

@Suite("Table Pattern Meta-Modulation", .serialized)
struct MetaModulationTests {

  @Test("MetaModulationArrow writes source value to target MutableParam")
  func metaModulationWritesToParam() {
    let source = [0.5, 0.7, 0.9].cyclicIterator()
    let target = MutableParam(0.0)
    let arrow = MetaModulationArrow(source: source, target: target)

    let _ = arrow.of(0)
    #expect(abs(target.val - 0.5) < 0.001)

    let _ = arrow.of(0)
    #expect(abs(target.val - 0.7) < 0.001)

    let _ = arrow.of(0)
    #expect(abs(target.val - 0.9) < 0.001)
  }

  @Test("MutableFloatSampler responds to MutableParam changes from MetaModulationArrow")
  func metaModulationEndToEnd() {
    let minP = MutableParam(0.0)
    let maxP = MutableParam(0.1)
    let sampler = MutableFloatSampler(minParam: minP, maxParam: maxP)

    // Initial range: [0, 0.1]
    for _ in 0..<20 {
      let v = sampler.next()!
      #expect(v >= 0.0 && v <= 0.1, "Value \(v) should be in [0, 0.1]")
    }

    // Simulate meta-modulation: change max to 100
    let modSource = [100.0].cyclicIterator()
    let arrow = MetaModulationArrow(source: modSource, target: maxP)
    let _ = arrow.of(0) // This writes 100.0 to maxP

    // Now sampler should use range [0, 100]
    var sawLargeValue = false
    for _ in 0..<200 {
      let v = sampler.next()!
      #expect(v >= 0.0 && v <= 100.0, "Value \(v) should be in [0, 100]")
      if v > 0.1 { sawLargeValue = true }
    }
    #expect(sawLargeValue, "After meta-modulation, should see values > 0.1")
  }
}

// MARK: - IntToFloatIterator Tests

@Suite("IntToFloatIterator", .serialized)
struct IntToFloatIteratorTests {

  @Test("IntToFloatIterator converts Int to CoreFloat")
  func convertsIntToFloat() {
    let ints = [1, 2, 3].cyclicIterator()
    var adapter = IntToFloatIterator(source: ints)
    #expect(adapter.next()! == 1.0)
    #expect(adapter.next()! == 2.0)
    #expect(adapter.next()! == 3.0)
  }
}
// MARK: - CapturingIterator Tests

@Suite("CapturingIterator")
struct CapturingIteratorTests {

  @Test("CapturingIterator updates shadow ArrowConst on each next()")
  func updatesShadowOnNext() {
    let shadow = ArrowConst(value: 0)
    let inner: any IteratorProtocol<Int> = [10, 20, 30].cyclicIterator()
    let capturing = CapturingIterator(inner: inner, shadow: shadow, toFloat: { CoreFloat($0) })
    #expect(shadow.val == 0, "Shadow starts at 0")

    let v1 = capturing.next()
    #expect(v1 == 10)
    #expect(shadow.val == 10.0, "Shadow updated to 10 after first next()")

    let v2 = capturing.next()
    #expect(v2 == 20)
    #expect(shadow.val == 20.0, "Shadow updated to 20 after second next()")
  }

  @Test("CapturingIterator preserves original element type")
  func preservesElementType() {
    let shadow = ArrowConst(value: 0)
    let inner: any IteratorProtocol<CoreFloat> = [3.5, 7.25].cyclicIterator()
    let capturing = CapturingIterator(inner: inner, shadow: shadow, toFloat: { $0 })

    let v = capturing.next()!
    #expect(v == 3.5)
    #expect(shadow.val == 3.5)
  }
}

// MARK: - ArrowConst ForwardTo Tests

@Suite("ArrowConst ForwardTo")
struct ArrowConstForwardToTests {

  @Test("ArrowConst without forwardTo reads own val")
  func readsOwnVal() {
    let c = ArrowConst(value: 42.0)
    #expect(c.effectiveVal == 42.0)
  }

  @Test("ArrowConst with forwardTo reads forwarded val")
  func readsForwardedVal() {
    let source = ArrowConst(value: 99.0)
    let placeholder = ArrowConst(value: 0)
    placeholder.forwardTo = source
    #expect(placeholder.effectiveVal == 99.0)

    // process() should also use the forwarded value
    let inputs: [CoreFloat] = [0, 0, 0]
    var outputs: [CoreFloat] = [0, 0, 0]
    placeholder.process(inputs: inputs, outputs: &outputs)
    #expect(outputs == [99.0, 99.0, 99.0])

    // Updating source's val should be reflected
    source.val = 50.0
    #expect(placeholder.effectiveVal == 50.0)
  }
}

// MARK: - Arrow Modulator Tests

@Suite("Arrow-Based Modulators")
struct ArrowModulatorTests {

  @Test("emitterValue compiles to ArrowConst registered in namedEmitterValues")
  func emitterValueCompiles() {
    let syntax = ArrowSyntax.emitterValue(name: "octaves")
    let compiled = syntax.compile()
    #expect(compiled.namedEmitterValues["octaves"]?.count == 1)
    // The ArrowConst should start at 0
    #expect(compiled.namedEmitterValues["octaves"]?.first?.val == 0)
  }

  @Test("emitterValue with forwardTo reads captured emitter value")
  func emitterValueReadsCapture() {
    // Simulate what compileModulator does:
    // 1. Create shadow (as CapturingIterator would)
    let shadow = ArrowConst(value: 3.0) // simulates octave = 3

    // 2. Compile an arrow: reciprocal(sum(const(1), emitterValue("oct")))
    let syntax = ArrowSyntax.reciprocal(
      of: .sum(of: [
        .const(name: "one", val: 1.0),
        .emitterValue(name: "oct")
      ])
    )
    let compiled = syntax.compile()

    // 3. Wire the placeholder to the shadow
    for placeholder in compiled.namedEmitterValues["oct"] ?? [] {
      placeholder.forwardTo = shadow
    }

    // 4. Evaluate: should compute 1 / (1 + 3) = 0.25
    let result = compiled.of(0)
    #expect(abs(result - 0.25) < 0.001, "Expected 0.25, got \(result)")

    // 5. Update shadow and re-evaluate: 1 / (1 + 4) = 0.2
    shadow.val = 4.0
    let result2 = compiled.of(0)
    #expect(abs(result2 - 0.2) < 0.001, "Expected 0.2, got \(result2)")
  }

  @Test("namedEmitterValues merges through recursive compilation")
  func emitterValuesMerge() {
    // A sum that contains two emitterValue references
    let syntax = ArrowSyntax.sum(of: [
      .emitterValue(name: "a"),
      .emitterValue(name: "b")
    ])
    let compiled = syntax.compile()
    #expect(compiled.namedEmitterValues["a"]?.count == 1)
    #expect(compiled.namedEmitterValues["b"]?.count == 1)
  }

  @Test("table_aurora.json decodes successfully with arrow modulator")
  func tableAuroraDecodes() throws {
    let pattern = Bundle.main.decode(PatternSyntax.self, from: "table_aurora.json", subdirectory: "patterns")
    let table = try #require(pattern.tableTracks)
    // Find the arrow-based modulator
    let octaveMod = table.modulators.first(where: { $0.name == "octaveAmpMod" })
    #expect(octaveMod != nil, "Should find octaveAmpMod modulator")
    #expect(octaveMod?.arrow != nil, "octaveAmpMod should have an arrow")
    #expect(octaveMod?.floatEmitter == nil, "octaveAmpMod should not have a floatEmitter")
    #expect(octaveMod?.targetHandle == "overallAmp2")
  }
}


