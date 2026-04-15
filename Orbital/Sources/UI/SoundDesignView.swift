//
//  SoundDesignView.swift
//  Orbital
//

import SwiftUI

struct SoundDesignView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(ResourceManager.self) private var resourceManager
  @Environment(PresetLibrary.self) private var library
  @State private var selectedPresetFileName: String?
  @State private var synth: SyntacticSynth?
  @State private var isShowingSaveDialog = false
  @State private var isShowingOverwriteConfirmation = false
  @State private var savePresetName = ""

  private var selectedPreset: PresetRef? {
    guard let selectedPresetFileName else { return nil }
    return library.presets.first { $0.fileName == selectedPresetFileName }
  }

  var body: some View {
    NavigationStack {
      if let selectedPreset, let synth {
        PresetFormView(synth: synth)
          .id(selectedPreset.fileName)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Picker("Preset", selection: $selectedPresetFileName) {
                ForEach(library.presets) { preset in
                  Text(preset.spec.name).tag(Optional(preset.fileName))
                }
              }
            }
            ToolbarItem(placement: .topBarTrailing) {
              Button("Save preset", systemImage: "square.and.arrow.down", action: showSaveDialog)
                .labelStyle(.iconOnly)
            }
          }
          .alert("Save Preset", isPresented: $isShowingSaveDialog) {
            TextField("Preset name", text: $savePresetName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: attemptSave)
          } message: {
            Text("Enter a name for the preset.")
          }
          .confirmationDialog(
            "A preset with this filename already exists.",
            isPresented: $isShowingOverwriteConfirmation,
            titleVisibility: .visible
          ) {
            Button("Overwrite", role: .destructive, action: saveCurrentPreset)
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("Do you want to replace the existing preset?")
          }
      } else if library.isLoading {
        ProgressView("Loading presets…")
      } else {
        ContentUnavailableView(
          "No Preset Selected",
          systemImage: "slider.horizontal.3"
        )
      }
    }
    .onChange(of: selectedPresetFileName) { _, _ in
      rebuildSynth()
    }
    .onChange(of: library.presets, initial: true) { _, _ in
      if selectedPresetFileName == nil, let first = library.presets.first {
        selectedPresetFileName = first.fileName
      }
    }
  }

  private func rebuildSynth() {
    guard let selectedPreset else {
      synth = nil
      return
    }
    // Reuse the same SyntacticSynth across preset picks: loadPreset rebuilds
    // the spatial preset and cleans up the old one atomically. Constructing a
    // fresh synth here would leak the prior SpatialPreset (still attached to
    // the audio graph) and leave MIDI receivers captured on the old instance.
    if let synth {
      synth.loadPreset(selectedPreset.spec)
    } else {
      synth = SyntacticSynth(engine: engine, presetSpec: selectedPreset.spec)
    }
  }

  private func showSaveDialog() {
    savePresetName = selectedPreset?.spec.name ?? ""
    isShowingSaveDialog = true
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
    guard PresetStorage.save(spec, filename: filename) else { return }
    guard let base = resourceManager.resourceBaseURL else { return }
    Task {
      await library.load(from: base.appending(path: "presets"))
      selectedPresetFileName = filename
    }
  }
}
