//
//  SpatialFormView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/18/26.
//

import SceneKit
import SwiftUI

/// Edits the spatial rose parameters for all tracks in a song.
struct SpatialFormView: View {
  @Environment(SongPlaybackState.self) private var playbackState
  @Environment(SpatialAudioEngine.self) private var engine
  @State private var isShowingVisualizer = false

  var body: some View {
    Text("Change how sounds move in space. Sounds in the same preset use the same path but with staggered positions.")
    Form {
      let roseTracks = playbackState.tracks.filter {
        $0.spatialPreset.presets.first?.positionLFO != nil
      }
      // 3D Rose visualizer (first track with a positionLFO)
      if let rose = roseTracks.first?.spatialPreset.presets.first?.positionLFO {
        Section {
          RoseSceneView(rose: rose)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .listRowInsets(EdgeInsets())
        }
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
#Preview("Spatial Form") {
  let engine = SpatialAudioEngine()
  let song = Song(name: "Preview Song", patternFileNames: ["aurora_arpeggio.json"])
  let state = SongPlaybackState(song: song, engine: engine)
  NavigationStack {
    SpatialFormView()
      .environment(state)
      .environment(engine)
  }
}

#Preview("Rose 3D") {
  RoseSceneView(rose: Rose(
    amp: ArrowConst(value: 3),
    leafFactor: ArrowConst(value: 4),
    freq: ArrowConst(value: 0.25),
    phase: 0
  ))
  .frame(height: 300)
  .clipShape(RoundedRectangle(cornerRadius: 12))
  .padding()
}

