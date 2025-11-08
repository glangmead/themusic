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
  
  init() {
    audioEngine.attach(envNode)
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
  
  func connectToEnvNode(_ nodes: [AVAudioNode]) {
    let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
    for node in nodes {
      audioEngine.connect(node, to: envNode, format: stereo)
    }
    audioEngine.connect(envNode, to: audioEngine.mainMixerNode, format: stereo)
  }
  
  func start() throws {
    envNode.renderingAlgorithm = .HRTFHQ
    envNode.outputType = .auto
    envNode.isListenerHeadTrackingEnabled = false
    envNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
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
