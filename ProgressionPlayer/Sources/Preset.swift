//
//  Preset.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import AVFAudio
import Overture

/// A Preset is an Instrument plus effects chain.

// TODO: ModulatedReverbNode which has an AVAudioUnitReverb and an arrow for each exposed parameter of said node

class InstrumentWithAVAudioUnitEffects {
  var sound: Arrow11
  var positionLFO: Arrow13? = nil
  var sourceNode: AVAudioSourceNode? = nil
  var reverbNode = AVAudioUnitReverb()
  var mixerNode = AVAudioMixerNode()
  var delayNode = AVAudioUnitDelay()
  var distortionNode = AVAudioUnitDistortion()
  var eqNode = AVAudioUnitEQ()
  var lastTimeWeSetPosition = 0.0
  let setPositionMinWaitTime = 10.0 / 44100.0 // every 10 frames is often enough
  
  init(sound: Arrow11) {
    self.sound = sound
  }
  
  func setPosition(_ t: Double) {
    if t > 1 { // fixes some race on startup
      if positionLFO != nil && (mixerNode.engine?.isRunning != nil) && (mixerNode.engine!.isRunning) {
        if (t - lastTimeWeSetPosition) > setPositionMinWaitTime {
          lastTimeWeSetPosition = t
          let (x, y, z) = positionLFO!.of(t - 1)
          mixerNode.position.x = Float(x)
          mixerNode.position.y = Float(y)
          mixerNode.position.z = Float(z)
        }
      }
    }
  }
  
  func buildChainAndGiveOutputNode(forEngine engine: AVAudioEngine) -> AVAudioMixerNode {
    let sampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
    let setPositionArrow = Arrow10(id: "SetPosition", of: { x in self.setPosition(x) })
    sourceNode = AVAudioSourceNode.withSource(
      source: arrowWithSidecars(arr: sound, sidecars: [setPositionArrow]),
      sampleRate: sampleRate)
    reverbNode.loadFactoryPreset(.largeChamber)
    engine.attach(sourceNode!)
    engine.attach(reverbNode)
    engine.attach(mixerNode)
    // TODO: support more effects
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
  private let envNode = AVAudioEnvironmentNode() // deprecated
  private let mixerNode = AVAudioMixerNode() // deprecated
  private var reverbNode = AVAudioUnitReverb() // deprecated
  var sourceNode: AVAudioSourceNode? = nil // deprecated
  
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
    envNode.renderingAlgorithm = .HRTFHQ // deprecated
    envNode.isListenerHeadTrackingEnabled = true // deprecated
    envNode.position = AVAudio3DPoint(x: 0, y: 1, z: 1) // deprecated
  }
  
  func stop() {
    audioEngine.stop()
  }
  
  // deprecated
  func moveIt() {
    mixerNode.position.x += 0.1
    mixerNode.position.y -= 0.1
  }
}
