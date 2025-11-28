//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import SwiftUI
import Tonic

struct TheoryView: View {
  @State private var synth: KnobbySynth
  @State private var fxExpanded = true
  @State private var ampADSRExpanded = true
  @State private var roseParamsExpanded = true
  @State private var synthExpanded = true

  @State private var key = Key.C
  @State private var octave: Int = 2
  @State private var seq: Sequencer
  
  @State private var engineOn: Bool
  
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
  
  init(synth: KnobbySynth) {
    self.synth = synth
    // the sequencer will pluck on the arrows
    self.seq = Sequencer(synth: synth, numTracks: 2)
    self.engineOn = true
  }
  
  var body: some View {
    NavigationStack {
      Section {
        KnobbySynthView(synth: synth)
      }
      Section {
        Picker("Key", selection: $key) {
          Text("C").tag(Key.C)
          Text("G").tag(Key.G)
          Text("D").tag(Key.D)
          Text("A").tag(Key.A)
          Text("E").tag(Key.E)
        }.pickerStyle(.segmented)
        Picker("Octave", selection: $octave) {
          ForEach(1..<7) { octave in
            Text("\(octave)")
          }
        }.pickerStyle(.segmented)
        
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 100, maximum: .infinity))
          ],
          content: {
            ForEach(keyChords, id: \.self) { chord in
              Button(chord.romanNumeralNotation(in: key) ?? chord.description) {
                seq.sendTonicChord(chord: chord, octave: octave)
                seq.play()
              }
              .frame(maxWidth: .infinity)
              //.font(.largeTitle)
              .buttonStyle(.borderedProminent)
            }
          }
        )
        HStack {
          Text("Engine")
          Toggle(isOn: $engineOn) {}
            .onChange(of: engineOn, initial: true) {
              if engineOn {
                Task {
                  try! synth.engine.start()
                }
              } else {
                Task {
                  synth.engine.pause()
                }
              }
            }
          Spacer()
          Button("Stop") {
            seq.stop() 
            seq.rewind()
          }
          .font(.largeTitle)
          .buttonStyle(.borderedProminent)
        }
      }
      .navigationTitle("⌘Scape")
    }
  }
}

#Preview {
  TheoryView(synth: KnobbySynth())
}
