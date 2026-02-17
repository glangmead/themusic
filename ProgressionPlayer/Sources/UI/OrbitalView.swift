//
//  OrbitalView.swift
//  ProgressionPlayer
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
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
          ForEach(library.songs) { song in
            SongCell(song: song)
          }
        }
        .padding()
      }
      .navigationTitle("Orbital")
      .toolbar {
        ToolbarItem {
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
    .fullScreenCover(isPresented: $isShowingVisualizer) {
      VisualizerView(engine: engine, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
    }
  }
}
#Preview {
  let library = SongLibrary()
  library.songs = [
    Song(
      name: "Aurora Borealis",
      patternFileName: "aurora_arpeggio.json",
      presetFileNames: ["auroraBorealis.json"]
    ),
    Song(
      name: "Baroque Chords",
      patternFileName: "baroque_chords.json",
      presetFileNames: ["5th_cluedo.json"]
    ),
  ]
  return OrbitalView()
    .environment(SpatialAudioEngine())
    .environment(library)
}

