//
//  PatternListView.swift
//  Orbital
//

import SwiftUI

struct PatternListView: View {
  @Environment(SongPlaybackState.self) private var playbackState
  let song: Song

  var body: some View {
    List(playbackState.tracks) { track in
      NavigationLink {
        PatternFormView(track: track)
          .environment(playbackState)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(track.patternName)
          if let trackSpec = track.trackSpec {
            HStack(spacing: 8) {
              Text(trackSpec.noteGenerator.displayTypeName)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(trackSpec.noteGenerator.displaySummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
          } else {
            Text("MIDI")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Patterns")
    .toolbar {
      ToolbarItemGroup {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
        Button {
          playbackState.restart()
        } label: {
          Image(systemName: "arrow.counterclockwise")
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
    patternFileName: "aurora_arpeggio.json"
  )
  let playbackState = SongPlaybackState(song: song, engine: engine)
  NavigationStack {
    PatternListView(song: song)
  }
  .environment(engine)
  .environment(playbackState)
}
