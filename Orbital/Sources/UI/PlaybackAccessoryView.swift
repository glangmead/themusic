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
  @State private var isShowingEventLog = false

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
          // Show subtitle (e.g. composer name from Classics) first; fall back to chord label.
          let secondaryText = state?.song.subtitle ?? state?.currentChordLabel
          if let secondary = secondaryText {
            Text(secondary)
              .font(.caption.italic())
              .lineLimit(1)
              .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.2), value: state?.song.subtitle ?? state?.currentChordLabel)

        Spacer()
      }

      if placement == .inline {
        AccessoryButtons(isShowingVisualizer: $isShowingVisualizer)
          .buttonStyle(.glass)
      } else {
        AccessoryButtons(isShowingVisualizer: $isShowingVisualizer)
      }
    }
    .padding(.horizontal)
    .contentShape(.rect)
    .onTapGesture { isShowingEventLog = true }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Show Event Log")
    .sheet(isPresented: $isShowingEventLog) {
      if let state {
        EventLogSheet(state: state)
      }
    }
  }
}
