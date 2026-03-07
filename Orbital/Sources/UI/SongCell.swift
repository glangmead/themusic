//
//  SongCell.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongCell: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  let song: SongRef

  @State private var playbackState: SongDocument?
  @State private var isShowingLoadError = false

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }
  private var isLoading: Bool { playbackState?.isLoading == true }

  var body: some View {
    HStack {
      Button {
        library.play(song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
      } label: {
        if isLoading {
          ProgressView()
            .frame(width: 24, height: 24)
        } else {
          Image(systemName: isPlaying && !isPaused ? "pause.fill" : "play.fill")
            .foregroundStyle(isPlaying ? .primary : .secondary)
        }
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(isPlaying && !isPaused ? "Pause" : "Play")

      Text(song.name)

      Spacer()

      if isPlaying {
        Image(systemName: "waveform")
          .foregroundStyle(.secondary)
          .imageScale(.small)
      }
    }
    .task {
      if playbackState == nil {
        playbackState = library.playbackState(for: song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
      }
    }
    .onChange(of: playbackState?.loadError) {
      isShowingLoadError = playbackState?.loadError != nil
    }
    .alert("Failed to Load Song", isPresented: $isShowingLoadError) {
      Button("OK") { playbackState?.loadError = nil }
    } message: {
      if let error = playbackState?.loadError {
        Text(error)
      }
    }
  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let library = SongLibrary()
  let resourceManager = ResourceManager()
  let song = SongRef(
    name: "Aurora Borealis",
    patternFileName: "table/aurora_arpeggio.json"
  )
  library.songs = [song]
  _ = library.playbackState(for: song, engine: engine)
  return NavigationStack {
    List {
      SongCell(song: song)
    }
    .environment(engine)
    .environment(library)
    .environment(resourceManager)
  }
}
