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
  @Environment(SpatialAudioEngine.self) private var engine
  @State private var synth: SyntacticSynth?
  @State private var seq: Sequencer?
  @State private var error: Error? = nil
  @State private var isImporting = false
  @State private var songURL: URL?
  @State private var playbackRate: Float = 1.0
  @State private var isShowingSynth = false
  @State private var isShowingVisualizer = false
  @State private var noteOffset: Float = 0
  @State private var musicPattern: MusicPattern? = nil
  @State private var patternSpatialPreset: SpatialPreset? = nil
  @State private var patternPlaybackHandle: Task<Void, Error>? = nil
  @State private var isShowingPresetList = false
  
  var body: some View {
    if let synth {
      SongViewContent(
        engine: engine,
        synth: synth,
        seq: $seq,
        error: $error,
        isImporting: $isImporting,
        songURL: $songURL,
        playbackRate: $playbackRate,
        isShowingSynth: $isShowingSynth,
        isShowingVisualizer: $isShowingVisualizer,
        noteOffset: $noteOffset,
        musicPattern: $musicPattern,
        patternSpatialPreset: $patternSpatialPreset,
        patternPlaybackHandle: $patternPlaybackHandle,
        isShowingPresetList: $isShowingPresetList
      )
    } else {
      ProgressView()
        .onAppear {
          let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "auroraBorealis.json", subdirectory: "presets")
          synth = SyntacticSynth(engine: engine, presetSpec: presetSpec)
        }
    }
  }
}

private struct SongViewContent: View {
  @Environment(\.openWindow) private var openWindow
  let engine: SpatialAudioEngine
  @Bindable var synth: SyntacticSynth
  @Binding var seq: Sequencer?
  @Binding var error: Error?
  @Binding var isImporting: Bool
  @Binding var songURL: URL?
  @Binding var playbackRate: Float
  @Binding var isShowingSynth: Bool
  @Binding var isShowingVisualizer: Bool
  @Binding var noteOffset: Float
  @Binding var musicPattern: MusicPattern?
  @Binding var patternSpatialPreset: SpatialPreset?
  @Binding var patternPlaybackHandle: Task<Void, Error>?
  @Binding var isShowingPresetList: Bool

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
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
            synth.noteHandler?.globalOffset = Int(noteOffset)
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
              .disabled(synth.noteHandler == nil)
            }
            ToolbarItem() {
              Button("Presets") {
                isShowingPresetList = true
              }
#if targetEnvironment(macCatalyst)
              .sheet(isPresented: $isShowingPresetList) {
                PresetListView(synth: synth, isPresented: $isShowingPresetList)
                  .frame(minWidth: 300, minHeight: 400)
              }
#else
              .popover(isPresented: $isShowingPresetList) {
                PresetListView(synth: synth, isPresented: $isShowingPresetList)
                  .frame(minWidth: 300, minHeight: 400)
              }
#endif
            }
            ToolbarItem() {
              Button {
                withAnimation(.easeInOut(duration: 0.4)) {
                  isShowingVisualizer = true
                }
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
            songURL = Bundle.main.url(forResource: song, withExtension: "mid", subdirectory: "patterns")
            seq?.playURL(url: songURL!)
          }
        }
        Button("Play Pattern") {
          if patternPlaybackHandle == nil {
            // Create a dedicated SpatialPreset for the pattern
            let sp = SpatialPreset(presetSpec: synth.presetSpec, engine: engine, numVoices: 20)
            patternSpatialPreset = sp
            // a test song
            musicPattern = MusicPattern(
              spatialPreset: sp,
              modulators: [
                "overallAmp": ArrowProd(innerArrs: [
                  ArrowExponentialRandom(min: 0.3, max: 0.6)
                ]),
                "overallAmp2": EventUsingArrow(ofEvent: { event, _ in 1.0 / (CoreFloat(event.notes[0].note % 12) + 1.0)  }),
                "overallCentDetune": ArrowRandom(min: -5, max: 5),
                "vibratoAmp": ArrowExponentialRandom(min: 0.002, max: 0.1),
                "vibratoFreq": ArrowRandom(min: 1, max: 25)
              ],
              // sequences of chords according to a Mozart/Bach corpus according to Tymoczko
              notes: Midi1700sChordGenerator(
                scaleGenerator: [Scale.major].cyclicIterator(),
                rootNoteGenerator: [NoteClass.A].cyclicIterator()
              ),
              sustains: FloatSampler(min: 5, max: 10),
              gaps: FloatSampler(min: 5, max: 10 )
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
          patternSpatialPreset?.cleanup()
          patternSpatialPreset = nil
        }
        Button("Rewind") {
          seq?.stop()
          seq?.rewind()
        }
      }
      .toolbar(isShowingVisualizer ? .hidden : .visible, for: .tabBar)
      .toolbar(isShowingVisualizer ? .hidden : .visible, for: .navigationBar)
      
    }
    .fullScreenCover(isPresented: $isShowingVisualizer) {
      VisualizerView(engine: engine, noteHandler: synth.noteHandler, isPresented: $isShowingVisualizer)
        .ignoresSafeArea()
    }
    .onAppear {
      if seq == nil {
        seq = Sequencer(engine: engine.audioEngine, numTracks: 2, defaultHandler: synth.noteHandler!)
        try! engine.start()
      }
    }
    .onChange(of: synth.reloadCount) {
      seq?.stop()
      seq = Sequencer(engine: engine.audioEngine, numTracks: 2, defaultHandler: synth.noteHandler!)
    }
    .sheet(isPresented: $isShowingSynth) {
      NavigationStack {
        PresetFormView(synth: synth)
      }
    }
  }
}

#Preview {
  SongView()
    .environment(SpatialAudioEngine())
}
