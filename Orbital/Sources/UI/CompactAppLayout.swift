//
//  CompactAppLayout.swift
//  Orbital
//

import SwiftUI

/// iPhone-style layout: bottom `TabView` with five tabs. Reads
/// `MIDIDownloadLedger` and `PresetLibrary` to show loading indicators on
/// the Classics, Sound Library, and Sound Design tabs.
struct CompactAppLayout: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(MIDIDownloadLedger.self) private var midiLedger
  @Environment(PresetLibrary.self) private var presetLibrary
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?

  var body: some View {
    TabView {
      Tab("Songs", systemImage: "music.note.list") {
        OrbitalView()
      }
      Tab {
        ClassicsBrowserView()
      } label: {
        LoadingTabLabel(text: "Classics", systemImage: "building.columns", isLoading: midiLedger.isLoading)
      }
      Tab("Mood", systemImage: "wand.and.stars") {
        IPadCreateView(createDocument: createDocument)
      }
      Tab {
        PresetLibraryView()
      } label: {
        LoadingTabLabel(text: "Sound library", systemImage: "pianokeys", isLoading: presetLibrary.isLoading)
      }
      Tab {
        SoundDesignView()
      } label: {
        LoadingTabLabel(text: "Sound design", systemImage: "slider.horizontal.3", isLoading: presetLibrary.isLoading)
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
