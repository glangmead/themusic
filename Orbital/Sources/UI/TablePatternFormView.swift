//
//  TablePatternFormView.swift
//  Orbital
//
//  Form-based editor for table patterns. Each table row becomes a Form Section.
//

import SwiftUI

struct TablePatternFormView: View {
  @Environment(SongPlaybackState.self) private var playbackState

  @State private var patternName: String
  @State private var emitters: [EmitterRowState]
  @State private var noteMaterials: [NoteMaterialRowState]
  @State private var modulators: [TableModulatorRowState]
  @State private var tracks: [TrackAssemblyRowState]

  init() {
    let table = TablePatternSyntax(
      name: "New Pattern", emitters: [], noteMaterials: [],
      modulators: [], tracks: []
    )
    _patternName = State(initialValue: table.name)
    _emitters = State(initialValue: [])
    _noteMaterials = State(initialValue: [])
    _modulators = State(initialValue: [])
    _tracks = State(initialValue: [])
  }

  init(table: TablePatternSyntax) {
    _patternName = State(initialValue: table.name)
    _emitters = State(initialValue: table.emitters.map(EmitterRowState.init))
    _noteMaterials = State(initialValue: table.noteMaterials.map(NoteMaterialRowState.init))
    _modulators = State(initialValue: table.modulators.map(TableModulatorRowState.init))
    _tracks = State(initialValue: table.tracks.map(TrackAssemblyRowState.init))
  }

  var body: some View {
    Form {
      // MARK: - Emitters
      Section("Emitters") {
        ForEach($emitters) { $emitter in
          emitterSection($emitter)
        }
        .onDelete { emitters.remove(atOffsets: $0) }
        Button("Add Emitter") {
          emitters.append(EmitterRowState())
        }
      }

      // MARK: - Note Material
      Section("Note Material") {
        ForEach($noteMaterials) { $nm in
          noteMaterialSection($nm)
        }
        .onDelete { noteMaterials.remove(atOffsets: $0) }
        Button("Add Note Material") {
          noteMaterials.append(NoteMaterialRowState())
        }
      }

      // MARK: - Modulators
      Section("Modulators") {
        ForEach($modulators) { $mod in
          modulatorSection($mod)
        }
        .onDelete { modulators.remove(atOffsets: $0) }
        Button("Add Modulator") {
          modulators.append(TableModulatorRowState())
        }
      }

      // MARK: - Tracks
      Section("Tracks") {
        ForEach($tracks) { $track in
          trackSection($track)
        }
        .onDelete { tracks.remove(atOffsets: $0) }
        Button("Add Track") {
          tracks.append(TrackAssemblyRowState())
        }
      }
    }
    .navigationTitle(patternName)
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

  // MARK: - Emitter Section

  @ViewBuilder
  private func emitterSection(_ emitter: Binding<EmitterRowState>) -> some View {
    DisclosureGroup(emitter.wrappedValue.name.isEmpty ? "Unnamed Emitter" : emitter.wrappedValue.name) {
      TextField("Name", text: emitter.name)

      Picker("Output Type", selection: emitter.outputType) {
        ForEach(EmitterOutputType.allCases, id: \.self) { type in
          Text(type.rawValue).tag(type)
        }
      }

      Picker("Function", selection: emitter.function) {
        ForEach(functionsForOutputType(emitter.wrappedValue.outputType), id: \.self) { fn in
          Text(functionLabel(fn)).tag(fn)
        }
      }

      if emitter.wrappedValue.needsArgs {
        SliderWithField(label: "Min", value: emitter.arg1, range: -100...1000)
        SliderWithField(label: "Max", value: emitter.arg2, range: -100...1000)
      }

      if emitter.wrappedValue.needsCandidates {
        candidatesEditor(candidates: emitter.candidates)
      }

      if case .indexPicker = emitter.wrappedValue.function {
        Picker("Index Emitter", selection: emitter.function) {
          ForEach(emitterNames(ofType: .int), id: \.self) { name in
            Text(name).tag(EmitterFunction.indexPicker(emitter: name))
          }
        }
      }

      if emitter.wrappedValue.needsInputEmitters {
        inputEmittersEditor(inputs: emitter.inputEmitters)
      }

      Picker("Update Mode", selection: emitter.updateMode) {
        Text("Each").tag(EmitterUpdateMode.each)
        ForEach(emitterNames(ofType: .float), id: \.self) { name in
          Text("Waiting: \(name)").tag(EmitterUpdateMode.waiting(emitter: name))
        }
      }
    }
  }

  // MARK: - Note Material Section

  @ViewBuilder
  private func noteMaterialSection(_ nm: Binding<NoteMaterialRowState>) -> some View {
    DisclosureGroup(nm.wrappedValue.name.isEmpty ? "Unnamed Material" : nm.wrappedValue.name) {
      TextField("Name", text: nm.name)

      Section("Intervals") {
        ForEach(nm.intervalStrings.indices, id: \.self) { i in
          TextField("Degrees (e.g. 0,2,4)", text: nm.intervalStrings[i])
            .keyboardType(.numbersAndPunctuation)
        }
        .onDelete { nm.wrappedValue.intervalStrings.remove(atOffsets: $0) }
        Button("Add Interval") {
          nm.wrappedValue.intervalStrings.append("0")
        }
      }

      Picker("Interval Picker", selection: nm.intervalPicker) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .int), id: \.self) { name in
          Text(name).tag(name)
        }
      }

      Picker("Octave Emitter", selection: nm.octaveEmitter) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .octave), id: \.self) { name in
          Text(name).tag(name)
        }
      }

      Picker("Scale Emitter", selection: nm.scaleEmitter) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .scale), id: \.self) { name in
          Text(name).tag(name)
        }
      }

      Picker("Root Emitter", selection: nm.scaleRootEmitter) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .root), id: \.self) { name in
          Text(name).tag(name)
        }
      }
    }
  }

  // MARK: - Modulator Section

  @ViewBuilder
  private func modulatorSection(_ mod: Binding<TableModulatorRowState>) -> some View {
    DisclosureGroup(mod.wrappedValue.name.isEmpty ? "Unnamed Modulator" : mod.wrappedValue.name) {
      TextField("Name", text: mod.name)
      TextField("Target Handle", text: mod.targetHandle)

      Picker("Float Emitter", selection: mod.floatEmitter) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .float), id: \.self) { name in
          Text(name).tag(name)
        }
      }
    }
  }

  // MARK: - Track Section

  @ViewBuilder
  private func trackSection(_ track: Binding<TrackAssemblyRowState>) -> some View {
    DisclosureGroup(track.wrappedValue.name.isEmpty ? "Unnamed Track" : track.wrappedValue.name) {
      TextField("Name", text: track.name)

      Picker("Preset", selection: track.presetFilename) {
        Text("(none)").tag("")
        ForEach(availablePresetFilenames, id: \.self) { name in
          Text(name).tag(name)
        }
      }

      Stepper("Voices: \(track.wrappedValue.numVoices)", value: track.numVoices, in: 1...24)

      Picker("Note Material", selection: track.noteMaterial) {
        Text("(none)").tag("")
        ForEach(noteMaterials.map(\.name), id: \.self) { name in
          Text(name).tag(name)
        }
      }

      Picker("Sustain Emitter", selection: track.sustainEmitter) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .float), id: \.self) { name in
          Text(name).tag(name)
        }
      }

      Picker("Gap Emitter", selection: track.gapEmitter) {
        Text("(none)").tag("")
        ForEach(emitterNames(ofType: .float), id: \.self) { name in
          Text(name).tag(name)
        }
      }

      modulatorNamesEditor(names: track.modulatorNames)
    }
  }

  // MARK: - Helpers

  /// Returns emitter names filtered by output type.
  private func emitterNames(ofType type: EmitterOutputType) -> [String] {
    emitters.filter { $0.outputType == type && !$0.name.isEmpty }.map(\.name)
  }

  /// All available preset filenames (without .json extension).
  private var availablePresetFilenames: [String] {
    let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "presets") ?? []
    return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
  }

  /// Functions available for a given output type.
  private func functionsForOutputType(_ type: EmitterOutputType) -> [EmitterFunction] {
    switch type {
    case .float:
      return [.randFloat, .exponentialRandFloat, .shuffle, .cyclic, .random, .sum, .reciprocal]
    case .int:
      return [.randInt, .shuffle, .cyclic, .random, .indexPicker(emitter: "")]
    case .root, .octave, .scale:
      return [.shuffle, .cyclic, .random, .indexPicker(emitter: "")]
    }
  }

  private func functionLabel(_ fn: EmitterFunction) -> String {
    switch fn {
    case .randFloat: return "Random Float"
    case .exponentialRandFloat: return "Exponential Random"
    case .randInt: return "Random Int"
    case .shuffle: return "Shuffle"
    case .cyclic: return "Cyclic"
    case .random: return "Random (list)"
    case .sum: return "Sum"
    case .reciprocal: return "Reciprocal"
    case .indexPicker: return "Index Picker"
    }
  }

  @ViewBuilder
  private func candidatesEditor(candidates: Binding<[String]>) -> some View {
    Section("Candidates") {
      ForEach(candidates.wrappedValue.indices, id: \.self) { i in
        TextField("Value", text: candidates[i])
      }
      .onDelete { candidates.wrappedValue.remove(atOffsets: $0) }
      Button("Add Candidate") {
        candidates.wrappedValue.append("")
      }
    }
  }

  @ViewBuilder
  private func inputEmittersEditor(inputs: Binding<[String]>) -> some View {
    Section("Input Emitters") {
      ForEach(inputs.wrappedValue.indices, id: \.self) { i in
        Picker("Input \(i + 1)", selection: inputs[i]) {
          Text("(none)").tag("")
          ForEach(emitterNames(ofType: .float), id: \.self) { name in
            Text(name).tag(name)
          }
        }
      }
      .onDelete { inputs.wrappedValue.remove(atOffsets: $0) }
      Button("Add Input Emitter") {
        inputs.wrappedValue.append("")
      }
    }
  }

  @ViewBuilder
  private func modulatorNamesEditor(names: Binding<[String]>) -> some View {
    Section("Modulators") {
      ForEach(names.wrappedValue.indices, id: \.self) { i in
        Picker("Modulator \(i + 1)", selection: names[i]) {
          Text("(none)").tag("")
          ForEach(modulators.map(\.name), id: \.self) { name in
            Text(name).tag(name)
          }
        }
      }
      .onDelete { names.wrappedValue.remove(atOffsets: $0) }
      Button("Add Modulator") {
        names.wrappedValue.append("")
      }
    }
  }

  // MARK: - Apply & Save

  private func buildTableSyntax() -> TablePatternSyntax {
    TablePatternSyntax(
      name: patternName,
      emitters: emitters.map { $0.toSyntax() },
      noteMaterials: noteMaterials.map { $0.toSyntax() },
      modulators: modulators.map { $0.toSyntax() },
      tracks: tracks.map { $0.toSyntax() }
    )
  }

  private func applyChanges() {
    let table = buildTableSyntax()
    playbackState.replaceTablePattern(table)
  }

  private func savePattern() {
    applyChanges()
    let table = buildTableSyntax()
    let filename = patternName.lowercased().replacingOccurrences(of: " ", with: "_") + ".json"
    let patternSyntax = PatternSyntax(
      name: patternName,
      proceduralTracks: nil,
      midiTracks: nil,
      tableTracks: table
    )
    PatternStorage.save(patternSyntax, filename: filename)
  }
}
