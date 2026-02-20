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

  var body: some View {
    TabView {
      Tab("Songs", systemImage: "music.note.list") {
        OrbitalView()
      }
    }
    .tabViewBottomAccessory(isEnabled: library.anySongPlaying) {
      PlaybackAccessoryView(isShowingVisualizer: $isShowingVisualizer)
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
private struct PlaybackAccessoryView: View {
  @Environment(SongLibrary.self) private var library
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    HStack {
      Button {
        if library.allPaused {
          library.resumeAll()
        } else {
          library.pauseAll()
        }
      } label: {
        Image(systemName: library.allPaused ? "play.fill" : "pause.fill")
      }

      Button {
        library.stopAll()
      } label: {
        Image(systemName: "stop.fill")
      }

      if let name = library.currentSongName {
        Text(name)
          .lineLimit(1)
      }

      Spacer()

      Button {
        withAnimation(.easeInOut(duration: 0.4)) {
          isShowingVisualizer = true
        }
      } label: {
        Image(systemName: "sparkles.tv")
      }
    }
  }
}

#Preview {
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
}
