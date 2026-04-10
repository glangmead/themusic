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
  @Environment(ResourceManager.self) private var resourceManager
  let song: SongRef

  @State private var playbackState: SongDocument?
  @State private var metadata: PatternMetadata?
  @State private var isShowingLoadError = false

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }
  private var isLoading: Bool { playbackState?.isLoading == true }

  var body: some View {
    Button(action: togglePlayback) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(song.name)
            .foregroundStyle(.primary)
          Text(metadata?.subtitle ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isLoading {
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
        } else if isPlaying && !isPaused {
          Image(systemName: "waveform")
            .foregroundStyle(.secondary)
            .imageScale(.small)
            .accessibilityHidden(true)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityHint(accessibilityHintText)
    .task(loadCellState)
    .onChange(of: playbackState?.loadError) {
      isShowingLoadError = playbackState?.loadError != nil
    }
    .alert("Failed to Load Song", isPresented: $isShowingLoadError) {
      Button("OK") { playbackState?.loadError = nil }
    } message: {
      if let error = playbackState?.loadError {
        Text(error)
      }
    }
  }

  private var accessibilityHintText: String {
    if isLoading { return "Loading" }
    return isPlaying && !isPaused ? "Pauses playback" : "Plays this song"
  }

  private func togglePlayback() {
    library.play(song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
  }

  @Sendable
  private func loadCellState() async {
    if playbackState == nil {
      playbackState = library.playbackState(for: song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
    }
    if metadata == nil {
      metadata = await library.metadata(for: song, resourceBaseURL: resourceManager.resourceBaseURL)
    }
  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let library = SongLibrary()
  let resourceManager = ResourceManager()
  let song = SongRef(patternFileName: "table/Aurora Arpeggio.json")
  library.songs = [song]
  _ = library.playbackState(for: song, engine: engine)
  return NavigationStack {
    List {
      SongCell(song: song)
    }
    .environment(engine)
    .environment(library)
    .environment(resourceManager)
  }
}
