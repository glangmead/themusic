//
//  SongSettingsView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/19/26.
//

import SwiftUI

/// A combined settings view for a song, with sections for Patterns, Presets, and Spatial.
struct SongSettingsView: View {
  @Environment(SpatialAudioEngine.self) private var engine: SpatialAudioEngine?
  @Environment(SongPlaybackState.self) private var playbackState
  let song: Song
  @State private var isShowingVisualizer = false
  @State private var editingTrackId: Int?

  var body: some View {
    List {
      // MARK: - Patterns
      Section("Patterns") {
        ForEach(playbackState.tracks) { track in
          NavigationLink {
            PatternFormView(track: track)
              .environment(playbackState)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(track.patternName)
              HStack(spacing: 8) {
                Text(track.patternSpec.noteGenerator.displayTypeName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(track.patternSpec.noteGenerator.displaySummary)
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
      }

      // MARK: - Presets
      Section("Presets") {
        ForEach(playbackState.tracks) { track in
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
                  .padding(.trailing, 28)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }

      // MARK: - Spatial
      Section("Spatial") {
        let roseTracks = playbackState.tracks.filter {
          $0.spatialPreset.presets.first?.positionLFO != nil
        }
        if roseTracks.isEmpty {
          Text("Press play to load spatial parameters.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(roseTracks) { track in
            NavigationLink {
              SpatialFormView()
                .environment(playbackState)
            } label: {
              Text(track.patternName)
            }
          }
        }
      }
    }
    .navigationDestination(item: $editingTrackId) { trackId in
      if let track = playbackState.tracks.first(where: { $0.id == trackId }) {
        PresetFormView(presetSpec: track.presetSpec)
          .environment(playbackState)
      }
    }
    .navigationTitle(song.name)
    .onAppear {
      playbackState.loadTracks()
    }
    .toolbar {
      ToolbarItemGroup {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
        Button {
          playbackState.stop()
        } label: {
          Image(systemName: "stop.fill")
        }
        .disabled(!playbackState.isPlaying)
        Button {
          playbackState.restart()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
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
      if let engine {
        VisualizerView(engine: engine, noteHandler: playbackState.noteHandler, isPresented: $isShowingVisualizer)
          .ignoresSafeArea()
      }
    }
  }
}

#Preview {
  let song = Song(
    name: "Aurora Borealis",
    patternFileNames: ["aurora_arpeggio.json"]
  )
  let playbackState = SongPlaybackState(song: song)
  NavigationStack {
    SongSettingsView(song: song)
  }
  .environment(playbackState)
}

