//
//  SpatialFormView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/18/26.
//

import SwiftUI

/// Edits the spatial rose parameters for all tracks in a song.
struct SpatialFormView: View {
  @Environment(SongPlaybackState.self) private var playbackState
  @Environment(SpatialAudioEngine.self) private var engine
  @State private var isShowingVisualizer = false

  var body: some View {
    Form {
      let roseTracks = playbackState.tracks.filter {
        $0.spatialPreset.presets.first?.positionLFO != nil
      }
      if roseTracks.isEmpty {
        ContentUnavailableView(
          "No Spatial Data",
          systemImage: "globe",
          description: Text("Press play to load spatial parameters.")
        )
      } else {
        ForEach(roseTracks) { track in
          Section(track.patternName) {
            RoseSliders(spatialPreset: track.spatialPreset)
          }
        }
      }
    }
    .navigationTitle("Spatial")
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
      VisualizerView(engine: engine, noteHandler: playbackState.noteHandler, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
    }
  }
}

/// Sliders for a single track's rose parameters, reading/writing directly
/// to the live `positionLFO` on every `Preset` in the `SpatialPreset`.
private struct RoseSliders: View {
  let spatialPreset: SpatialPreset

  @State private var amp: CoreFloat = 0
  @State private var freq: CoreFloat = 0
  @State private var leaves: CoreFloat = 0

  var body: some View {
    LabeledSlider(value: $amp, label: "Amplitude", range: 0...20)
      .onChange(of: amp) { _, newValue in
        spatialPreset.presets.forEach { $0.positionLFO?.amp.val = newValue }
      }
    LabeledSlider(value: $freq, label: "Frequency", range: 0...30)
      .onChange(of: freq) { _, newValue in
        spatialPreset.presets.forEach { $0.positionLFO?.freq.val = newValue }
      }
    LabeledSlider(value: $leaves, label: "Leaves", range: 0...30)
      .onChange(of: leaves) { _, newValue in
        spatialPreset.presets.forEach { $0.positionLFO?.leafFactor.val = newValue }
      }
  }

  init(spatialPreset: SpatialPreset) {
    self.spatialPreset = spatialPreset
    let lfo = spatialPreset.presets.first?.positionLFO
    _amp = State(initialValue: lfo?.amp.val ?? 0)
    _freq = State(initialValue: lfo?.freq.val ?? 0)
    _leaves = State(initialValue: lfo?.leafFactor.val ?? 0)
  }
}
