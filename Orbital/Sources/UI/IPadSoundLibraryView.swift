//
//  IPadSoundLibraryView.swift
//  Orbital
//

import SwiftUI

/// iPad Sound Library detail view: lists the wavetable browser entry plus
/// every preset known to the shared `PresetLibrary`.
struct IPadSoundLibraryView: View {
  @Environment(PresetLibrary.self) private var library

  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink(value: PresetLibraryView.wavetableBrowserID) {
            Label("Wavetable Browser", systemImage: "waveform")
          }
        }
        if library.isLoading && library.presets.isEmpty {
          PresetLoadingRow()
        } else {
          ForEach(library.presets) { preset in
            NavigationLink(value: preset.fileName) {
              Text(preset.spec.name)
            }
          }
        }
      }
      .navigationTitle("Sounds")
      .navigationDestination(for: String.self) { presetID in
        if presetID == PresetLibraryView.wavetableBrowserID {
          WavetableBrowserView()
        } else if let preset = library.presets.first(where: { $0.fileName == presetID }) {
          PresetFormView(presetSpec: preset.spec)
            .navigationTitle(preset.spec.name)
        }
      }
    }
  }
}
