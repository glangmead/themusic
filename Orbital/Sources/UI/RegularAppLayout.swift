//
//  RegularAppLayout.swift
//  Orbital
//

import SwiftUI

/// iPad / Mac-as-iPad layout: `NavigationSplitView` with a sidebar of
/// categories. Reads `MIDIDownloadLedger` and `PresetLibrary` so the
/// Classics and Sounds rows can show loading indicators while their
/// data is being fetched from iCloud. A `Now Playing` row appears at the
/// top of the sidebar only while a song is playing or loading.
struct RegularAppLayout: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  @Environment(MIDIDownloadLedger.self) private var midiLedger
  @Environment(PresetLibrary.self) private var presetLibrary
  @State private var selectedCategory: SidebarCategory? = .songs
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?

  private var isPlaybackActive: Bool {
    library.anySongPlaying || createDocument?.isPlaying == true || createDocument?.isLoading == true
  }

  private var sidebarRows: [SidebarCategory] {
    let base: [SidebarCategory] = [.songs, .classics, .create, .soundDesign]
    return isPlaybackActive ? [.nowPlaying] + base : base
  }

  var body: some View {
    NavigationSplitView {
      List(sidebarRows, selection: $selectedCategory) { category in
        LoadingSidebarRow(category: category, isLoading: isLoading(for: category))
          .tag(category)
      }
      .navigationTitle("Orbital")
    } detail: {
      IPadDetailView(
        selectedCategory: selectedCategory,
        createDocument: createDocument,
        isShowingVisualizer: $isShowingVisualizer
      )
    }
    .task {
      if createDocument == nil {
        createDocument = SongDocument(generatorPattern: GeneratorSyntax(), engine: engine)
      }
    }
    .onChange(of: isPlaybackActive) { _, nowActive in
      if !nowActive, selectedCategory == .nowPlaying {
        selectedCategory = .songs
      }
    }
    .safeAreaInset(edge: .bottom) {
      if isPlaybackActive, selectedCategory != .nowPlaying {
        PlaybackAccessoryView(
          state: library.currentPlaybackState ?? createDocument,
          isShowingVisualizer: $isShowingVisualizer,
          onTap: { selectedCategory = .nowPlaying }
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
    case .nowPlaying, .songs, .create: false
    }
  }
}
