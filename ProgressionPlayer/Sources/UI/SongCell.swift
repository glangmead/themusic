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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        // Play/Stop button
        Button {
          playbackState?.togglePlayback()
        } label: {
          Image(systemName: playbackState?.isPlaying == true ? "stop.fill" : "play.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(playbackState?.isPlaying == true ? Color.red : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)

        // Song name
        Text(song.name)
          .font(.largeTitle).fontWeight(.bold)

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
    .contentShape(Rectangle())
    .onTapGesture {
      playbackState?.togglePlayback()
    }
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
      patternFileName: "aurora_arpeggio.json",
      presetFileNames: ["auroraBorealis.json"]
    ))
    .padding()
    .environment(SpatialAudioEngine())
  }
}

