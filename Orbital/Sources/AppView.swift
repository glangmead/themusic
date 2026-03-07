//
//  AppView.swift
//  Orbital
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

struct AppView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @State private var isShowingVisualizer = false
  @State private var createDocument: SongDocument?

  var body: some View {
    TabView {
      Tab("Songs", systemImage: "music.note.list") {
        OrbitalView()
      }
      Tab("Classics", systemImage: "building.columns") {
        ClassicsBrowserView()
      }
      Tab("Create", systemImage: "wand.and.stars") {
        NavigationStack {
          if let doc = createDocument {
            GeneratorFormView(params: doc.generatorPattern ?? GeneratorSyntax())
              .environment(doc)
          } else {
            ProgressView()
          }
        }
      }
      Tab("Sound library", systemImage: "pianokeys") {
        PresetLibraryView()
      }
      Tab("Sound design", systemImage: "slider.horizontal.3") {
        PadTemplateFormView()
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
      VisualizerView(engine: engine, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
        .opacity(isShowingVisualizer ? 1 : 0)
        .allowsHitTesting(isShowingVisualizer)
        .animation(.easeInOut(duration: 0.4), value: isShowingVisualizer)
    }
  }
}

/// Playback controls shown as the tab view's bottom accessory when a song is playing.
/// Tapping the accessory opens the event log as a sheet.
private struct PlaybackAccessoryView: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  let state: SongDocument?
  @Binding var isShowingVisualizer: Bool
  @State private var isShowingEventLog = false

  var body: some View {
    HStack {
      if placement != .inline {
        if library.isLoading {
          ProgressView()
        }

        VStack(alignment: .leading, spacing: 2) {
          if let name = library.currentSongName {
            Text(name)
              .lineLimit(1)
          }
          // Show subtitle (e.g. composer name from Classics) first; fall back to chord label.
          let secondaryText = state?.song.subtitle ?? state?.currentChordLabel
          if let secondary = secondaryText {
            Text(secondary)
              .font(.caption.italic())
              .lineLimit(1)
              .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.2), value: state?.song.subtitle ?? state?.currentChordLabel)

        Spacer()
      }

      if placement == .inline {
        AccessoryButtons(isShowingVisualizer: $isShowingVisualizer)
          .buttonStyle(.glass)
      } else {
        AccessoryButtons(isShowingVisualizer: $isShowingVisualizer)
      }
    }
    .padding(.horizontal)
    .contentShape(Rectangle())
    .onTapGesture {
      isShowingEventLog = true
    }
    .sheet(isPresented: $isShowingEventLog) {
      if let state {
        EventLogSheet(state: state)
      }
    }
  }
}

private struct AccessoryButtons: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    HStack(spacing: placement == .inline ? 12 : 20) {
      if !library.isLoading {
        Button(library.allPaused ? "Play" : "Pause", systemImage: library.allPaused ? "play.fill" : "pause.fill") {
          if library.allPaused {
            library.resumeAll()
          } else {
            library.pauseAll()
          }
        }

        Button("Stop", systemImage: "stop.fill", action: library.stopAll)
      }

      Button("Visualizer", systemImage: "sparkles.tv") {
        withAnimation(.easeInOut(duration: 0.4)) {
          isShowingVisualizer = true
        }
      }
    }
  }
}

/// Full event log presented as a sheet with a grab bar.
private struct EventLogSheet: View {
  let state: SongDocument
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      EventLogView(eventLog: state.eventLog)
        .navigationTitle("Event Log")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .presentationDragIndicator(.visible)
  }
}

#Preview {
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
    .environment(ResourceManager())
    .environment(ClassicsCatalogLibrary())
}
