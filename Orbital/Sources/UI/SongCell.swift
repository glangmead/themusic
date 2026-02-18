//
//  SongCell.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongCell: View {
  @Environment(SpatialAudioEngine.self) private var engine
  let song: Song

  @State private var playbackState: SongPlaybackState?

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        // Play/Pause button
        Button {
          playbackState?.togglePlayback()
        } label: {
          Image(systemName: isPlaying && !isPaused ? "pause.fill" : "play.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(isPlaying && !isPaused ? Color.gray : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)

        // Stop button — visible when playing or paused
        if isPlaying {
          Button {
            playbackState?.stop()
          } label: {
            Image(systemName: "stop.fill")
              .font(.title3)
              .foregroundStyle(.white)
              .frame(width: 36, height: 36)
              .background(Color.red)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
        }

        // Song name
        Text(song.name)
          .font(.title).fontWeight(.bold)

        Spacer()
      }

      HStack(spacing: 12) {
        // Pattern button (placeholder)
        Button {
          // TODO: Pattern editor
        } label: {
          Label("Pattern", systemImage: "waveform")
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .disabled(true)

        // Presets button
        if let playbackState {
          NavigationLink {
            SongPresetListView(song: song)
              .environment(playbackState)
          } label: {
            Label("Presets", systemImage: "slider.horizontal.3")
              .font(.subheadline)
          }
          .buttonStyle(.bordered)
        }

        // Spatial button (placeholder)
        Button {
          // TODO: Spatial editor
        } label: {
          Label("Spatial", systemImage: "globe")
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .disabled(true)
      }
    }
    .padding()
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onAppear {
      if playbackState == nil {
        playbackState = SongPlaybackState(song: song, engine: engine)
      }
    }
  }
}
#Preview {
  NavigationStack {
    SongCell(song: Song(
      name: "Aurora Borealis",
      patternFileNames: ["aurora_arpeggio.json"]
    ))
    .padding()
    .environment(SpatialAudioEngine())
  }
}

