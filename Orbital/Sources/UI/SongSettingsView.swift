//
//  SongSettingsView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/19/26.
//

import SwiftUI

/// A combined settings view for a song, with sections for Patterns, Presets, and Spatial.
struct SongSettingsView: View {
  @Environment(SongDocument.self) private var playbackState
  let song: SongRef
  @State private var editingTrackId: Int?

  var body: some View {
    List {
      // MARK: - Patterns
      Section("Patterns") {
        if let table = playbackState.tablePattern {
          NavigationLink {
            TablePatternFormView(table: table)
              .environment(playbackState)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(table.name)
              Text("Table Pattern — \(table.tracks.count) track(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        } else {
          Text("MIDI pattern")
            .foregroundStyle(.secondary)
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
        if playbackState.runtime != nil {
          let rosePairs = playbackState.tracks.compactMap { track -> (TrackInfo, SpatialPreset)? in
            guard let sp = playbackState.spatialPreset(forTrack: track.id),
                  sp.presets.first?.positionLFO != nil else { return nil }
            return (track, sp)
          }
          if rosePairs.isEmpty {
            Text("No spatial data for this pattern.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(rosePairs, id: \.0.id) { track, _ in
              NavigationLink {
                SpatialFormView()
                  .environment(playbackState)
              } label: {
                Text(track.patternName)
              }
            }
          }
        } else {
          Text("Press play to load spatial parameters.")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationDestination(item: $editingTrackId) { trackId in
      if let track = playbackState.tracks.first(where: { $0.id == trackId }),
         let sp = playbackState.spatialPreset(forTrack: trackId) {
        PresetFormView(presetSpec: track.presetSpec, spatialPreset: sp)
          .environment(playbackState)
      }
    }
    .navigationTitle(song.name)
    .task {
      try? await playbackState.loadTracks()
    }
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
  }
}

#Preview {
  let song = SongRef(
    name: "Aurora Borealis",
    patternFileName: "aurora_arpeggio.json"
  )
  let playbackState = SongDocument(song: song)
  NavigationStack {
    SongSettingsView(song: song)
  }
  .environment(playbackState)
  .environment(ResourceManager())
}

