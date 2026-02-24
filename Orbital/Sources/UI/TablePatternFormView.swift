//
//  TablePatternFormView.swift
//  Orbital
//
//  Form-based editor for table patterns. Each table row becomes a Form Section.
//

import SwiftUI

struct TablePatternFormView: View {
  @Environment(SongDocument.self) private var playbackState

  @State private var patternName: String
  @State private var emitters: [EmitterRowState]
  @State private var noteMaterials: [NoteMaterialRowState]
  @State private var modulators: [TableModulatorRowState]
  @State private var tracks: [TrackAssemblyRowState]

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
          applyChanges()
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
        Button {
          applyChanges()
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
    DisclosureGroup {
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
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(emitter.wrappedValue.name.isEmpty ? "Unnamed Emitter" : emitter.wrappedValue.name)
        Text(emitterSummary(emitter.wrappedValue))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Note Material Section

  @ViewBuilder
  private func noteMaterialSection(_ nm: Binding<NoteMaterialRowState>) -> some View {
    DisclosureGroup {
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
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(nm.wrappedValue.name.isEmpty ? "Unnamed Material" : nm.wrappedValue.name)
        Text(noteMaterialSummary(nm.wrappedValue))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Modulator Section

  @ViewBuilder
  private func modulatorSection(_ mod: Binding<TableModulatorRowState>) -> some View {
    DisclosureGroup {
      TextField("Name", text: mod.name)
      TextField("Target Handle", text: mod.targetHandle)

      if mod.wrappedValue.arrow != nil || !mod.wrappedValue.quickExpressionText.isEmpty {
        ExpressionTextField(
          text: mod.quickExpressionText,
          placeholder: "Expression (e.g. 1 / (octave + 1))",
          emitterNames: allEmitterNames()
        )
        .frame(height: 34)
      } else {
        Picker("Float Emitter", selection: mod.floatEmitter) {
          Text("(none)").tag("")
          ForEach(emitterNames(ofType: .float), id: \.self) { name in
            Text(name).tag(name)
          }
        }
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(mod.wrappedValue.name.isEmpty ? "Unnamed Modulator" : mod.wrappedValue.name)
        Text(modulatorSummary(mod.wrappedValue))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }

  // MARK: - Track Section

  @ViewBuilder
  private func trackSection(_ track: Binding<TrackAssemblyRowState>) -> some View {
    DisclosureGroup {
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
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(track.wrappedValue.name.isEmpty ? "Unnamed Track" : track.wrappedValue.name)
        Text(trackSummary(track.wrappedValue))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Helpers

  /// Returns emitter names filtered by output type.
  private func emitterNames(ofType type: EmitterOutputType) -> [String] {
    emitters.filter { $0.outputType == type && !$0.name.isEmpty }.map(\.name)
  }

  /// Returns all emitter names regardless of type, for expression keyboard.
  private func allEmitterNames() -> [String] {
    emitters.filter { !$0.name.isEmpty }.map(\.name)
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
      return [.randInt, .shuffle, .cyclic, .random, .indexPicker(emitter: ""), .markovChord]
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
    case .markovChord: return "Markov Chord"
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

  // MARK: - Summaries

  private func emitterSummary(_ emitter: EmitterRowState) -> String {
    var parts: [String] = [emitter.outputType.rawValue]
    parts.append(functionLabel(emitter.function))
    if emitter.needsArgs {
      parts.append("\(formatNumber(emitter.arg1))–\(formatNumber(emitter.arg2))")
    } else if emitter.needsCandidates {
      let count = emitter.candidates.filter { !$0.isEmpty }.count
      parts.append("\(count) candidates")
    } else if emitter.needsInputEmitters {
      let inputs = emitter.inputEmitters.filter { !$0.isEmpty }
      if !inputs.isEmpty {
        parts.append("of: " + inputs.joined(separator: ", "))
      }
    }
    if case .waiting(let e) = emitter.updateMode {
      parts.append("waiting: \(e)")
    }
    return parts.joined(separator: " · ")
  }

  private func noteMaterialSummary(_ nm: NoteMaterialRowState) -> String {
    var parts: [String] = []
    let count = nm.intervalStrings.filter { !$0.isEmpty }.count
    parts.append("\(count) interval\(count == 1 ? "" : "s")")
    if !nm.intervalPicker.isEmpty { parts.append("picker: \(nm.intervalPicker)") }
    if !nm.scaleEmitter.isEmpty { parts.append("scale: \(nm.scaleEmitter)") }
    if !nm.scaleRootEmitter.isEmpty { parts.append("root: \(nm.scaleRootEmitter)") }
    return parts.joined(separator: " · ")
  }

  private func modulatorSummary(_ mod: TableModulatorRowState) -> String {
    if mod.targetHandle.isEmpty && mod.floatEmitter.isEmpty && mod.arrow == nil { return "unconfigured" }
    let target = mod.targetHandle.isEmpty ? "?" : mod.targetHandle
    let source: String
    if !mod.quickExpressionText.isEmpty {
      source = mod.quickExpressionText
    } else if mod.arrow != nil {
      source = "(arrow)"
    } else if mod.floatEmitter.isEmpty {
      source = "?"
    } else {
      source = mod.floatEmitter
    }
    return "\(target) ← \(source)"
  }

  private func trackSummary(_ track: TrackAssemblyRowState) -> String {
    var parts: [String] = []
    if !track.presetFilename.isEmpty { parts.append(track.presetFilename) }
    if !track.noteMaterial.isEmpty { parts.append(track.noteMaterial) }
    if !track.sustainEmitter.isEmpty { parts.append("sustain: \(track.sustainEmitter)") }
    if !track.gapEmitter.isEmpty { parts.append("gap: \(track.gapEmitter)") }
    if parts.isEmpty { return "unconfigured" }
    return parts.joined(separator: " · ")
  }

  private func formatNumber(_ value: CoreFloat) -> String {
    if value == value.rounded() && abs(value) < 10000 {
      return String(format: "%.0f", value)
    }
    return String(format: "%.4g", value)
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
