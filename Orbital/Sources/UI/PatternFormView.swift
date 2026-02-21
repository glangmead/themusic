//
//  PatternFormView.swift
//  Orbital

import SwiftUI
import Tonic

// MARK: - Helper State Types

/// Bridges TimingSyntax (immutable, Codable) to editable UI state.
struct TimingState: Equatable {
  enum Kind: String, CaseIterable { case fixed, random, list }
  var kind: Kind
  var fixedValue: CoreFloat
  var randomMin: CoreFloat
  var randomMax: CoreFloat
  var listValues: [CoreFloat]

  init(from syntax: TimingSyntax?) {
    switch syntax {
    case .fixed(let value):
      kind = .fixed; fixedValue = value; randomMin = 0.5; randomMax = 2.0; listValues = [value]
    case .random(let min, let max):
      kind = .random; fixedValue = 1.0; randomMin = min; randomMax = max; listValues = [min, max]
    case .list(let values):
      kind = .list; fixedValue = 1.0; randomMin = 0.5; randomMax = 2.0; listValues = values
    case nil:
      kind = .fixed; fixedValue = 1.0; randomMin = 0.5; randomMax = 2.0; listValues = [1.0]
    }
  }

  func toSyntax() -> TimingSyntax? {
    switch kind {
    case .fixed:  return .fixed(value: fixedValue)
    case .random: return .random(min: randomMin, max: randomMax)
    case .list:   return listValues.isEmpty ? nil : .list(values: listValues)
    }
  }
}



/// Arrow types supported in the modulator editor UI.
enum SimpleArrowType: String, CaseIterable, Identifiable {
  case rand = "Random"
  case exponentialRand = "Exponential Random"
  case const = "Constant"
  case reciprocalConst = "Reciprocal Constant"
  case noiseSmoothStep = "Noise Smooth Step"
  case line = "Line"
  case eventNote = "Event Note"
  case eventVelocity = "Event Velocity"
  var id: String { rawValue }
}

/// Bridges ModulatorSyntax to editable UI state.
struct ModulatorState: Identifiable, Equatable {
  let id: UUID
  var target: String
  var arrowType: SimpleArrowType
  var min: CoreFloat
  var max: CoreFloat
  var constValue: CoreFloat
  var noiseDuration: CoreFloat
  var lineDuration: CoreFloat

  init(from syntax: ModulatorSyntax) {
    id = UUID()
    target = syntax.target
    switch syntax.arrow {
    case .rand(let lo, let hi):
      arrowType = .rand; min = lo; max = hi; constValue = lo; noiseDuration = 1; lineDuration = 1
    case .exponentialRand(let lo, let hi):
      arrowType = .exponentialRand; min = lo; max = hi; constValue = lo; noiseDuration = 1; lineDuration = 1
    case .const(_, let val):
      arrowType = .const; min = 0; max = 1; constValue = val; noiseDuration = 1; lineDuration = 1
    case .reciprocalConst(_, let val):
      arrowType = .reciprocalConst; min = 0; max = 1; constValue = val; noiseDuration = 1; lineDuration = 1
    case .eventNote:
      arrowType = .eventNote; min = 0; max = 127; constValue = 0; noiseDuration = 1; lineDuration = 1
    case .eventVelocity:
      arrowType = .eventVelocity; min = 0; max = 1; constValue = 0; noiseDuration = 1; lineDuration = 1
    case .noiseSmoothStep(let freq, let lo, let hi):
      arrowType = .noiseSmoothStep; min = lo; max = hi; constValue = 0; noiseDuration = freq; lineDuration = 1
    case .line(let dur, let lo, let hi):
      arrowType = .line; min = lo; max = hi; constValue = 0; noiseDuration = 1; lineDuration = dur
    default:
      arrowType = .rand; min = 0; max = 1; constValue = 0.5; noiseDuration = 1; lineDuration = 1
    }
  }

  init() {
    id = UUID()
    target = "overallAmp"
    arrowType = .rand
    min = 0
    max = 1
    constValue = 0.5
    noiseDuration = 1
    lineDuration = 1
  }

  func toSyntax() -> ModulatorSyntax {
    let arrow: ArrowSyntax
    switch arrowType {
    case .rand:            arrow = .rand(min: min, max: max)
    case .exponentialRand: arrow = .exponentialRand(min: min, max: max)
    case .const:           arrow = .const(name: target, val: constValue)
    case .reciprocalConst: arrow = .reciprocalConst(name: target, val: constValue)
    case .noiseSmoothStep: arrow = .noiseSmoothStep(noiseFreq: noiseDuration, min: min, max: max)
    case .line:            arrow = .line(duration: lineDuration, min: min, max: max)
    case .eventNote:       arrow = .eventNote
    case .eventVelocity:   arrow = .eventVelocity
    }
    return ModulatorSyntax(target: target, arrow: arrow)
  }
}

// MARK: - PatternFormView

struct PatternFormView: View {
  @Environment(SongPlaybackState.self) private var playbackState
  let track: TrackInfo

  // Top-level state
  @State private var generatorType: GeneratorType
  @State private var name: String
  @State private var presetFilename: String
  @State private var numVoices: Int
  @State private var sustain: TimingState
  @State private var gap: TimingState
  @State private var modulators: [ModulatorState]

  // Melodic state
  @State private var scaleNames: [String]
  @State private var scaleEmission: IteratorSyntax
  @State private var rootNames: [String]
  @State private var rootEmission: IteratorSyntax
  @State private var octaves: [Int]
  @State private var octaveEmission: IteratorSyntax
  @State private var degrees: [Int]
  @State private var degreeEmission: IteratorSyntax
  @State private var defaultOrdering: IteratorSyntax

  // ScaleSampler state
  @State private var ssScaleName: String
  @State private var ssRootName: String
  @State private var ssOctaves: [Int]

  // ChordProgression state
  @State private var cpScale: String
  @State private var cpRoot: String
  @State private var cpStyle: String

  // Fixed state
  @State private var fixedEvents: [ChordSyntax]

  // MidiFile state
  @State private var midiFilename: String
  @State private var midiTrack: Int?
  @State private var midiLoop: Bool

  init(track: TrackInfo) {
    self.track = track
    let spec = track.trackSpec ?? ProceduralTrackSyntax(
      name: track.patternName,
      presetFilename: "",
      numVoices: nil,
      noteGenerator: .fixed(events: []),
      sustain: nil,
      gap: nil,
      modulators: nil
    )

    _generatorType = State(initialValue: spec.noteGenerator.generatorType)
    _name = State(initialValue: spec.name)
    _presetFilename = State(initialValue: spec.presetFilename)
    _numVoices = State(initialValue: spec.numVoices ?? 12)
    _sustain = State(initialValue: TimingState(from: spec.sustain))
    _gap = State(initialValue: TimingState(from: spec.gap))
    _modulators = State(initialValue: (spec.modulators ?? []).map { ModulatorState(from: $0) })

    // Initialize all generator-specific state from the current spec
    switch spec.noteGenerator {
    case .melodic(let scales, let roots, let octs, let degs, let ordering):
      _scaleNames = State(initialValue: scales.candidates)
      _scaleEmission = State(initialValue: scales.emission ?? .cyclic)
      _rootNames = State(initialValue: roots.candidates)
      _rootEmission = State(initialValue: roots.emission ?? .cyclic)
      _octaves = State(initialValue: octs.candidates)
      _octaveEmission = State(initialValue: octs.emission ?? .cyclic)
      _degrees = State(initialValue: degs.candidates)
      _degreeEmission = State(initialValue: degs.emission ?? .cyclic)
      _defaultOrdering = State(initialValue: ordering ?? .shuffled)
      _ssScaleName = State(initialValue: "Major")
      _ssRootName = State(initialValue: "C")
      _ssOctaves = State(initialValue: [3, 4, 5])
      _cpScale = State(initialValue: "Major")
      _cpRoot = State(initialValue: "C")
      _cpStyle = State(initialValue: "baroque")
      _fixedEvents = State(initialValue: [])
      _midiFilename = State(initialValue: "")
      _midiTrack = State(initialValue: nil)
      _midiLoop = State(initialValue: true)

    case .scaleSampler(let scale, let root, let octs):
      _ssScaleName = State(initialValue: scale)
      _ssRootName = State(initialValue: root)
      _ssOctaves = State(initialValue: octs ?? [3, 4, 5])
      // Defaults for others
      _scaleNames = State(initialValue: ["Major"])
      _scaleEmission = State(initialValue: .cyclic)
      _rootNames = State(initialValue: ["C"])
      _rootEmission = State(initialValue: .cyclic)
      _octaves = State(initialValue: [4])
      _octaveEmission = State(initialValue: .cyclic)
      _degrees = State(initialValue: [1, 3, 5])
      _degreeEmission = State(initialValue: .cyclic)
      _defaultOrdering = State(initialValue: .shuffled)
      _cpScale = State(initialValue: "Major")
      _cpRoot = State(initialValue: "C")
      _cpStyle = State(initialValue: "baroque")
      _fixedEvents = State(initialValue: [])
      _midiFilename = State(initialValue: "")
      _midiTrack = State(initialValue: nil)
      _midiLoop = State(initialValue: true)

    case .chordProgression(let scale, let root, let style):
      _cpScale = State(initialValue: scale)
      _cpRoot = State(initialValue: root)
      _cpStyle = State(initialValue: style ?? "baroque")
      // Defaults for others
      _scaleNames = State(initialValue: ["Major"])
      _scaleEmission = State(initialValue: .cyclic)
      _rootNames = State(initialValue: ["C"])
      _rootEmission = State(initialValue: .cyclic)
      _octaves = State(initialValue: [4])
      _octaveEmission = State(initialValue: .cyclic)
      _degrees = State(initialValue: [1, 3, 5])
      _degreeEmission = State(initialValue: .cyclic)
      _defaultOrdering = State(initialValue: .shuffled)
      _ssScaleName = State(initialValue: "Major")
      _ssRootName = State(initialValue: "C")
      _ssOctaves = State(initialValue: [3, 4, 5])
      _fixedEvents = State(initialValue: [])
      _midiFilename = State(initialValue: "")
      _midiTrack = State(initialValue: nil)
      _midiLoop = State(initialValue: true)

    case .fixed(let events):
      _fixedEvents = State(initialValue: events)
      // Defaults for others
      _scaleNames = State(initialValue: ["Major"])
      _scaleEmission = State(initialValue: .cyclic)
      _rootNames = State(initialValue: ["C"])
      _rootEmission = State(initialValue: .cyclic)
      _octaves = State(initialValue: [4])
      _octaveEmission = State(initialValue: .cyclic)
      _degrees = State(initialValue: [1, 3, 5])
      _degreeEmission = State(initialValue: .cyclic)
      _defaultOrdering = State(initialValue: .shuffled)
      _ssScaleName = State(initialValue: "Major")
      _ssRootName = State(initialValue: "C")
      _ssOctaves = State(initialValue: [3, 4, 5])
      _cpScale = State(initialValue: "Major")
      _cpRoot = State(initialValue: "C")
      _cpStyle = State(initialValue: "baroque")
      _midiFilename = State(initialValue: "")
      _midiTrack = State(initialValue: nil)
      _midiLoop = State(initialValue: true)

    case .midiFile(let filename, let trackNum, let loop):
      _midiFilename = State(initialValue: filename)
      _midiTrack = State(initialValue: trackNum)
      _midiLoop = State(initialValue: loop ?? true)
      // Defaults for others
      _scaleNames = State(initialValue: ["Major"])
      _scaleEmission = State(initialValue: .cyclic)
      _rootNames = State(initialValue: ["C"])
      _rootEmission = State(initialValue: .cyclic)
      _octaves = State(initialValue: [4])
      _octaveEmission = State(initialValue: .cyclic)
      _degrees = State(initialValue: [1, 3, 5])
      _degreeEmission = State(initialValue: .cyclic)
      _defaultOrdering = State(initialValue: .shuffled)
      _ssScaleName = State(initialValue: "Major")
      _ssRootName = State(initialValue: "C")
      _ssOctaves = State(initialValue: [3, 4, 5])
      _cpScale = State(initialValue: "Major")
      _cpRoot = State(initialValue: "C")
      _cpStyle = State(initialValue: "baroque")
      _fixedEvents = State(initialValue: [])
    }
  }

  var body: some View {
    Form {
      generatorTypeSection
      noteGeneratorSection
      timingSection
      modulatorsSection
      presetSection
    }
    .navigationTitle(name)
    .toolbar {
      ToolbarItemGroup {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
        Button {
          playbackState.restart()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
        Button {
          savePattern()
        } label: {
          Image(systemName: "square.and.arrow.down")
        }
      }
    }
    .onDisappear {
      applyChanges()
    }
  }

  // MARK: - Generator Type Picker

  @ViewBuilder
  private var generatorTypeSection: some View {
    Section("Generator Type") {
      Picker("Type", selection: $generatorType) {
        ForEach(GeneratorType.allCases) { type in
          Text(type.rawValue).tag(type)
        }
      }
      .onChange(of: generatorType) { oldValue, newValue in
        if oldValue != newValue {
          resetGeneratorState(for: newValue)
        }
      }
    }
  }

  // MARK: - Note Generator Section

  @ViewBuilder
  private var noteGeneratorSection: some View {
    switch generatorType {
    case .melodic:          melodicSection
    case .scaleSampler:     scaleSamplerSection
    case .chordProgression: chordProgressionSection
    case .fixed:            fixedSection
    case .midiFile:         midiFileSection
    }
  }

  // MARK: - Melodic

  @ViewBuilder
  private var melodicSection: some View {
    Section("Scales") {
      ForEach(Array(scaleNames.enumerated()), id: \.offset) { i, _ in
        Picker("Scale \(i + 1)", selection: $scaleNames[i]) {
          ForEach(NoteGeneratorSyntax.allScales, id: \.name) { entry in
            Text(entry.name).tag(entry.name)
          }
        }
      }
      .onDelete { scaleNames.remove(atOffsets: $0) }
      .onMove { scaleNames.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Scale") { scaleNames.append("Major") }
      emissionPicker(selection: $scaleEmission)
    }

    Section("Roots") {
      ForEach(Array(rootNames.enumerated()), id: \.offset) { i, _ in
        Picker("Root \(i + 1)", selection: $rootNames[i]) {
          ForEach(NoteGeneratorSyntax.allNoteClasses, id: \.name) { entry in
            Text(entry.name).tag(entry.name)
          }
        }
      }
      .onDelete { rootNames.remove(atOffsets: $0) }
      .onMove { rootNames.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Root") { rootNames.append("C") }
      emissionPicker(selection: $rootEmission)
    }

    Section("Octaves") {
      ForEach(Array(octaves.enumerated()), id: \.offset) { i, _ in
        Stepper("Octave: \(octaves[i])", value: $octaves[i], in: 0...8)
      }
      .onDelete { octaves.remove(atOffsets: $0) }
      .onMove { octaves.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Octave") { octaves.append(4) }
      emissionPicker(selection: $octaveEmission)
    }

    Section("Degrees") {
      ForEach(Array(degrees.enumerated()), id: \.offset) { i, _ in
        Stepper("Degree: \(degrees[i])", value: $degrees[i], in: 0...11)
      }
      .onDelete { degrees.remove(atOffsets: $0) }
      .onMove { degrees.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Degree") { degrees.append(1) }
      emissionPicker(selection: $degreeEmission)
    }

    Section("Default Ordering") {
      emissionPicker(selection: $defaultOrdering)
    }
  }

  // MARK: - Scale Sampler

  @ViewBuilder
  private var scaleSamplerSection: some View {
    Section("Scale Sampler") {
      Picker("Scale", selection: $ssScaleName) {
        ForEach(NoteGeneratorSyntax.allScales, id: \.name) { entry in
          Text(entry.name).tag(entry.name)
        }
      }
      Picker("Root", selection: $ssRootName) {
        ForEach(NoteGeneratorSyntax.allNoteClasses, id: \.name) { entry in
          Text(entry.name).tag(entry.name)
        }
      }
      ForEach(Array(ssOctaves.enumerated()), id: \.offset) { i, _ in
        Stepper("Octave: \(ssOctaves[i])", value: $ssOctaves[i], in: 0...8)
      }
      .onDelete { ssOctaves.remove(atOffsets: $0) }
      .onMove { ssOctaves.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Octave") { ssOctaves.append(4) }
    }
  }

  // MARK: - Chord Progression

  @ViewBuilder
  private var chordProgressionSection: some View {
    Section("Chord Progression") {
      Picker("Scale", selection: $cpScale) {
        ForEach(NoteGeneratorSyntax.allScales, id: \.name) { entry in
          Text(entry.name).tag(entry.name)
        }
      }
      Picker("Root", selection: $cpRoot) {
        ForEach(NoteGeneratorSyntax.allNoteClasses, id: \.name) { entry in
          Text(entry.name).tag(entry.name)
        }
      }
      TextField("Style", text: $cpStyle)
    }
  }

  // MARK: - Fixed

  @ViewBuilder
  private var fixedSection: some View {
    Section("Fixed Chords") {
      ForEach(Array(fixedEvents.enumerated()), id: \.offset) { i, chord in
        DisclosureGroup("Chord \(i + 1) — \(chord.notes.count) note\(chord.notes.count == 1 ? "" : "s")") {
          ForEach(Array(chord.notes.enumerated()), id: \.offset) { j, note in
            HStack {
              Text("MIDI \(note.midi)")
              Spacer()
              Text("vel \(note.velocity ?? 127)")
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .onDelete { fixedEvents.remove(atOffsets: $0) }
      .onMove { fixedEvents.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Chord") {
        fixedEvents.append(ChordSyntax(notes: [NoteSyntax(midi: 60, velocity: 100)]))
      }
    }
  }

  // MARK: - MIDI File

  @ViewBuilder
  private var midiFileSection: some View {
    Section("MIDI File") {
      LabeledContent("File", value: (midiFilename as NSString).lastPathComponent)
      if let t = midiTrack {
        Stepper("Track: \(t)", value: Binding(
          get: { midiTrack ?? 0 },
          set: { midiTrack = $0 }
        ), in: 0...32)
      }
      Toggle("Loop", isOn: $midiLoop)
    }
  }

  // MARK: - Timing Section

  @ViewBuilder
  private var timingSection: some View {
    Section("Sustain") {
      timingEditor(state: $sustain)
    }
    Section("Gap") {
      timingEditor(state: $gap)
    }
  }

  @ViewBuilder
  private func timingEditor(state: Binding<TimingState>) -> some View {
    Picker("Type", selection: state.kind) {
      ForEach(TimingState.Kind.allCases, id: \.self) { kind in
        Text(kind.rawValue.capitalized).tag(kind)
      }
    }

    switch state.wrappedValue.kind {
    case .fixed:
      SliderWithField(label: "Value", value: state.fixedValue, range: 0.01...10.0)
    case .random:
      SliderWithField(label: "Min", value: state.randomMin, range: 0.01...10.0)
      SliderWithField(label: "Max", value: state.randomMax, range: 0.01...10.0)
    case .list:
      ForEach(Array(state.wrappedValue.listValues.enumerated()), id: \.offset) { i, _ in
        SliderWithField(label: "Value \(i + 1)", value: state.listValues[i], range: 0.01...10.0)
      }
      .onDelete { state.wrappedValue.listValues.remove(atOffsets: $0) }
      Button("Add Value") { state.wrappedValue.listValues.append(1.0) }
    }
  }

  // MARK: - Modulators Section

  @ViewBuilder
  private var modulatorsSection: some View {
    Section("Modulators") {
      ForEach(Array(modulators.enumerated()), id: \.element.id) { i, _ in
        modulatorRow(index: i)
      }
      .onDelete { modulators.remove(atOffsets: $0) }
      .onMove { modulators.move(fromOffsets: $0, toOffset: $1) }
      Button("Add Modulator") {
        modulators.append(ModulatorState())
      }
    }
  }

  @ViewBuilder
  private func modulatorRow(index i: Int) -> some View {
    DisclosureGroup(modulators[i].target.isEmpty ? "Modulator \(i + 1)" : modulators[i].target) {
      TextField("Target", text: $modulators[i].target)
      Picker("Type", selection: $modulators[i].arrowType) {
        ForEach(SimpleArrowType.allCases) { type in
          Text(type.rawValue).tag(type)
        }
      }

      switch modulators[i].arrowType {
      case .const:
        SliderWithField(label: "Value", value: $modulators[i].constValue, range: 0...2)
      case .rand, .exponentialRand:
        SliderWithField(label: "Min", value: $modulators[i].min, range: modulatorRange(for: modulators[i]))
        SliderWithField(label: "Max", value: $modulators[i].max, range: modulatorRange(for: modulators[i]))
      case .noiseSmoothStep:
        SliderWithField(label: "Freq", value: $modulators[i].noiseDuration, range: 0.01...10)
        SliderWithField(label: "Min", value: $modulators[i].min, range: modulatorRange(for: modulators[i]))
        SliderWithField(label: "Max", value: $modulators[i].max, range: modulatorRange(for: modulators[i]))
      case .line:
        SliderWithField(label: "Duration", value: $modulators[i].lineDuration, range: 0.01...30)
        SliderWithField(label: "Min", value: $modulators[i].min, range: modulatorRange(for: modulators[i]))
        SliderWithField(label: "Max", value: $modulators[i].max, range: modulatorRange(for: modulators[i]))
      case .reciprocalConst:
        SliderWithField(label: "Value", value: $modulators[i].constValue, range: 0...128)
      case .eventNote:
        Text("Emits MIDI note number (0–127)")
          .foregroundStyle(.secondary)
      case .eventVelocity:
        Text("Emits velocity (0.0–1.0)")
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Preset Section

  @ViewBuilder
  private var presetSection: some View {
    Section("Preset") {
      LabeledContent("Preset File", value: presetFilename)
      Stepper("Voices: \(numVoices)", value: $numVoices, in: 1...64)
    }
  }

  // MARK: - Emission Picker

  @ViewBuilder
  private func emissionPicker(selection: Binding<IteratorSyntax>) -> some View {
    Picker("Emission", selection: Binding(
      get: { emissionTag(selection.wrappedValue) },
      set: { selection.wrappedValue = tagToEmission($0) }
    )) {
      Text("Cyclic").tag("cyclic")
      Text("Shuffled").tag("shuffled")
      Text("Random").tag("random")
    }
  }

  private func emissionTag(_ emission: IteratorSyntax) -> String {
    switch emission {
    case .cyclic:   return "cyclic"
    case .shuffled: return "shuffled"
    case .random:   return "random"
    case .waiting:  return "cyclic"
    }
  }

  private func tagToEmission(_ tag: String) -> IteratorSyntax {
    switch tag {
    case "cyclic":   return .cyclic
    case "shuffled": return .shuffled
    case "random":   return .random
    default:         return .cyclic
    }
  }

  /// Computes a slider range that adapts to the modulator's current values.
  /// For large values (>= 0.01), uses 0...2. For tiny values (like vibratoAmp),
  /// scales the range to 10x the larger of min/max so the slider is usable.
  private func modulatorRange(for mod: ModulatorState) -> ClosedRange<CoreFloat> {
    let upper = max(abs(mod.min), abs(mod.max))
    if upper >= 0.01 { return 0...2 }
    if upper == 0 { return 0...2 }
    return 0...(upper * 10)
  }

  // MARK: - Apply / Save

  private func buildTrackSpec() -> ProceduralTrackSyntax {
    let noteGen: NoteGeneratorSyntax
    switch generatorType {
    case .melodic:
      noteGen = .melodic(
        scales: IteratedListSyntax(candidates: scaleNames, emission: scaleEmission),
        roots: IteratedListSyntax(candidates: rootNames, emission: rootEmission),
        octaves: IteratedListSyntax(candidates: octaves, emission: octaveEmission),
        degrees: IteratedListSyntax(candidates: degrees, emission: degreeEmission),
        ordering: defaultOrdering
      )
    case .scaleSampler:
      noteGen = .scaleSampler(scale: ssScaleName, root: ssRootName, octaves: ssOctaves.isEmpty ? nil : ssOctaves)
    case .chordProgression:
      noteGen = .chordProgression(scale: cpScale, root: cpRoot, style: cpStyle.isEmpty ? nil : cpStyle)
    case .fixed:
      noteGen = .fixed(events: fixedEvents)
    case .midiFile:
      noteGen = .midiFile(filename: midiFilename, track: midiTrack, loop: midiLoop)
    }

    return ProceduralTrackSyntax(
      name: name,
      presetFilename: presetFilename,
      numVoices: numVoices,
      noteGenerator: noteGen,
      sustain: sustain.toSyntax(),
      gap: gap.toSyntax(),
      modulators: modulators.isEmpty ? nil : modulators.map { $0.toSyntax() }
    )
  }

  private func applyChanges() {
    let newSpec = buildTrackSpec()
    playbackState.replaceTrack(trackId: track.id, newTrackSpec: newSpec)
  }

  private func savePattern() {
    applyChanges()
    let spec = buildTrackSpec()
    let filename = name.lowercased().replacingOccurrences(of: " ", with: "_") + ".json"
    let patternSyntax = PatternSyntax(
      name: name,
      proceduralTracks: [spec],
      midiTracks: nil
    )
    PatternStorage.save(patternSyntax, filename: filename)
  }

  private func resetGeneratorState(for type: GeneratorType) {
    switch type {
    case .melodic:
      scaleNames = ["Major"]
      scaleEmission = .cyclic
      rootNames = ["C"]
      rootEmission = .cyclic
      octaves = [4]
      octaveEmission = .cyclic
      degrees = [1, 3, 5]
      degreeEmission = .cyclic
      defaultOrdering = .shuffled
    case .scaleSampler:
      ssScaleName = "Major"
      ssRootName = "C"
      ssOctaves = [3, 4, 5]
    case .chordProgression:
      cpScale = "Major"
      cpRoot = "C"
      cpStyle = "baroque"
    case .fixed:
      fixedEvents = [ChordSyntax(notes: [NoteSyntax(midi: 60, velocity: 100)])]
    case .midiFile:
      midiFilename = ""
      midiTrack = nil
      midiLoop = true
    }
  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let song = Song(name: "Aurora", patternFileName: "aurora_arpeggio.json")
  let playbackState = SongPlaybackState(song: song)
  let patternSpec = Bundle.main.decode(PatternSyntax.self, from: "aurora_arpeggio.json", subdirectory: "patterns")
  let trackSpec = patternSpec.proceduralTracks![0]
  let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "auroraBorealis.json", subdirectory: "presets")
  let track = TrackInfo(
    id: 0,
    patternName: "Preview",
    trackSpec: trackSpec,
    presetSpec: presetSpec,
    spatialPreset: SpatialPreset(presetSpec: presetSpec)
  )
  NavigationStack {
    PatternFormView(track: track)
  }
  .environment(engine)
  .environment(playbackState)
}

