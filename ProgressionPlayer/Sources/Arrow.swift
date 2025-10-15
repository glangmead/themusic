//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import AVFAudio
import Overture
import SwiftUI

// a source is () -> Float
//   - underlying it is a Float -> Float with a state for the input
//   - frequency is a parameter (or wavelength, the size of the fundamental domain)
// the source can be composed with
//   - multiplication (amplitude)
//   - sum (multiple voices)
// ADSR is a source as well, but with more state: it is a piecewise function
//   - some pieces are transitioned automatically, some need outside input

// we have functions x -> y and a stream of domain points [x]
// () -> time: add 1 / sampleRate to the previous value

// (time) -> time could also maybe subtract, so as to let functions eat their previous values??

// FAUST implements linear functions by adding to itself, but it could just be f(x) as well, instead of knowing about f(x-delta) and the slope.

// Now we can curry anything like (time) -> z to () -> z

// an AVAudioSourceNode has to populate a frame of stuff by calling a source N times
//

typealias MidiValue = UInt8

protocol WaveForm {
  func value(_ phase: Double) -> Double
}

struct SineWaveForm: WaveForm {
  func value(_ x: Double) -> Double {
    sin(x)
  }
}

struct TriangleWaveForm: WaveForm {
  let triangle = PiecewiseFunc<Double>(ifuncs: [
    IntervalFunc<Double>(
      interval: Interval<Double>(start: 0.0, end: .pi/2),
      f: { x in x * (2.0 / .pi) }
    ),
    IntervalFunc<Double>(
      interval: Interval<Double>(start: .pi/2, end: 3 * .pi/2),
      f: { x in (2.0 / .pi) * (.pi - x) }
    ),
    IntervalFunc<Double>(
      interval: Interval<Double>(start: 3 * .pi/2, end: 2 * .pi),
      f: { x in (2.0 / .pi) * (x - 2 * .pi) }
    ),
  ])
  func value(_ x: Double) -> Double {
    //triangle.val(fmod(x, 2.0 * .pi))
    abs((fmod(x, 2 * .pi) / .pi) - 1.0)
  }
}

struct SawtoothWaveForm: WaveForm {
  func value(_ x: Double) -> Double {
    (fmod(x, 2 * .pi) / .pi) - 1.0
  }
}

struct MidiNote {
  let note: MidiValue
  let velocity: MidiValue
}

protocol SampleSource {
  func sample(at time: Double) -> Double
}

protocol SampleProcessor {
  func process(_ sample: Double, time: Double) -> Double
}

protocol NoteHandler {
  func noteOn(_ note: MidiNote)
  func noteOff(_ note: MidiNote)
}

protocol Voice: SampleSource, NoteHandler {
}

class WaveOscillator: SampleSource {
  private let waveForm: WaveForm
  private var frequency: Double = 1.0
  
  init(waveForm: WaveForm) {
    self.waveForm = waveForm
  }
  
  func setFrequency(_ frequency: Double) {
    self.frequency = frequency
  }
  
  func sample(at time: Double) -> Double {
    return waveForm.value(frequency * time * 2 * .pi)
  }
}

class SimpleVoice: Voice {
  private let oscillator: WaveOscillator
  private let filter: NoteHandler & SampleProcessor
  private var amplitude: Double = 0.0 // Controls the current loudness of the voice
  
  init(oscillator: WaveOscillator, filter: NoteHandler & SampleProcessor) {
    self.oscillator = oscillator
    self.filter = filter
  }
  
  func noteOn(_ note: MidiNote) {
    // Map the MIDI velocity (0-127) to an amplitude (0.0-1.0)
    self.amplitude = Double(note.velocity) / 127.0
    
    // Calculate the frequency for the given MIDI note number
    let freq = 440.0 * pow(2.0, (Double(note.note) - 69.0) / 12.0)
    
    // Set the oscillator's frequency to produce the correct pitch
    oscillator.setFrequency(freq)
    filter.noteOn(note)
  }
  
  func noteOff(_ note: MidiNote) {
    // For this simple voice, turning the note off means setting amplitude to zero,
    // effectively silencing the sound instantly.
    filter.noteOff(note)
  }
  
  func sample(at time: Double) -> Double {
    // If the amplitude is zero, the voice is effectively off, so we return silence.
    guard self.amplitude > 0.0 else {
      return 0.0
    }
    let rawOscillatorSample = oscillator.sample(at: time)
    let envelopedSample = filter.process(rawOscillatorSample, time: time)
    return self.amplitude * envelopedSample
  }

}

class MyAudioEngine {
  private let audioEngine = AVAudioEngine()
  
  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
  }
  
  func setup(_ source: SampleSource) {
    // Initialize WaveOscillator with the system's sample rate
    // and our SineWaveForm.
    let source = source
    
    let sourceNode: AVAudioSourceNode = AVAudioSourceNode.withSource(source: source, sampleRate: sampleRate)
    audioEngine.attach(sourceNode)
    audioEngine.connect(sourceNode, to: audioEngine.outputNode, format: nil)
  }
  
  func start() throws {
    // Prepare the engine, getting all resources ready.
    audioEngine.prepare()
    
    // And then, start the engine! This is the moment the sound begins to play.
    try audioEngine.start()
  }
  
  func stop() {
    audioEngine.stop()
  }
}

struct ArrowView: View {
  let engine = MyAudioEngine()
  var sampleRate: Double
  let voice: Voice
  
  init() {
    self.sampleRate = engine.sampleRate
    voice = SimpleVoice(
      oscillator: WaveOscillator(waveForm: SawtoothWaveForm()),
      //filter: ADSRFilter(sampleRate: sampleRate, envelope: EnvelopeData())
      filter: ADSR(envelope: EnvelopeData())
    )
    engine.setup(voice)
  }
  
  var body: some View {
    Button("Stop") {
      voice.noteOff(MidiNote(note: 60, velocity: 100))
    }
    Button("Start") {
      do {
        try engine.start()
        voice.noteOn(MidiNote(note: 60, velocity: 100))
      } catch {
          print("engine failed")
      }
    }
    Button("Move it") {
    }
  }
}

#Preview {
  ArrowView()
}
