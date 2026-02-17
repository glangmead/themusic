//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import SwiftUI
import Tonic

struct TheoryView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @State private var synth: SyntacticSynth?

  var body: some View {
    if let synth {
      TheoryViewContent(engine: engine, synth: synth)
    } else {
      ProgressView()
        .onAppear {
          let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "auroraBorealis.json", subdirectory: "presets")
          synth = SyntacticSynth(engine: engine, presetSpec: presetSpec)
        }
    }
  }
}

private struct TheoryViewContent: View {
  @Environment(\.openWindow) private var openWindow
  let engine: SpatialAudioEngine
  @Bindable var synth: SyntacticSynth
  @State private var fxExpanded = true
  @State private var ampADSRExpanded = true
  @State private var roseParamsExpanded = true
  @State private var isShowingSynth = false
  @State private var isShowingPresetList = false
  
  @State private var key = Key.C
  @State private var octave: Int = 2
  @State private var seq: Sequencer?
  @State private var noteOffset: Float = 0
  
  @State private var engineOn: Bool = true
  
  @FocusState private var isFocused: Bool
  
  var keyChords: [Chord] {
    get {
      key.chords.filter { chord in
        [.major, .minor, .dim, .dom7, .maj7, .min7].contains(chord.type)
      }
      .sorted {
        $0.description < $1.description
      }
    }
  }
  
  var body: some View {
    NavigationStack {
      Section {
        Picker("Key", selection: $key) {
          Text("F").tag(Key.F)
          Text("C").tag(Key.C)
          Text("G").tag(Key.G)
          Text("D").tag(Key.D)
          Text("A").tag(Key.A)
          Text("E").tag(Key.E)
        }
        .pickerStyle(.segmented)
        
        Picker("Octave", selection: $octave) {
          ForEach(1..<7) { octave in
            Text("\(octave)")
          }
        }
        .pickerStyle(.segmented)
        
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 100, maximum: .infinity))
          ],
          content: {
            ForEach(keyChords, id: \.self) { chord in
              Button(chord.romanNumeralNotation(in: key) ?? chord.description) {
                seq?.sendTonicChord(chord: chord, octave: octave)
                seq?.play()
              }
              .frame(maxWidth: .infinity)
              //.font(.largeTitle)
              .buttonStyle(.borderedProminent)
            }
          }
        )
        
        KnobbyKnob(value: $noteOffset, range: -50...50, stepSize: 1)
          .onChange(of: noteOffset, initial: true) {
            synth.noteHandler?.globalOffset = Int(noteOffset)
          }
        
        HStack {
          Text("Engine")
          Toggle(isOn: $engineOn) {}
            .onChange(of: engineOn, initial: true) {
              if engineOn {
                Task {
                  try! engine.start()
                }
              } else {
                Task {
                  engine.pause()
                }
              }
            }
          Spacer()
          Button("Stop") {
            seq?.stop()
          }
          .font(.largeTitle)
          .buttonStyle(.borderedProminent)
        }
        .toolbar {
          Button("Edit") {
#if targetEnvironment(macCatalyst)
            openWindow(id: "synth-window")
#else
            isShowingSynth = true
#endif
          }
          .disabled(synth.noteHandler == nil)
          Button("Presets") {
            isShowingPresetList = true
          }
          .popover(isPresented: $isShowingPresetList) {
            PresetListView(synth: synth, isPresented: $isShowingPresetList)
              .frame(minWidth: 300, minHeight: 400)
          }
        }
        .navigationTitle("\(synth.name)")
      }
      .focusable()
      .focused($isFocused)
      .onAppear(perform: {isFocused = true})
      .onKeyPress(phases: [.up, .down], action: playKey)
      Spacer()
    }
    .onChange(of: isShowingSynth, { isFocused = !isShowingSynth})
    .onAppear {
      if seq == nil {
        seq = Sequencer(engine: engine.audioEngine, numTracks: 2, defaultHandler: synth.noteHandler!)
      }
    }
    .onChange(of: synth.reloadCount) {
      seq?.stop()
      seq = Sequencer(engine: engine.audioEngine, numTracks: 2, defaultHandler: synth.noteHandler!)
    }
    .sheet(isPresented: $isShowingSynth) {
      SyntacticSynthView(synth: synth)
    }
  }
  
  func playKey(keyPress: KeyPress) -> KeyPress.Result {
    let charToMidiNote:[String:Int] = [
      "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67, "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75
    ]
    if let noteValue = charToMidiNote[keyPress.characters], keyPress.modifiers.rawValue == 0 {
      switch keyPress.phase {
      case .down:
        synth.noteHandler?.noteOn(MidiNote(note: UInt8(noteValue), velocity: 100))
      case .up:
        synth.noteHandler?.noteOff(MidiNote(note: UInt8(noteValue), velocity: 100))
      default:
        ()
      }
      return .handled
    }
    return .ignored
  }
  
}

#Preview {
  TheoryView()
    .environment(SpatialAudioEngine())
}
