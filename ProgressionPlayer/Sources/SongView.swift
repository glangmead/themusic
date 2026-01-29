//
//  SongView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/28/25.
//

import SwiftUI
import Tonic

struct SongView: View {
  @Environment(\.openWindow) private var openWindow
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
  @State private var isShowingPresetList = false
  
  var body: some View {
    NavigationStack {
      if songURL != nil {
        MidiInspectorView(midiURL: songURL!)
      }
      Text("Playback speed: \(seq?.avSeq.rate ?? 0)")
      Slider(value: $playbackRate, in: 0.001...20)
        .onChange(of: playbackRate, initial: true) {
          seq?.avSeq.rate = playbackRate
        }
        .padding()
      KnobbyKnob(value: $noteOffset, range: -100...100, stepSize: 1)
        .onChange(of: noteOffset, initial: true) {
          synth.poolVoice?.globalOffset = Int(noteOffset)
        }
      Text("\(seq?.sequencerTime ?? 0.0) (\(seq?.lengthinSeconds() ?? 0.0))")
        .navigationTitle("\(synth.name)")
        .toolbar {
          ToolbarItem() {
            Button("Edit") {
              #if targetEnvironment(macCatalyst)
              openWindow(id: "synth-window")
              #else
              isShowingSynth = true
              #endif
            }
          }
          ToolbarItem() {
            Button("Presets") {
              isShowingPresetList = true
            }
            .popover(isPresented: $isShowingPresetList) {
              PresetListView(isPresented: $isShowingPresetList)
                .frame(minWidth: 300, minHeight: 400)
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
            presetSpec: synth.presetSpec,
            engine: synth.engine,
            modulators: [
              "overallAmp": ArrowExponentialRandom(min: 0.0011, max: 0.77),
              "overallCentDetune": ArrowRandom(min: -5, max: 5),
//              "vibratoAmp": ArrowExponentialRandom(min: 2, max: 20),
//              "vibratoFreq": ArrowProd(innerArrs: [ArrowConst(value: 25), Noise()])
            ],
            // a pitch consists of: root (NoteClass), Scale, octave, degree (element of Scale)
            notes: MidiPitchAsChordGenerator(
              pitchGenerator: MidiPitchGenerator(
                scaleGenerator: [Scale.lydian].cyclicIterator(),
                degreeGenerator: Array(0...6).shuffledIterator(),
                rootNoteGenerator: [NoteClass.A].cyclicIterator(),
                octaveGenerator: [2, 3, 4, 5].shuffledIterator()
              )
            ),
            sustains: FloatSampler(min: 5, max: 5),
            gaps: FloatSampler(min: 0.1, max: 0.5)
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
    .onChange(of: synth.reloadCount) {
      seq?.stop()
      seq = Sequencer(synth: synth, numTracks: 2)
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
  let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")
  SongView()
    .environment(SyntacticSynth(engine: SpatialAudioEngine(), presetSpec: presetSpec))
}
