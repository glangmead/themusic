//
//  PresetLibraryView.swift
//  Orbital
//

import SwiftUI

/// A lightweight reference to a preset file on disk.
struct PresetRef: Identifiable, Equatable {
  var id: String { fileName }
  let fileName: String
  let spec: PresetSyntax

  static func == (lhs: PresetRef, rhs: PresetRef) -> Bool {
    lhs.fileName == rhs.fileName
  }
}

/// Loads preset JSONs from `presetsDir` using `NSFileCoordinator` so iCloud
/// can bring files local before reading. The function is `nonisolated` and
/// `async`, so when awaited from MainActor it runs on the cooperative pool.
/// Returns an array sorted by the preset `name` field.
func loadPresetsFromDirectory(_ presetsDir: URL) async -> [PresetRef] {
  let fileData = readPresetFilesSynchronously(in: presetsDir)
  let decoder = JSONDecoder()
  return fileData.compactMap { fileName, data -> PresetRef? in
    guard let spec = try? decoder.decode(PresetSyntax.self, from: data) else { return nil }
    return PresetRef(fileName: fileName, spec: spec)
  }.sorted { $0.spec.name.localizedCaseInsensitiveCompare($1.spec.name) == .orderedAscending }
}

/// Synchronous worker that does the blocking iCloud-coordinated reads.
/// Always invoked from a nonisolated async context, never on the main actor.
private func readPresetFilesSynchronously(in presetsDir: URL) -> [(String, Data)] {
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
}

struct PresetLibraryView: View {
  @Environment(ResourceManager.self) private var resourceManager
  @Environment(PresetLibrary.self) private var library
  @State private var selectedPresetID: String?

  static let wavetableBrowserID = "__wavetable_browser__"

  var body: some View {
    NavigationStack {
      List(selection: $selectedPresetID) {
        Section {
          Text("Wavetable Browser")
            .tag(Self.wavetableBrowserID)
        }
        if library.isLoading && library.presets.isEmpty {
          PresetLoadingRow()
        } else {
          ForEach(library.presets) { preset in
            Text(preset.spec.name)
              .tag(preset.fileName)
              .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Duplicate", systemImage: "doc.on.doc", action: { duplicatePreset(preset) })
                  .tint(.blue)
              }
          }
        }
      }
      .navigationTitle("Sounds")
      .navigationDestination(item: $selectedPresetID) { presetID in
        if presetID == Self.wavetableBrowserID {
          WavetableBrowserView()
        } else if let preset = library.presets.first(where: { $0.fileName == presetID }) {
          PresetFormView(presetSpec: preset.spec)
            .navigationTitle(preset.spec.name)
        }
      }
    }
  }

  private func duplicatePreset(_ preset: PresetRef) {
    guard PresetStorage.duplicate(filename: preset.fileName) != nil else { return }
    guard let base = resourceManager.resourceBaseURL else { return }
    Task { await library.load(from: base.appending(path: "presets")) }
  }
}

/// Loading row used by Sound Library lists. Combined into one accessibility
/// element so VoiceOver speaks "Loading presets" once instead of two pieces.
struct PresetLoadingRow: View {
  var body: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("Loading presets…")
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Loading presets")
  }
}
