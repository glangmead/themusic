//
//  PresetLibraryView.swift
//  Orbital
//

import SwiftUI

/// A lightweight reference to a preset file on disk.
private struct PresetRef: Identifiable {
  var id: String { fileName }
  let fileName: String
  let spec: PresetSyntax
}

struct PresetLibraryView: View {
  @Environment(ResourceManager.self) private var resourceManager
  @State private var presets: [PresetRef] = []

  var body: some View {
    NavigationStack {
      Group {
        if resourceManager.isReady {
          List {
            Section {
              NavigationLink("Wavetable Browser", value: "__wavetable_browser__")
            }
            ForEach(presets) { preset in
              NavigationLink(value: preset.fileName) {
                Text(preset.spec.name)
              }
              .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                  duplicatePreset(preset)
                } label: {
                  Label("Duplicate", systemImage: "doc.on.doc")
                }
                .tint(.blue)
              }
            }
          }
        } else {
          ProgressView("Loading sounds…")
        }
      }
      .navigationTitle("Sounds")
      .navigationDestination(for: String.self) { value in
        if value == "__wavetable_browser__" {
          WavetableBrowserView()
        } else if let preset = presets.first(where: { $0.fileName == value }) {
          PresetFormView(presetSpec: preset.spec)
            .navigationTitle(preset.spec.name)
        }
      }
      .onAppear { loadPresets() }
    }
  }

  private func loadPresets() {
    guard let base = resourceManager.resourceBaseURL else { return }
    let presetsDir = base.appendingPathComponent("presets")
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: presetsDir,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }) ?? []
    presets = urls.compactMap { url -> PresetRef? in
      let fileName = url.lastPathComponent
      guard let data = try? Data(contentsOf: url),
            let spec = try? JSONDecoder().decode(PresetSyntax.self, from: data)
      else { return nil }
      return PresetRef(fileName: fileName, spec: spec)
    }.sorted { $0.spec.name.localizedCaseInsensitiveCompare($1.spec.name) == .orderedAscending }
  }

  private func duplicatePreset(_ preset: PresetRef) {
    guard PresetStorage.duplicate(filename: preset.fileName) != nil else { return }
    loadPresets()
  }
}
