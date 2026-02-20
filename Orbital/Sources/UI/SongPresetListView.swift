//
//  SongPresetListView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongPresetListView: View {
  @Environment(SongPlaybackState.self) private var playbackState
  let song: Song
  @State private var editingTrackId: Int?

  var body: some View {
    List(playbackState.tracks) { track in
      NavigationLink {
        PresetPickerView(trackId: track.id, currentPresetName: track.presetSpec.name)
          .environment(playbackState)
      } label: {
        VStack(alignment: .leading) {
          Text(track.presetSpec.name)
          Text(track.patternName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .overlay(alignment: .trailing) {
        if track.presetSpec.arrow != nil {
          Button {
            editingTrackId = track.id
          } label: {
            Image(systemName: "slider.horizontal.3")
              .font(.title3)
              .padding(.trailing, 28) // clear the chevron
          }
          .buttonStyle(.plain)
        }
      }
    }
    .navigationDestination(item: $editingTrackId) { trackId in
      if let track = playbackState.tracks.first(where: { $0.id == trackId }) {
        PresetFormView(presetSpec: track.presetSpec, spatialPreset: track.spatialPreset)
          .environment(playbackState)
      }
    }
    .navigationTitle(song.name)
    .toolbar {
      ToolbarItemGroup {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
      }
    }
    .task {
      try? await playbackState.loadTracks()
    }
  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let song = Song(
    name: "Aurora Borealis",
    patternFileNames: ["aurora_arpeggio.json"]
  )
  let playbackState = SongPlaybackState(song: song, engine: engine)
  NavigationStack {
    SongPresetListView(song: song)
  }
  .environment(engine)
  .environment(playbackState)
}
