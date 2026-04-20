//
//  RegularAppLayout.swift
//  Orbital
//

import SwiftUI

/// iPad / Mac-as-iPad layout: `NavigationSplitView` with a sidebar of
/// categories. Reads `MIDIDownloadLedger` and `PresetLibrary` so the
/// Classics and Sounds rows can show loading indicators while their
/// data is being fetched from iCloud.
struct RegularAppLayout: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  @Environment(MIDIDownloadLedger.self) private var midiLedger
  @Environment(PresetLibrary.self) private var presetLibrary
  @State private var selectedCategory: SidebarCategory? = .songs
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?

  var body: some View {
    NavigationSplitView {
      List(SidebarCategory.allCases, selection: $selectedCategory) { category in
        LoadingSidebarRow(category: category, isLoading: isLoading(for: category))
          .tag(category)
      }
      .navigationTitle("Orbital")
    } detail: {
      IPadDetailView(selectedCategory: selectedCategory, createDocument: createDocument)
    }
    .task {
      if createDocument == nil {
        createDocument = SongDocument(generatorPattern: GeneratorSyntax(), engine: engine)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if library.anySongPlaying || createDocument?.isPlaying == true || createDocument?.isLoading == true {
        PlaybackAccessoryView(
          state: library.currentPlaybackState ?? createDocument,
          isShowingVisualizer: $isShowingVisualizer
        )
        .padding()
        .background(.ultraThinMaterial)
      }
    }
    .overlay {
      VisualizerOverlay(engine: engine, isShowingVisualizer: $isShowingVisualizer)
    }
  }

  private func isLoading(for category: SidebarCategory) -> Bool {
    switch category {
    case .classics: midiLedger.isLoading
    case .soundDesign: presetLibrary.isLoading
    default: false
    }
  }
}
