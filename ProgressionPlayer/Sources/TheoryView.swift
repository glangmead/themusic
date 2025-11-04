//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import AVFAudio
import SwiftUI
import Tonic

struct TheoryView: View {
  let engine: MyAudioEngine
  var sampleRate: Double
  let voices: [SimpleVoice]
  let presets: [Preset]
  let voiceMixerNodes: [AVAudioMixerNode]
  let polyVoice: PolyVoice
  let seq: Sequencer
  
  @State private var key = Key.C
  @State private var instrument = Sawtooth
  
  var keyChords: [Chord] {
    get {
      key.chords.filter { chord in
        chord.type == .major || chord.type == .minor || chord.type == .dim
      }
      .sorted {
        $0.pitches(octave: 4)[0] < $1.pitches(octave: 4)[0]
      }
    }
  }

  init() {
    voices = [
      SimpleVoice(
        oscillator: ModulatedPreMult(
          factor: 440.0,
          arrow: Sawtooth,
          modulation: arrowConst(1.0)
        ),
        filter: ADSR(envelope: EnvelopeData(
          attackTime: 0.2,
          decayTime: 0.0,
          sustainLevel: 1.0,
          releaseTime: 0.2))
      ),
      SimpleVoice(
        oscillator: ModulatedPreMult(
          factor: 440.0,
          arrow: Sawtooth,
          modulation: arrowConst(1.0)
        ),
        filter: ADSR(envelope: EnvelopeData(
          attackTime: 0.2,
          decayTime: 0.0,
          sustainLevel: 1.0,
          releaseTime: 0.2))
      ),
      SimpleVoice(
        oscillator: ModulatedPreMult(
          factor: 440.0,
          arrow: Sawtooth,
          modulation: arrowConst(1.0)
        ),
        filter: ADSR(envelope: EnvelopeData(
          attackTime: 0.2,
          decayTime: 0.0,
          sustainLevel: 1.0,
          releaseTime: 0.2))
      )
    ]
    // here we wrap the triple of voices into a PolyVoice, and we wrap each voice in a preset
    // so the preset attachment is breaking through the PolyVoice attachment
    // the PV is just combining the noteOn/noteOff inputs, whereas the Preset is pulling the voice into the Apple world
    polyVoice = PolyVoice(voices: voices)
    
    presets = voices.map { Preset(sound: $0) }
    var roseAmount = 1.0
    for preset in presets {
      preset.positionLFO = Rose(leafFactor: roseAmount + 1, frequency: 0.5, startingPhase: roseAmount * 2 * .pi / Double(presets.count))
      roseAmount += 1.0
    }
    
    let engine = MyAudioEngine() // local var so as not to reference self
    sampleRate = engine.sampleRate
    let envNode = AVAudioEnvironmentNode()
    engine.audioEngine.attach(envNode)
    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    //let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)

    voiceMixerNodes = presets.map { $0.buildChainAndGiveOutputNode(forEngine: engine.audioEngine) }
    for voiceMixerNode in voiceMixerNodes {
      engine.audioEngine.connect(voiceMixerNode, to: envNode, format: mono)
    }
    engine.audioEngine.connect(envNode, to: engine.audioEngine.outputNode, format: nil)
    do {
      engine.audioEngine.prepare()
      try engine.start()
    } catch {
      print("engine failed")
    }
    self.engine = engine

    envNode.renderingAlgorithm = .HRTFHQ
    envNode.isListenerHeadTrackingEnabled = true
    envNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    envNode.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
    envNode.reverbParameters.loadFactoryReverbPreset(.largeChamber)

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
        Text("Sine").tag(Sine)
        Text("Square").tag(Square)
        Text("Saw").tag(Sawtooth)
        Text("Triangle").tag(Triangle)
      }.pickerStyle(.segmented)
        .onChange(of: instrument, initial: true) {
          for voice in voices {
            voice.oscillator.arrow = instrument
          }
        }
      ScrollView {
        ForEach(keyChords, id: \.self) { chord in
          Button(chord.description) {
            seq.stop()
            seq.clear()
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
  
//  static func demoTrackFor(chord: Chord, inTrack: AVMusicTrack) {
//    inTrack.lengthInBeats = 4
//    chord.pitches(octave: 3).forEach { pitch in
//      inTrack.addEvent(AVMIDINoteEvent(channel: 0, key: UInt32(pitch.midiNoteNumber), velocity: 128, duration: 2), at: 0)
//    }
//  }
}

#Preview {
  TheoryView()
}
