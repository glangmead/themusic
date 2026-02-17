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
          ensurePlaybackState().togglePlayback()
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
          .font(.headline)

        Spacer()
      }

      HStack(spacing: 12) {
        // Pattern button (placeholder)
        Button {
          // TODO: Pattern editor
        } label: {
          Label("Pattern", systemImage: "waveform")
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .disabled(true)

        // Presets button
        NavigationLink {
          SongPresetListView(song: song)
            .environment(ensurePlaybackState())
        } label: {
          Label("Presets", systemImage: "slider.horizontal.3")
            .font(.caption)
        }
        .buttonStyle(.bordered)

        // Spatial button (placeholder)
        Button {
          // TODO: Spatial editor
        } label: {
          Label("Spatial", systemImage: "globe")
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .disabled(true)
      }
    }
    .padding()
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  @discardableResult
  private func ensurePlaybackState() -> SongPlaybackState {
    if let state = playbackState { return state }
    let state = SongPlaybackState(song: song, engine: engine)
    playbackState = state
    return state
  }
}
