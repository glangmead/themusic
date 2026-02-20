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
  let song: Song

  @State private var playbackState: SongPlaybackState?
  @State private var showSettings = false

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }

  var body: some View {
    HStack {
      // Tappable title area for play/pause
      Button {
        library.play(song, engine: engine)
      } label: {
        HStack {
          Text(song.name)
          Spacer()
          Image(systemName: isPaused ? "pause.fill" : "waveform")
            .foregroundStyle(.secondary)
            .opacity(isPlaying ? 1 : 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      // Single settings button
      Button { showSettings = true } label: {
        Image(systemName: "slider.horizontal.3")
      }
      .buttonStyle(.borderless)
    }
    .navigationDestination(isPresented: $showSettings) {
      if let playbackState {
        SongSettingsView(song: song)
          .environment(playbackState)
      }
    }
    .onAppear {
      if playbackState == nil {
        playbackState = library.playbackState(for: song, engine: engine)
      }
    }
  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let library = SongLibrary()
  let song = Song(
    name: "Aurora Borealis",
    patternFileNames: ["aurora_arpeggio.json"]
  )
  library.songs = [song]
  _ = library.playbackState(for: song, engine: engine)
  return NavigationStack {
    List {
      SongCell(song: song)
    }
    .environment(engine)
    .environment(library)
  }
}

