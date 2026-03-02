//
//  MidiTracksFormView.swift
//  Orbital
//
//  Form-based editor for MIDI track patterns.
//

import SwiftUI

struct MidiTracksFormView: View {
  @Environment(SongDocument.self) private var playbackState

  @State private var bpm: CoreFloat
  private let midi: MidiTracksSyntax

  init(midi: MidiTracksSyntax) {
    self.midi = midi
    _bpm = State(initialValue: midi.bpm ?? 120.0)
  }

  var body: some View {
    Form {
      Section("Playback") {
        SliderWithField(label: "BPM", value: $bpm, range: 0.1...300)
      }
    }
    .navigationTitle(midi.filename.components(separatedBy: "/").last ?? midi.filename)
    .toolbar {
      ToolbarItemGroup {
        Button {
          applyChanges()
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
        Button {
          applyChanges()
          playbackState.restart()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
    }
    .onDisappear {
      applyChanges()
    }
  }

  private func applyChanges() {
    let updated = MidiTracksSyntax(
      filename: midi.filename,
      loop: midi.loop,
      bpm: bpm,
      tracks: midi.tracks
    )
    playbackState.replaceMidiPattern(updated)
  }
}
