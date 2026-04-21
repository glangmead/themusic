//
//  TransportControls.swift
//  Orbital
//

import SwiftUI

/// Play / pause / stop / visualizer buttons shared by the playback accessory
/// and the Now Playing view. `style` switches between icon-only (compact, used
/// in the accessory strip) and icon + title (expanded, used in the NP view).
struct TransportControls: View {
  @Environment(SongLibrary.self) private var library
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Binding var isShowingVisualizer: Bool
  var style: Style = .compact

  enum Style {
    case compact
    case expanded
  }

  var body: some View {
    Group {
      if style == .compact {
        buttons.labelStyle(.iconOnly)
      } else {
        buttons.labelStyle(.titleAndIcon)
      }
    }
  }

  private var buttons: some View {
    HStack(spacing: style == .compact ? compactSpacing : 24) {
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

  private var compactSpacing: CGFloat {
    placement == .inline ? 12 : 20
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
