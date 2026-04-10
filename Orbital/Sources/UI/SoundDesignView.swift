//
//  SoundDesignView.swift
//  Orbital
//

import SwiftUI

struct SoundDesignView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(ResourceManager.self) private var resourceManager
  @State private var presets: [PresetRef] = []
  @State private var selectedPreset: PresetRef?
  @State private var synth: SyntacticSynth?
  @State private var isShowingSaveDialog = false
  @State private var isShowingOverwriteConfirmation = false
  @State private var savePresetName = ""
  @State private var isLoadingPresets = false

  /// Optional external loading flag the parent can observe (e.g. to show a
  /// spinner next to the Sound Design row in a sidebar). Mirrors
  /// `isLoadingPresets` while loads are in-flight.
  var externalIsLoading: Binding<Bool>?

  var body: some View {
    NavigationStack {
      if let selectedPreset, let synth {
        PresetFormView(synth: synth)
          .id(selectedPreset.fileName)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Picker("Preset", selection: Binding(
                get: { selectedPreset.fileName },
                set: { newFileName in selectPreset(named: newFileName) }
              )) {
                ForEach(presets) { preset in
                  Text(preset.spec.name).tag(preset.fileName)
                }
              }
            }
            ToolbarItem(placement: .topBarTrailing) {
              Button {
                savePresetName = selectedPreset.spec.name
                isShowingSaveDialog = true
              } label: {
                Image(systemName: "square.and.arrow.down")
              }
              .accessibilityLabel("Save preset") // [VERIFY]
            }
          }
          .alert("Save Preset", isPresented: $isShowingSaveDialog) {
            TextField("Preset name", text: $savePresetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { attemptSave() }
          } message: {
            Text("Enter a name for the preset.")
          }
          .confirmationDialog(
            "A preset with this filename already exists.",
            isPresented: $isShowingOverwriteConfirmation,
            titleVisibility: .visible
          ) {
            Button("Overwrite", role: .destructive) { saveCurrentPreset() }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("Do you want to replace the existing preset?")
          }
      } else if isLoadingPresets {
        ProgressView("Loading presets…")
      } else {
        ContentUnavailableView(
          "No Preset Selected",
          systemImage: "slider.horizontal.3"
        )
      }
    }
    .task(id: resourceManager.resourceBaseURL) {
      await loadPresets()
      if selectedPreset == nil, let first = presets.first {
        selectPreset(ref: first)
      }
    }
  }

  private func loadPresets() async {
    guard let base = resourceManager.resourceBaseURL else { return }
    let presetsDir = base.appending(path: "presets")
    isLoadingPresets = true
    externalIsLoading?.wrappedValue = true
    defer {
      isLoadingPresets = false
      externalIsLoading?.wrappedValue = false
    }
    presets = await loadPresetsFromDirectory(presetsDir)
  }

  private func selectPreset(named fileName: String) {
    guard let ref = presets.first(where: { $0.fileName == fileName }) else { return }
    selectPreset(ref: ref)
  }

  private func selectPreset(ref: PresetRef) {
    selectedPreset = ref
    synth = SyntacticSynth(engine: engine, presetSpec: ref.spec)
  }

  private func filenameForPresetName(_ name: String) -> String {
    name.replacing(" ", with: "_").lowercased().appending(".json")
  }

  private func attemptSave() {
    let filename = filenameForPresetName(savePresetName)
    if PresetStorage.exists(filename: filename) {
      isShowingOverwriteConfirmation = true
    } else {
      saveCurrentPreset()
    }
  }

  private func saveCurrentPreset() {
    guard let synth, !savePresetName.isEmpty else { return }
    let spec = synth.currentPresetSyntax(name: savePresetName)
    let filename = filenameForPresetName(savePresetName)
    if PresetStorage.save(spec, filename: filename) {
      Task {
        await loadPresets()
        selectPreset(named: filename)
      }
    }
  }
}
