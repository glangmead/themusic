//
//  SongPresetListView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongPresetListView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongPlaybackState.self) private var playbackState
  let song: Song
  @State private var isShowingVisualizer = false

  var body: some View {
    List(playbackState.tracks) { track in
      NavigationLink {
        PresetFormView(presetSpec: track.presetSpec)
          .environment(playbackState)
      } label: {
        VStack(alignment: .leading) {
          Text(track.presetSpec.name)
          Text(track.patternName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle(song.name)
    .toolbar {
      ToolbarItem {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying ? "stop.fill" : "play.fill")
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(playbackState.isPlaying ? Color.red : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
      }
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
    .fullScreenCover(isPresented: $isShowingVisualizer) {
      VisualizerView(engine: engine, noteHandler: playbackState.noteHandler, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
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
