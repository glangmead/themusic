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
  let song: Song

  @State private var playbackState: SongPlaybackState?

  private var isPlaying: Bool { playbackState?.isPlaying == true }
  private var isPaused: Bool { playbackState?.isPaused == true }

  var body: some View {
    HStack(spacing: 12) {
      // Title button — its own interactive glass card
      Button {
        playbackState?.togglePlayback()
      } label: {
        Text(song.name)
          .font(.title3)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .modifier(TitleGlassModifier(isActive: isPlaying))
      .animation(.easeInOut(duration: 0.3), value: isPlaying)

      // Navigation buttons
      if let playbackState {
        VStack(alignment: .leading, spacing: 6) {
          NavigationLink {
            PatternListView(song: song)
              .environment(playbackState)
          } label: {
            Label("Pattern", systemImage: "waveform")
              .font(.caption)
              .foregroundStyle(.primary)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          NavigationLink {
            SongPresetListView(song: song)
              .environment(playbackState)
          } label: {
            Label("Presets", systemImage: "slider.horizontal.3")
              .font(.caption)
              .foregroundStyle(.primary)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          NavigationLink {
            SpatialFormView()
              .environment(playbackState)
          } label: {
            Label("Spatial", systemImage: "globe")
              .font(.caption)
              .foregroundStyle(.primary)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      // State icon
      Image(systemName: isPaused ? "pause.fill" : "waveform")
        .font(.title3)
        .foregroundStyle(.secondary)
        .opacity(isPlaying ? 1 : 0)
        .frame(width: 24)
    }
    .padding(.vertical, 4)
    .padding(.trailing, 8)
    .onAppear {
      if playbackState == nil {
        playbackState = library.playbackState(for: song, engine: engine)
      }
    }
  }
}

private struct TitleGlassModifier: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(
          .regular.interactive().tint(
            isActive ? .white.opacity(0.15) : Theme.colorHighlight.opacity(0.08)
          ),
          in: .rect(cornerRadius: 12)
        )
        .overlay {
          if isActive {
            ShimmerBorder(cornerRadius: 12)
          }
        }
    } else {
      content
        .background {
          RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
  }
}

/// An animated gradient that sweeps around the border of a rounded rectangle.
/// Uses a rotating linear gradient masked to a stroke shape instead of an
/// AngularGradient to avoid expensive per-frame CPU rasterisation
/// (CGContextDrawConicGradient). The rotation is a GPU-composited transform.
private struct ShimmerBorder: View {
  var cornerRadius: CGFloat = 16
  @State private var rotation: Double = 0

  private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius) }

  var body: some View {
    shape
      .stroke(lineWidth: 1.5)
      // Fill the stroke with a rotating gradient via the overlay + mask trick:
      // overlay provides the animated gradient, mask clips it to the stroke path.
      .foregroundStyle(.clear)
      .overlay {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.25),
            .init(color: Color.red.opacity(0.45), location: 0.40),
            .init(color: Color(red: 1.0, green: 0.85, blue: 0.85).opacity(0.6), location: 0.5),
            .init(color: Color.red.opacity(0.45), location: 0.60),
            .init(color: .clear, location: 0.75),
            .init(color: .clear, location: 1.0),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .rotationEffect(.degrees(rotation))
        .scaleEffect(3)
      }
      .mask { shape.stroke(lineWidth: 1.5) }
      .onAppear {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
          rotation = 360
        }
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
    .environment(SongLibrary())
  }
}

