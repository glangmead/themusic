//
//  OrbitalView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct OrbitalView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @State private var isShowingVisualizer = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(library.songs) { song in
          SongCell(song: song)
        }
      }
      .navigationTitle("Orbital")
      .toolbar {
        ToolbarItemGroup {
          Button {
            if library.allPaused {
              library.resumeAll()
            } else {
              library.pauseAll()
            }
          } label: {
            Image(systemName: library.allPaused ? "play.fill" : "pause.fill")
          }
          .disabled(!library.anySongPlaying)

          Button {
            library.stopAll()
          } label: {
            Image(systemName: "stop.fill")
          }
          .disabled(!library.anySongPlaying)

          Button {
            withAnimation(.easeInOut(duration: 0.4)) {
              isShowingVisualizer = true
            }
          } label: {
            Label("Visualizer", systemImage: "sparkles.tv")
          }
        }
      }
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

#Preview {
  let engine = SpatialAudioEngine()
  let library = SongLibrary()
  library.songs = [
    Song(
      name: "Aurora Borealis",
      patternFileNames: ["aurora_arpeggio.json"]
    ),
    Song(
      name: "Baroque Chords",
      patternFileNames: ["baroque_chords.json"]
    ),
  ]
  // Pre-create playback states so navigating to SongSettingsView works in Preview
  for song in library.songs {
    _ = library.playbackState(for: song, engine: engine)
  }
  return OrbitalView()
    .environment(engine)
    .environment(library)
}

