//
//  CompactAppLayout.swift
//  Orbital
//

import SwiftUI

/// iPhone-style layout: bottom `TabView` with four tabs. Reads
/// `MIDIDownloadLedger` and `PresetLibrary` to show loading indicators on
/// the Classics and Sounds tabs.
struct CompactAppLayout: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(MIDIDownloadLedger.self) private var midiLedger
  @Environment(PresetLibrary.self) private var presetLibrary
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?

  var body: some View {
    TabView {
      Tab("Library", systemImage: "music.note.list") {
        OrbitalView()
      }
      Tab {
        ClassicsBrowserView()
      } label: {
        LoadingTabLabel(text: "Classics", systemImage: "building.columns", isLoading: midiLedger.isLoading)
      }
      Tab("Procedures", systemImage: "list.bullet.indent") {
        IPadCreateView(createDocument: createDocument)
      }
      Tab {
        SoundDesignView()
      } label: {
        LoadingTabLabel(text: "Sounds", systemImage: "horn", isLoading: presetLibrary.isLoading)
      }
    }
    .task {
      if createDocument == nil {
        createDocument = SongDocument(generatorPattern: GeneratorSyntax(), engine: engine)
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory(isEnabled: library.anySongPlaying || createDocument?.isPlaying == true || createDocument?.isLoading == true) {
      PlaybackAccessoryView(
        state: library.currentPlaybackState ?? createDocument,
        isShowingVisualizer: $isShowingVisualizer
      )
    }
    .overlay {
      VisualizerOverlay(engine: engine, isShowingVisualizer: $isShowingVisualizer)
    }
  }
}
