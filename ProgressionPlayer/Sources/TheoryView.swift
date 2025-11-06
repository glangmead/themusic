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
  let engine: MyAudioEngine
  var sampleRate: Double
  var voices: [SimpleVoice]
  let numVoices = 4
  let presets: [Preset]
  let voiceMixerNodes: [AVAudioNode]
  let polyVoice: PolyVoice
  let seq: Sequencer
  let envNode = AVAudioEnvironmentNode()
  
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
        chord.type == .major || chord.type == .minor || chord.type == .dim || chord.type == .dom7
      }
      .sorted {
        $0.pitches(octave: 4)[0] < $1.pitches(octave: 4)[0]
      }
    }
  }

  init() {
    let engine = MyAudioEngine() // local var so as not to reference self
    sampleRate = engine.sampleRate

    voices = []
    for _ in 0..<numVoices {
      voices.append(SimpleVoice(
        oscillator: ModulatedPreMult(factor: 440.0, arrow: Sawtooth, modulation: ControlArrow(of: PostMult(factor: 0.0, arrow: PreMult(factor: 5.0, arrow: Sine)))) ,
        filter: ADSR(envelope: EnvelopeData(attackTime: 0.2, decayTime: 0.0, sustainLevel: 1.0, releaseTime: 0.2))
      ))
    }

    // here we wrap the triple of voices into a PolyVoice, and we wrap each voice in a preset
    // so the preset attachment is breaking through the PolyVoice attachment
    // the PV is just combining the noteOn/noteOff inputs, whereas the Preset is pulling the voice into the Apple world
    polyVoice = PolyVoice(voices: voices)
    
    presets = voices.map { Preset(sound: $0) }
    
    // animate the voices with various Roses
    var roseAmount = 0.0
    for preset in presets {
      preset.positionLFO = Rose(leafFactor: roseAmount, frequency: 6, startingPhase: roseAmount * 2 * .pi / Double(presets.count))
      roseAmount += 1.0
    }
    
    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    //let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)

    voiceMixerNodes = presets.map {  $0.buildChainAndGiveOutputNode(forEngine: engine.audioEngine) }
    engine.audioEngine.attach(envNode)
    for voiceMixerNode in voiceMixerNodes {
      engine.audioEngine.connect(voiceMixerNode, to: envNode, format: mono)
      //voiceMixerNode.pointSourceInHeadMode = .mono
    }
    engine.audioEngine.connect(envNode, to: engine.audioEngine.mainMixerNode, format: nil)
    do {
      try engine.start()
    } catch {
      print("engine failed")
    }
    self.engine = engine

    envNode.renderingAlgorithm = .HRTFHQ
    envNode.outputType = .auto
    envNode.isListenerHeadTrackingEnabled = false
    envNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    //envNode.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: 0.0, y: -1.0, z: 1.0), up: AVAudio3DVector(x: 0.0, y: 0.0, z: 1.0))

    // the sequencer will pluck on the arrows
    self.seq = Sequencer(engine: engine.audioEngine, numTracks: 1, sourceNode: polyVoice)
  }
  
  var body: some View {
    VStack {
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
      }.pickerStyle(.segmented)
        .onChange(of: instrument, initial: true) {
          for voice in voices {
            voice.oscillator.arrow = switch instrument {
            case .Sawtooth:
              Sawtooth
            case .Sine:
              Sine
            case .Square:
              Square
            case .Triangle:
              Triangle
            }
          }
        }
      ScrollView {
        ForEach(keyChords, id: \.self) { chord in
          Button(chord.description) {
            seq.sendTonicChord(chord: chord)
          }
          .frame(maxWidth: .infinity)
          .font(.largeTitle)
        }
      }
      .navigationTitle("Chordata")
    }
    Button("Stop") {
      seq.stop()
    }
  }
}

#Preview {
  TheoryView()
}
