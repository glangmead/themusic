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
  @State private var patternSpatialPreset: SpatialPreset? = nil
  @State private var patternPlaybackHandle: Task<Void, Error>? = nil
  @State private var isShowingPresetList = false
  
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
              .popover(isPresented: $isShowingPresetList) {
                PresetListView(isPresented: $isShowingPresetList)
                  .frame(minWidth: 300, minHeight: 400)
              }
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
            songURL = Bundle.main.url(forResource: song, withExtension: "mid")
            seq?.playURL(url: songURL!)
          }
        }
        Button("Play Pattern") {
          if patternPlaybackHandle == nil {
            // Create a dedicated SpatialPreset for the pattern
            let sp = SpatialPreset(presetSpec: synth.presetSpec, engine: synth.engine, numVoices: 20)
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
              // Aurora Borealis
              // notes: MidiPitchAsChordGenerator(
              //   pitchGenerator: MidiPitchGenerator(
              //     scaleGenerator: [Scale.lydian].cyclicIterator(),
              //     degreeGenerator: Array(0...6).shuffledIterator(),
              //     rootNoteGenerator: WaitingIterator(
              //       iterator: [NoteClass.C, NoteClass.E, NoteClass.G].cyclicIterator(),
              //       timeBetweenChanges: ArrowRandom(min: 10, max: 25)
              //     ),
              //     octaveGenerator: [2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 5].randomIterator()
              //   )
              // ),
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
      .scaleEffect(isShowingVisualizer ? 0.85 : 1.0)
      .opacity(isShowingVisualizer ? 0.0 : 1.0)
      .toolbar(isShowingVisualizer ? .hidden : .visible, for: .tabBar)
      .toolbar(isShowingVisualizer ? .hidden : .visible, for: .navigationBar)
      
      if isShowingVisualizer {
        VisualizerView(synth: synth, isPresented: $isShowingVisualizer)
          .ignoresSafeArea()
          .transition(.opacity.animation(.easeInOut(duration: 0.5)))
          .zIndex(1)
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
  }
}

#Preview {
  let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")
  SongView()
    .environment(SyntacticSynth(engine: SpatialAudioEngine(), presetSpec: presetSpec))
}
