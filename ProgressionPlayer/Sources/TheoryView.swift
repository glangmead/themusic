//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import AVFAudio
import SwiftUI
import Tonic

// the knobs i want visible here:
// - oscillator
// - vibrato
// - envelope
// - filter envelope
// - reverb
// -

struct TheoryView: View {
  let engine: SpatialAudioEngine
  var sampleRate: Double
  var voices: [SimpleVoice]
  let numVoices = 8
  let presets: [Preset]
  let voiceMixerNodes: [AVAudioNode]
  let envNode = AVAudioEnvironmentNode()
  
  let voicePool: NoteHandler
  let seq: Sequencer
  
  enum Instrument: CaseIterable, Equatable, Hashable {
    case Sawtooth
    case Sine
    case Square
    case Triangle
  }
  
  @State private var key = Key.C
  @State private var instrument: Instrument = .Sawtooth
  
  var keyChords: [Chord] {
    get {
      key.chords.filter { chord in
        [.major, .minor, .dim, .dom7, .maj7, .min7].contains(chord.type)
      }
      .sorted {
        $0.pitches(octave: 4)[0] < $1.pitches(octave: 4)[0]
      }
    }
  }

  init() {
    let engine = SpatialAudioEngine()
    sampleRate = engine.sampleRate

    voices = []
    for _ in 0..<numVoices {
      voices.append(SimpleVoice(
        oscillator:
            ModulatedPreMult(
              factor: 440.0,
              arrow: Sawtooth,
              modulation:
                PostMult(
                  factor: 0.2,
                  arrow:
                    PreMult(
                      factor: 5.0,
                      arrow: Sine)
                ).asControl()
              ),
        filter:
          ADSR(
            envelope:
              EnvelopeData(
                attackTime: 0.2,
                decayTime: 0.0,
                sustainLevel: 1.0,
                releaseTime: 0.2
              )
          )
      ))
    }

    // here we wrap the triple of voices into a PoolVoice, and we wrap each voice in a preset
    // so the preset attachment is breaking through the PoolVoice attachment
    // the PV is just combining the noteOn/noteOff inputs, whereas the Preset is pulling the voice into the Apple world
    voicePool = PoolVoice(voices: voices)
    
    presets = voices.map { Preset(sound: $0) }
    
    // animate the voices with various Roses
    var roseAmount = 0.0
    for preset in presets {
      preset.positionLFO = Rose(leafFactor: roseAmount,  frequency: 1, startingPhase: roseAmount * 2 * .pi / Double(presets.count))
      roseAmount += 1.0
    }
  
    voiceMixerNodes = presets.map {  $0.buildChainAndGiveOutputNode(forEngine: engine) }
    engine.connectToEnvNode(voiceMixerNodes)
    
    do {
      try engine.start()
    } catch {
      print("engine failed")
    }
    self.engine = engine

    // the sequencer will pluck on the arrows
    self.seq = Sequencer(engine: engine.audioEngine, numTracks: 1,  sourceNode: voicePool)
  }
  
  var body: some View {
    NavigationStack {
      Picker("Key", selection: $key) {
        Text("C").tag(Key.C)
        Text("G").tag(Key.G)
        Text("D").tag(Key.D)
        Text("A").tag(Key.A)
        Text("E").tag(Key.E)
      }.pickerStyle(.segmented)
      
      Picker("Instrument", selection: $instrument) {
        ForEach(Instrument.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)
      .onChange(of: instrument, initial: true) {
        for voice in voices {
          let rawOsc = switch instrument {
          case .Sawtooth:
            Sawtooth
          case .Sine:
            Sine
          case .Square:
            Square
          case .Triangle:
            Triangle
          }
          voice.oscillator.arrow = rawOsc
        }
      }
      ScrollView {
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 100, maximum: .infinity))
          ],
          content: {
            ForEach(keyChords, id: \.self) { chord in
              Button(chord.description) {
                seq.sendTonicChord(chord: chord)
              }
              .frame(maxWidth: .infinity)
              //.font(.largeTitle)
              .buttonStyle(.borderedProminent)
            }
          }
        )
      }
      .navigationTitle("Scape")
      Button("Stop") {
        seq.stop()
      }
    }
  }
}

#Preview {
  TheoryView()
}
