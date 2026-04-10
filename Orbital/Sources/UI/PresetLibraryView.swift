//
//  PresetLibraryView.swift
//  Orbital
//

import SwiftUI

/// A lightweight reference to a preset file on disk.
struct PresetRef: Identifiable {
  var id: String { fileName }
  let fileName: String
  let spec: PresetSyntax
}

/// Loads preset JSONs from `presetsDir` off the main thread using
/// `NSFileCoordinator` so iCloud can bring files local before reading.
/// Returns an array sorted by the preset `name` field.
func loadPresetsFromDirectory(_ presetsDir: URL) async -> [PresetRef] {
  let fileData: [(String, Data)] = await Task.detached(priority: .userInitiated) {
    let fm = FileManager.default
    let urls = (try? fm.contentsOfDirectory(
      at: presetsDir,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }) ?? []

    for url in urls {
      try? fm.startDownloadingUbiquitousItem(at: url)
    }

    let coordinator = NSFileCoordinator()
    var results: [(String, Data)] = []
    for url in urls {
      var coordError: NSError?
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
        if let data = try? Data(contentsOf: coordinatedURL) {
          results.append((url.lastPathComponent, data))
        }
      }
    }
    return results
  }.value

  let decoder = JSONDecoder()
  return fileData.compactMap { fileName, data -> PresetRef? in
    guard let spec = try? decoder.decode(PresetSyntax.self, from: data) else { return nil }
    return PresetRef(fileName: fileName, spec: spec)
  }.sorted { $0.spec.name.localizedCaseInsensitiveCompare($1.spec.name) == .orderedAscending }
}

struct PresetLibraryView: View {
  @Environment(ResourceManager.self) private var resourceManager
  @State private var presets: [PresetRef] = []
  @State private var selectedPresetID: String?

  private static let wavetableBrowserID = "__wavetable_browser__"

  var body: some View {
    NavigationStack {
      Group {
        if resourceManager.isReady {
          List(selection: $selectedPresetID) {
            Section {
              Text("Wavetable Browser")
                .tag(Self.wavetableBrowserID)
            }
            ForEach(presets) { preset in
              Text(preset.spec.name)
                .tag(preset.fileName)
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
          ProgressView("Loading sounds...")
        }
      }
      .navigationTitle("Sounds")
      .task { loadPresets() }
      .navigationDestination(item: $selectedPresetID) { presetID in
        if presetID == Self.wavetableBrowserID {
          WavetableBrowserView()
        } else if let preset = presets.first(where: { $0.fileName == presetID }) {
          PresetFormView(presetSpec: preset.spec)
            .navigationTitle(preset.spec.name)
        }
      }
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
