//
//  AccessoryButtons.swift
//  Orbital
//

import SwiftUI

struct AccessoryButtons: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    HStack(spacing: placement == .inline ? 12 : 20) {
      if !library.isLoading {
        Button(
          library.allPaused ? "Play" : "Pause",
          systemImage: library.allPaused ? "play.fill" : "pause.fill",
          action: togglePlayPause
        )
        Button("Stop", systemImage: "stop.fill", action: library.stopAll)
      }

      Button("Visualizer", systemImage: "sparkles.tv", action: showVisualizer)
    }
  }

  private func togglePlayPause() {
    if library.allPaused {
      library.resumeAll()
    } else {
      library.pauseAll()
    }
  }

  private func showVisualizer() {
    withAnimation(.easeInOut(duration: 0.4)) {
      isShowingVisualizer = true
    }
  }
}
