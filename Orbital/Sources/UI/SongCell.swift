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
  @Binding var selectedSongID: Song.ID?

  @State private var playbackState: SongPlaybackState?

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }
  private var isLoading: Bool { playbackState?.isLoading == true }

  var body: some View {
    HStack {
      // Tappable title area for play/pause
      Button {
        library.play(song, engine: engine)
      } label: {
        HStack {
          Text(song.name)
          Spacer()
          if isLoading {
            ProgressView()
          } else {
            Image(systemName: isPaused ? "pause.fill" : "waveform")
              .foregroundStyle(.secondary)
              .opacity(isPlaying ? 1 : 0)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      // Single settings button
      Button { selectedSongID = song.id } label: {
        Image(systemName: "slider.horizontal.3")
      }
      .buttonStyle(.borderless)
    }
    .onAppear {
      if playbackState == nil {
        playbackState = library.playbackState(for: song, engine: engine)
      }
    }
    .alert(
      "Failed to Load Song",
      isPresented: Binding(
        get: { playbackState?.loadError != nil },
        set: { if !$0 { playbackState?.loadError = nil } }
      )
    ) {
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
  let song = Song(
    name: "Aurora Borealis",
    patternFileNames: ["aurora_arpeggio.json"]
  )
  library.songs = [song]
  _ = library.playbackState(for: song, engine: engine)
  return NavigationStack {
    List {
      SongCell(song: song, selectedSongID: .constant(nil))
    }
    .environment(engine)
    .environment(library)
  }
}

