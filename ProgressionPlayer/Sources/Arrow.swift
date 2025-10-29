//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import AVFAudio
import Overture
import SwiftUI

/// High-level architecture: [Instrument -> AVAudioUnitEffect_1 -> ... -> AVAudioUnitEffect_n -> AVAudioEnvironmentNode] => AVAudioEngine
///                               ^                 ^                             ^                         ^
///                             [LFO]             [LFO]                         [LFO]                     [LFO]
///
/// AVAudioSourceNode per _instrument_
///   - the render block callback for this obtains all the outputs of all oscillators of that instrument
///   - polyphony in this instrument
///   - envelopes
///   - tremolo
///   - filter envelopes
///   - chain of AVAudioUnitEffects
///   - AVAudioEnvironmentNode (the famous spatializer)
///   - The output node is the AVAudioEngine outputNode
///
/// The Instrument is an Arrow and is a static formula of
///   - the oscillator
///   - amplitude envelope
///   - frequency
///   - modulation of frequency
///
/// AVAudioUnitEffect nodes need some way to be modulated by an LFO, or so I am saying.
///   - AVAudioUnitDelay
///       * delayTime, feedback, lowPassCutoff, wetDryMix
///   - AVAudioUnitDistortion
///       * loadFactoryPreset, preGain, wetDryMix
///   - AVAudioUnitEQ
///       * AVAudioUnitEQFilterParameters, bands, globalGain
///   - AVAudioUnitReverb
///       * loadFactoryPreset, wetDryMix
///   - AU plugins!
///
/// AVAudioEnvironmentNode
///   - position, listenerPosition, listenerAngularOrientation, listenerVectorOrientation,
///     distanceAttenuationParameters, reverbParameters, outputVolume, outputType, applicableRenderingAlgorithms,
///     isListenerHeadTrackingEnabled, nextAvailableInputBus
///
/// An LFO is a coupling of two arrows.
///   - arrow1 is a target to be modulated, e.g. a sin wave whose frequency we shall modulate
///   - arrow2 is an LFO without knowledge of where it's being plugged in
///   - in real time we can do a few things
///       * couple and uncouple (a binary change -- maybe the wire is there statically and we just set the coupling constant to 0)
///       * change arrow1's variables
///       * change arrow2's variables
///
/// What is an arrow?
///   - A collection of sub-arrows composed together statically
///   - A single arrow has exposed parameters that can be changed in real time
///   - So in fullness, and arrow is a wiring diagram (the static part) with a few knobs attached (the real-time part)
///   - Compile-time wires and runtime wires?
///

typealias MidiValue = UInt8

class Arrow11 {
  var of: (Double) -> Double
  init(of: @escaping (Double) -> Double) {
    self.of = of
  }
}

//protocol SampleSource {
//  func sample(at time: Double) -> Double
//}

class Arrow21 {
  var of: (Double, Double) -> Double
  init(of: @escaping (Double, Double) -> Double) {
    self.of = of
  }
}

func arrowPlus(a: Arrow11, b: Arrow11) -> Arrow11 {
  return Arrow11(of: { a.of($0) + b.of($0) })
}

func arrowSum(_ arrows: [Arrow11]) -> Arrow11 {
  return Arrow11(of: { x in
    arrows.map({$0.of(x)}).reduce(0, +)
  } )
}

func arrowTimes(a: Arrow11, b: Arrow11) -> Arrow11 {
  return Arrow11(of: { a.of($0) * b.of($0) })
}

func arrowCompose(outer: Arrow11, inner: Arrow11) -> Arrow11 {
  return Arrow11(of: { outer.of(inner.of($0)) })
}

func arrowConst(_ val: Double) -> Arrow11 {
  return Arrow11(of: { _ in return val })
}

protocol NoteHandler {
  func noteOn(_ note: MidiNote)
  func noteOff(_ note: MidiNote)
}

let Sine = Arrow11(of: {
  sin(2 * .pi * $0)
})

let Triangle = Arrow11(of: { x in
  2 * (abs((2 * fmod(x, 1.0)) - 1.0) - 0.5)
})

let Sawtooth = Arrow11(of: { x in
  (2 * fmod(x, 1.0)) - 1.0
})

struct MidiNote {
  let note: MidiValue
  let velocity: MidiValue
}

class VariableMult: Arrow11 {
  var factor: Double
  let arrow: Arrow11
  init(factor: Double, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    weak var futureSelf: VariableMult? = nil
    super.init(of: { x in
      //print("\(futureSelf!.factor) \(x)")
      return futureSelf!.arrow.of(futureSelf!.factor * x)
    })
    futureSelf = self
  }
}

class SimpleVoice: Arrow11, NoteHandler {
  private let oscillator: VariableMult
  private let filter: NoteHandler & Arrow21
  private var amplitude: Double = 0.0 // Controls the current loudness of the voice
  
  init(oscillator: VariableMult, filter: NoteHandler & Arrow21) {
    self.oscillator = oscillator
    self.filter = filter
    weak var futureSelf: SimpleVoice? = nil
    super.init(of: { time in
      // If the amplitude is zero, the voice is effectively off, so we return silence.
      guard futureSelf!.amplitude > 0.0 else {
        return 0.0
      }
      let rawOscillatorSample = oscillator.of(time)
      let envelopedSample = filter.of(rawOscillatorSample, time)
      return futureSelf!.amplitude * envelopedSample
    })
    futureSelf = self

  }
  
  func noteOn(_ note: MidiNote) {
    // Map the MIDI velocity (0-127) to an amplitude (0.0-1.0)
    self.amplitude = Double(note.velocity) / 127.0
    
    // Calculate the frequency for the given MIDI note number
    let freq = 440.0 * pow(2.0, (Double(note.note) - 69.0) / 12.0)
    
    // Set the oscillator's frequency to produce the correct pitch
    //print("\(freq)")
    oscillator.factor = freq
    filter.noteOn(note)
  }
  
  func noteOff(_ note: MidiNote) {
    // For this simple voice, turning the note off means setting amplitude to zero,
    // effectively silencing the sound instantly.
    filter.noteOff(note)
  }
}

struct ArrowView: View {
  let engine: MyAudioEngine
  var sampleRate: Double
  let voices: [SimpleVoice]
  let sumSource: Arrow11
  let midiChord: [MidiValue] = [60, 64, 67]
  let seq: Sequencer
  
  init() {
    voices = midiChord.map { _ in
      SimpleVoice(
        oscillator: VariableMult(factor: 440.0, arrow: Sawtooth),
        filter: ADSR(envelope: EnvelopeData(
          attackTime: 0.2,
          decayTime: 0.0,
          sustainLevel: 1.0,
          releaseTime: 0.2))
      )
    }
    sumSource = arrowSum(voices)
//    let lfoSource = WaveOscillator(waveForm: SineWaveForm())
//    lfoSource.setFrequency(1.0)
//    let vibratoSource = ComposeSource(outer: sumSource, inner: lfoSource)
    
    engine = MyAudioEngine(sumSource)
    sampleRate = engine.sampleRate
    seq = Sequencer(engine: engine.audioEngine, numTracks: 1, sourceNode: voices[0])
  }
  
  var body: some View {
    Button("Stop") {
      for (voice, note) in zip(voices, midiChord) {
        voice.noteOff(MidiNote(note: note, velocity: 100))
      }
    }
    Button("Start") {
      do {
        try engine.start()
        for (voice, note) in zip(voices, midiChord) {
          voice.noteOn(MidiNote(note: note, velocity: 100))
        }
      } catch {
          print("engine failed")
      }
    }
    Button("Sequencer") {
      do {
        try engine.start()
        seq.testListener(chord: midiChord)
      } catch {
        print("engine failed")
      }
    }
    Button("Move it") {
      engine.moveIt()
    }
  }
}

class MyAudioEngine {
  let audioEngine = AVAudioEngine()
  private let envNode = AVAudioEnvironmentNode()
  private let mixerNode = AVAudioMixerNode()
  private var reverbNode = AVAudioUnitReverb()
  let sourceNode: AVAudioSourceNode
  
  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
  }
  
  init(_ source: Arrow11) {
    // Initialize WaveOscillator with the system's sample rate
    // and our SineWaveForm.
    let source = source
    
    
    //print("\(sampleRate)")
    sourceNode = AVAudioSourceNode.withSource(source: source, sampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate)
    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    
    audioEngine.attach(sourceNode)
    audioEngine.attach(envNode)
    audioEngine.attach(mixerNode)
    audioEngine.attach(reverbNode)
    audioEngine.connect(sourceNode, to: reverbNode, format: nil)
    audioEngine.connect(reverbNode, to: mixerNode, format: nil)
    audioEngine.connect(mixerNode, to: envNode, format: mono)
    audioEngine.connect(envNode, to: audioEngine.outputNode, format: nil)
  }
  
  func start() throws {
    // Prepare the engine, getting all resources ready.
    audioEngine.prepare()
    
    // And then, start the engine! This is the moment the sound begins to play.
    try audioEngine.start()
    envNode.renderingAlgorithm = .HRTFHQ
    envNode.isListenerHeadTrackingEnabled = true
    envNode.position = AVAudio3DPoint(x: 0, y: 1, z: 1)
  }
  
  func stop() {
    audioEngine.stop()
  }
  
  func moveIt() {
    if sourceNode is AVAudioUnit {
      print("alas my node doesn't turn out to helpfully just be an AVAudioUnit")
    }
    mixerNode.position.x += 0.1
    mixerNode.position.y -= 0.1
  }
}


#Preview {
  ArrowView()
}
