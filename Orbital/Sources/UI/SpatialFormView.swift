//
//  SpatialFormView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/18/26.
//

import SwiftUI

/// Edits the spatial rose parameters for all tracks in a song.
struct SpatialFormView: View {
  @Environment(SongDocument.self) private var playbackState

  var body: some View {
    Form {
      Text("Change how sounds move in space. Sounds in the same preset use the same path but with staggered positions.")
      let rosePairs: [(TrackInfo, SpatialPreset)] = playbackState.tracks.compactMap { track in
        guard let sp = playbackState.spatialPreset(forTrack: track.id),
              sp.presets.first?.positionLFO != nil else { return nil }
        return (track, sp)
      }
      // 3D Rose visualizer (first track with a positionLFO)
      if let rose = rosePairs.first?.1.presets.first?.positionLFO {
        Section {
          RoseSceneView(rose: rose)
            .frame(height: 600)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .listRowInsets(EdgeInsets())
        }
      }

      if rosePairs.isEmpty {
        ContentUnavailableView(
          "No Spatial Data",
          systemImage: "globe",
          description: Text("Press play to load spatial parameters.")
        )
      } else {
        ForEach(rosePairs, id: \.0.id) { track, spatialPreset in
          Section(track.patternName) {
            RoseSliders(spatialPreset: spatialPreset)
          }
        }
      }
    }
    .navigationTitle("Spatial")
    .task {
      try? await playbackState.loadTracks()
    }
    .toolbar {
      ToolbarItemGroup {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
      }
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
  let song = SongRef(name: "Preview Song", patternFileName: "aurora_arpeggio.json")
  let state = SongDocument(song: song, engine: engine)
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
