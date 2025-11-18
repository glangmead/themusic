//
//  SpatialAudioEngine.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/8/25.
//

import AVFAudio

class SpatialAudioEngine {
  let audioEngine = AVAudioEngine()
  let envNode = AVAudioEnvironmentNode()
  let stereo: AVAudioFormat
  let mono: AVAudioFormat

  init() {
    audioEngine.attach(envNode)
    stereo = AVAudioFormat(standardFormatWithSampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 2)!
    mono = AVAudioFormat(standardFormatWithSampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 1)!
  }
  
  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
  }
  
  func attach(_ nodes: [AVAudioNode]) {
    for node in nodes {
      audioEngine.attach(node)
    }
  }
  
  func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {
    audioEngine.connect(node1, to: node2, format: format)
  }
  
  func connectToEnvNode(_ nodes: [AVAudioMixerNode]) {
    for node in nodes {
      node.pointSourceInHeadMode = .mono
      node.sourceMode = .spatializeIfMono
      audioEngine.connect(node, to: envNode, format: mono)
    }
    audioEngine.connect(envNode, to: audioEngine.outputNode, format: stereo)
  }
  
  func start() throws {
    envNode.renderingAlgorithm = .HRTFHQ
    envNode.outputType = .auto
    envNode.isListenerHeadTrackingEnabled = true
    envNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    envNode.distanceAttenuationParameters.referenceDistance = 2.0
    envNode.distanceAttenuationParameters.maximumDistance = 500.0
    //envNode.distanceAttenuationParameters.rolloffFactor = 2.0
    envNode.reverbParameters.enable = true
    envNode.reverbParameters.loadFactoryReverbPreset(.largeHall)
    envNode.reverbBlend = 0.2
    
    //envNode.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: 0.0, y: -1.0, z: 1.0), up: AVAudio3DVector(x: 0.0, y: 0.0, z: 1.0))
    
    // Prepare the engine, getting all resources ready.
    audioEngine.prepare()
    
    // And then, start the engine! This is the moment the sound begins to play.
    try audioEngine.start()
  }
  
  func stop() {
    audioEngine.stop()
  }
}
