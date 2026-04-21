//
//  NowPlayingHeaderView.swift
//  Orbital
//

import SwiftUI

/// Title, composer, type / BPM line, and the large live chord label for the
/// Now Playing view. Fetches `PatternMetadata` lazily via `SongLibrary` in the
/// same manner as `SongCell`.
struct NowPlayingHeaderView: View {
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  let state: SongDocument

  @State private var metadata: PatternMetadata?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(state.song.name)
        .font(.largeTitle.bold())
        .lineLimit(2)

      if let subtitle = state.song.subtitle {
        Text(subtitle)
          .font(.title3.italic())
          .foregroundStyle(.secondary)
      }

      Text(metadata?.subtitle ?? " ")
        .font(.caption)
        .textCase(.uppercase)
        .tracking(0.5)
        .foregroundStyle(.tertiary)

      if let chord = state.currentChordLabel {
        Text(chord)
          .font(.system(size: 48, weight: .heavy, design: .default))
          .foregroundStyle(.primary)
          .padding(.top, 8)
          .transition(.opacity)
          .id(chord)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.easeInOut(duration: 0.2), value: state.currentChordLabel)
    .task(loadMetadata)
  }

  @Sendable
  private func loadMetadata() async {
    if metadata == nil {
      metadata = await library.metadata(for: state.song, resourceBaseURL: resourceManager.resourceBaseURL)
    }
  }
}
