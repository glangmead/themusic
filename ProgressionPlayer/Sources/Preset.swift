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
//  var delayNode = AVAudioUnitDelay()
//  var distortionNode = AVAudioUnitDistortion()
//  var eqNode = AVAudioUnitEQ()
  var lastTimeWeSetPosition = 0.0
  let setPositionMinWaitTime = 441.0 / 44100.0 // setting position is expensive, so limit how often
  
  init(sound: Arrow11) {
    self.sound = sound
  }
  
  func setPosition(_ t: Double) {
    if t > 1 { // fixes some race on startup
      if positionLFO != nil {
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
  
  func buildChainAndGiveOutputNode(forEngine engine: AVAudioEngine) -> AVAudioNode {
    let sampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    let setPositionArrow = Arrow10(of: { x in self.setPosition(x) })
    sourceNode = AVAudioSourceNode.withSource(
      source: arrowWithSidecars(arr: sound, sidecars: [setPositionArrow]),
      sampleRate: sampleRate)
    reverbNode.loadFactoryPreset(.largeChamber)
    reverbNode.wetDryMix = 50
    engine.attach(sourceNode!)
    engine.attach(reverbNode)
    engine.attach(mixerNode)
    // TODO: support more effects
    //engine.attach(delayNode)
    //engine.attach(distortionNode)
    //engine.attach(eqNode)
    engine.connect(sourceNode!, to: reverbNode, format: mono)
    engine.connect(reverbNode, to: mixerNode, format: nil)
    return mixerNode
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects

class MyAudioEngine {
  let audioEngine = AVAudioEngine()
  
  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
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
