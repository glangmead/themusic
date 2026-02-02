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
  //let limiter: AVAudioUnitEffect
  let stereo: AVAudioFormat
  let mono: AVAudioFormat

  init() {
    audioEngine.attach(envNode)
    stereo = AVAudioFormat(standardFormatWithSampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 2)!
    mono = AVAudioFormat(standardFormatWithSampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 1)!
    //limiter = AVAudioUnitEffect(
    //  audioComponentDescription: AudioComponentDescription(
    //    componentType: kAudioUnitType_Effect,
    //    componentSubType: kAudioUnitSubType_PeakLimiter,
    //    componentManufacturer: kAudioUnitManufacturer_Apple,
    //    componentFlags: 0,
    //    componentFlagsMask: 0
    //  )
    //)
    //audioEngine.attach(limiter)
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
  
  func detach(_ nodes: [AVAudioNode]) {
    for node in nodes {
      audioEngine.detach(node)
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
    //audioEngine.connect(envNode, to: limiter, format: stereo)
    //audioEngine.connect(limiter, to: audioEngine.outputNode, format: stereo)
    audioEngine.connect(envNode, to: audioEngine.outputNode, format: stereo)
  }
  
  func start() throws {
    envNode.renderingAlgorithm = .HRTFHQ
    envNode.outputType = .auto
    envNode.isListenerHeadTrackingEnabled = true
    envNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    envNode.distanceAttenuationParameters.referenceDistance = 5.0
    envNode.distanceAttenuationParameters.maximumDistance = 50.0
    //envNode.distanceAttenuationParameters.rolloffFactor = 2.0
    envNode.reverbParameters.enable = true
    envNode.reverbParameters.level = 60
    envNode.reverbParameters.loadFactoryReverbPreset(.largeHall)
    
    //envNode.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: 0.0, y: -1.0, z: 1.0), up: AVAudio3DVector(x: 0.0, y: 0.0, z: 1.0))
    
    // Prepare the engine, getting all resources ready.
    audioEngine.prepare()
    
    // And then, start the engine! This is the moment the sound begins to play.
    try audioEngine.start()
  }
  
  func installTap(tapBlock: @escaping ([Float]) -> Void) {
    let node = envNode
    let format = node.outputFormat(forBus: 0)
    node.removeTap(onBus: 0)
    
    // public typealias AVAudioNodeTapBlock = (AVAudioPCMBuffer, AVAudioTime) -> Void
    node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
      guard let channelData = buffer.floatChannelData else { return }
      let frameLength = Int(buffer.frameLength)
      let channels = Int(format.channelCount)
      
      // Prepare interleaved buffer, to be re-interleaved by JavaScript
      // If mono, size = frameLength. If stereo, size = frameLength * 2.
      let outputChannels = min(channels, 2)
      var samples = [Float](repeating: 0, count: frameLength * outputChannels)
      
      if outputChannels == 2 {
          let ptrL = channelData[0]
          let ptrR = channelData[1]
          for i in 0..<frameLength {
              samples[i*2] = ptrL[i]
              samples[i*2+1] = ptrR[i]
          }
      } else if outputChannels == 1 {
          let ptr = channelData[0]
          for i in 0..<frameLength {
              samples[i] = ptr[i]
          }
      }
      
      // call the provided closure
      tapBlock(samples)
    }
  }
  
  func removeTap() {
    envNode.removeTap(onBus: 0)
  }
  
  func stop() {
    audioEngine.stop()
  }
  
  func pause() {
    audioEngine.pause()
  }
}
