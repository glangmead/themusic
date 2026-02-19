//
//  SongCell.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongCell: View {
  @Environment(SpatialAudioEngine.self) private var engine
  let song: Song

  @State private var playbackState: SongPlaybackState?

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text(song.name)
          .font(.title)

        Spacer()

        Button {
          playbackState?.togglePlayback()
        } label: {
          Image(systemName: isPlaying && !isPaused ? "pause.fill" : "play.fill")
            .font(.largeTitle)
        }
        .buttonStyle(.plain)

        Button {
          playbackState?.stop()
        } label: {
          Image(systemName: "stop.fill")
            .font(.largeTitle)
        }
        .buttonStyle(.plain)
        .disabled(!isPlaying)
      }

      HStack(spacing: 12) {
        // Pattern button (placeholder)
        Button {
          // TODO: Pattern editor
        } label: {
          Label("Pattern", systemImage: "waveform")
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .disabled(true)

        // Presets button
        if let playbackState {
          NavigationLink {
            SongPresetListView(song: song)
              .environment(playbackState)
          } label: {
            Label("Presets", systemImage: "slider.horizontal.3")
              .font(.subheadline)
          }
          .buttonStyle(.bordered)
        }

        // Spatial button (placeholder)
        Button {
          // TODO: Spatial editor
        } label: {
          Label("Spatial", systemImage: "globe")
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .disabled(true)
      }
    }
    .padding()
    .contentShape(Rectangle())
    .onTapGesture {
      playbackState?.togglePlayback()
    }
    .modifier(GlassCardModifier(isActive: isPlaying))
    .animation(.easeInOut(duration: 0.3), value: isPlaying)
    .onAppear {
      if playbackState == nil {
        playbackState = SongPlaybackState(song: song, engine: engine)
      }
    }
  }
}
private struct GlassCardModifier: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(
          isActive
            ? .regular.interactive().tint(.white.opacity(0.15))
            : .regular.interactive(),
          in: .rect(cornerRadius: 16)
        )
        .overlay {
          if isActive {
            ShimmerBorder()
          }
        }
    } else {
      content
        .background {
          RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
  }
}

/// An animated gradient that sweeps around the border of a rounded rectangle.
private struct ShimmerBorder: View {
  var body: some View {
    TimelineView(.animation) { context in
      let angle = Angle.degrees(
        context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360
      )
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(
          AngularGradient(
            stops: [
              .init(color: .clear, location: 0),
              .init(color: .clear, location: 0.3),
              .init(color: Theme.colorHighlight.opacity(0.35), location: 0.42),
              .init(color: .white.opacity(0.45), location: 0.5),
              .init(color: Theme.colorHighlight.opacity(0.35), location: 0.58),
              .init(color: .clear, location: 0.7),
              .init(color: .clear, location: 1.0),
            ],
            center: .center,
            angle: angle
          ),
          lineWidth: 1.5
        )
    }
  }
}

#Preview {
  NavigationStack {
    SongCell(song: Song(
      name: "Aurora Borealis",
      patternFileNames: ["aurora_arpeggio.json"]
    ))
    .padding()
    .environment(SpatialAudioEngine())
  }
}

