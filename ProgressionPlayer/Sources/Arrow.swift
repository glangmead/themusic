//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import AVFAudio
import Overture
import SwiftUI

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

class Triangle: Arrow11 {
//  let triangle = PiecewiseFunc<Double>(ifuncs: [
//    IntervalFunc<Double>(
//      interval: Interval<Double>(start: 0.0, end: .pi/2),
//      f: { x in x * (2.0 / .pi) }
//    ),
//    IntervalFunc<Double>(
//      interval: Interval<Double>(start: .pi/2, end: 3 * .pi/2),
//      f: { x in (2.0 / .pi) * (.pi - x) }
//    ),
//    IntervalFunc<Double>(
//      interval: Interval<Double>(start: 3 * .pi/2, end: 2 * .pi),
//      f: { x in (2.0 / .pi) * (x - 2 * .pi) }
//    ),
//  ])
  init() {
    super.init(of: { x in
      //triangle.val(fmod(x, 2.0 * .pi))
      abs((fmod(x, 2 * .pi) / .pi) - 1.0)
    })
  }
}

let Sawtooth = Arrow11(of: { x in
  let ret = (fmod(x, 2 * .pi) / .pi) - 1.0
  return ret
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
    oscillator.factor = freq
    filter.noteOn(note)
  }
  
  func noteOff(_ note: MidiNote) {
    // For this simple voice, turning the note off means setting amplitude to zero,
    // effectively silencing the sound instantly.
    filter.noteOff(note)
  }
}

class MyAudioEngine {
  private let audioEngine = AVAudioEngine()
  private let envNode = AVAudioEnvironmentNode()
  private let mixerNode = AVAudioMixerNode()
  
  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
  }
  
  func setup(_ source: Arrow11) {
    // Initialize WaveOscillator with the system's sample rate
    // and our SineWaveForm.
    let source = source
    
    //print("\(sampleRate)")
    let sourceNode: AVAudioSourceNode = AVAudioSourceNode.withSource(source: source, sampleRate: sampleRate)

    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)

    audioEngine.attach(sourceNode)
    audioEngine.attach(envNode)
    audioEngine.attach(mixerNode)
    audioEngine.connect(sourceNode, to: mixerNode, format: nil)
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
    mixerNode.position.x += 0.1
    mixerNode.position.y -= 0.1
  }
}

struct ArrowView: View {
  let engine = MyAudioEngine()
  var sampleRate: Double
  let voices: [SimpleVoice]
  let sumSource: Arrow11
  let midiChord: [MidiValue] = [60, 64, 67, 48, 72]
  
  init() {
    self.sampleRate = engine.sampleRate
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
    
    engine.setup(sumSource)
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
    Button("Move it") {
      engine.moveIt()
    }
  }
}

#Preview {
  ArrowView()
}
