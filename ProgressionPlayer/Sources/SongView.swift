//
//  SongView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/28/25.
//

import SwiftUI
import Tonic

struct SongView: View {
  @Environment(SyntacticSynth.self) private var synth
  @State private var seq: Sequencer?
  @State private var error: Error? = nil
  @State private var isImporting = false
  @State private var songURL: URL?
  @State private var playbackRate: Float = 1.0
  @State private var isShowingSynth = false
  @State private var isShowingVisualizer = false
  @State private var noteOffset: Float = 0
  @State private var musicPattern: MusicPattern? = nil
  @State private var patternPlaybackHandle: Task<Void, Error>? = nil

  var body: some View {
    NavigationStack {
      if songURL != nil {
        MidiInspectorView(midiURL: songURL!)
      }
      Text("Playback speed: \(seq?.avSeq.rate ?? 0)")
      Slider(value: $playbackRate, in: 0...20)
        .onChange(of: playbackRate, initial: true) {
          seq?.avSeq.rate = playbackRate
        }
      KnobbyKnob(value: $noteOffset, range: -100...100, stepSize: 1)
        .onChange(of: noteOffset, initial: true) {
          synth.poolVoice?.globalOffset = Int(noteOffset)
        }
      Text("\(seq?.sequencerTime ?? 0.0) (\(seq?.lengthinSeconds() ?? 0.0))")
        .navigationTitle("⌘Scape")
        .toolbar {
          ToolbarItem() {
            Button("Synth") {
              isShowingSynth = true
            }
          }
          ToolbarItem() {
            Button {
              isShowingVisualizer = true
            } label: {
              Label("Visualizer", systemImage: "sparkles.tv")
            }
          }
          ToolbarItem() {
            Button {
              isImporting = true
            } label: {
              Label("Import file",
                    systemImage: "document")
            }
          }
        }
        .fileImporter(
          isPresented: $isImporting,
          allowedContentTypes: [.midi],
          allowsMultipleSelection: false
        ) { result in
          switch result {
          case .success(let urls):
            seq?.playURL(url: urls[0])
            songURL = urls[0]
          case .failure(let error):
            print("\(error.localizedDescription)")
          }
        }
      ForEach(["D_Loop_01", "MSLFSanctus", "All-My-Loving", "BachInvention1"], id: \.self) { song in
        Button("Play \(song)") {
          songURL = Bundle.main.url(forResource: song, withExtension: "mid")
          seq?.playURL(url: songURL!)
        }
      }
      Button("Play Pattern") {
        if patternPlaybackHandle == nil {
          // a test song
          musicPattern = MusicPattern(
            synth: synth,
            modulators: [:],//["vibratoAmp": ArrowLine(0, 1, 7)],
            notes: ScaleSampler().makeIterator(),
            sustains: FloatSampler(min: 4, max: 5),
            gaps: FloatSampler(min: 1, max: 2)
          )
          patternPlaybackHandle = Task.detached {
            await musicPattern?.play()
          }
        }
      }
      Button("Play") {
        seq?.play()
      }
      Button("Stop") {
        seq?.stop()
        patternPlaybackHandle?.cancel()
        patternPlaybackHandle = nil
      }
      Button("Rewind") {
        seq?.stop()
        seq?.rewind()
      }
    }
    .onAppear {
      if seq == nil {
        seq = Sequencer(synth: synth, numTracks: 2)
        try! synth.engine.start()
      }
    }
    .sheet(isPresented: $isShowingSynth) {
      SyntacticSynthView(synth: synth)
    }
    .fullScreenCover(isPresented: $isShowingVisualizer) {
      ZStack(alignment: .topTrailing) {
        VisualizerView(synth: synth)
          .edgesIgnoringSafeArea(.all)
      }
    }

  }
}

#Preview {
  SongView()
    .environment(SyntacticSynth(engine: SpatialAudioEngine()))
}
