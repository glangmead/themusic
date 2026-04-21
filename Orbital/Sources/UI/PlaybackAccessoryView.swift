//
//  PlaybackAccessoryView.swift
//  Orbital
//

import SwiftUI

struct PlaybackAccessoryView: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  let state: SongDocument?
  @Binding var isShowingVisualizer: Bool
  var onTap: () -> Void

  var body: some View {
    HStack {
      if placement != .inline {
        if library.isLoading {
          ProgressView()
        }

        VStack(alignment: .leading, spacing: 2) {
          if let name = library.currentSongName {
            Text(name)
              .lineLimit(1)
          }
          let secondaryText = state?.song.subtitle ?? state?.currentChordLabel
          if let secondary = secondaryText {
            Text(secondary)
              .font(.caption.italic())
              .lineLimit(1)
              .transition(.opacity)
          }
          if let seed = state?.currentSeedString, state?.hasRandomness == true {
            Button {
              UIPasteboard.general.string = seed
            } label: {
              Text("seed \(seed)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seed " + seed.map(String.init).joined(separator: " "))
            .accessibilityHint("Double-tap to copy seed to clipboard")
          }
        }
        .animation(.easeInOut(duration: 0.2), value: state?.song.subtitle ?? state?.currentChordLabel)

        Spacer()
      }

      if placement == .inline {
        TransportControls(isShowingVisualizer: $isShowingVisualizer, style: .compact)
          .buttonStyle(.glass)
      } else {
        TransportControls(isShowingVisualizer: $isShowingVisualizer, style: .compact)
      }
    }
    .padding(.horizontal)
    .contentShape(.rect)
    .onTapGesture { onTap() }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Show Now Playing")
  }
}
