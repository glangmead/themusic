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
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
          ForEach(library.songs) { song in
            SongCell(song: song)
          }
        }
        .padding()
      }
      .background {
        // A gradient behind the Liquid Glass cards gives the material
        // something to blur and reflect, improving contrast in light mode.
        LinearGradient(
          colors: [
            Color(UIColor { traits in
              traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.10, alpha: 1)
                : UIColor(white: 0.88, alpha: 1)
            }),
            Color(UIColor { traits in
              traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.05, alpha: 1)
                : UIColor(white: 0.80, alpha: 1)
            })
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .ignoresSafeArea()
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
  return OrbitalView()
    .environment(SpatialAudioEngine())
    .environment(library)
}

