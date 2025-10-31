//
//  Preset.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import AVFAudio

/// A Preset is an Instrument plus effects chain.

// TODO: ModulatedReverbNode which has an AVAudioUnitReverb and an arrow for each exposed parameter of said node

class InstrumentWithAVAudioUnitEffects {
  var sound: Arrow11
  var sourceNode: AVAudioSourceNode? = nil
  var reverbNode = AVAudioUnitReverb()
  var mixerNode = AVAudioMixerNode()
  var delayNode = AVAudioUnitDelay()
  var distortionNode = AVAudioUnitDistortion()
  var eqNode = AVAudioUnitEQ()
  
  init(sound: Arrow11) {
    self.sound = sound
  }
  
  func buildChainAndGiveOutputNode(forEngine engine: AVAudioEngine) -> AVAudioMixerNode {
    let sampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
    sourceNode = AVAudioSourceNode.withSource(source: sound, sampleRate: sampleRate)
    engine.attach(sourceNode!)
    engine.attach(reverbNode)
    engine.attach(mixerNode)
    //engine.attach(delayNode)
    //engine.attach(distortionNode)
    //engine.attach(eqNode)
    engine.connect(sourceNode!, to: reverbNode, format: nil)
    engine.connect(reverbNode, to: mixerNode, format: nil)
    return mixerNode
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects

class MyAudioEngine {
  let audioEngine = AVAudioEngine()
  private let envNode = AVAudioEnvironmentNode()
  private let mixerNode = AVAudioMixerNode()
  private var reverbNode = AVAudioUnitReverb()
  var sourceNode: AVAudioSourceNode? = nil
  
  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
  }
  
  init() {} // version that doesn't wrap a fixed Arrow, which was an early testing paradigm
  
  // deprecated
  init(_ source: Arrow11) {
    // Initialize WaveOscillator with the system's sample rate
    // and our SineWaveForm.
    let source = source
    
    
    //print("\(sampleRate)")
    sourceNode = AVAudioSourceNode.withSource(source: source, sampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate)
    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    
    audioEngine.attach(sourceNode!)
    audioEngine.attach(envNode)
    audioEngine.attach(mixerNode)
    audioEngine.attach(reverbNode)
    audioEngine.connect(sourceNode!, to: reverbNode, format: nil)
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
    mixerNode.position.x += 0.1
    mixerNode.position.y -= 0.1
  }
}
