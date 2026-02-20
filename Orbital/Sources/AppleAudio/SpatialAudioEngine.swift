//
//  SpatialAudioEngine.swift
//  Orbital
//
//  Created by Greg Langmead on 11/8/25.
//

import AVFAudio
import Observation
import os

@Observable
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
  
  func detach(_ nodes: [AVAudioNode]) {
    for node in nodes where node.engine === audioEngine {
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
    audioEngine.connect(envNode, to: audioEngine.outputNode, format: stereo)
  }
  
  func start() throws {
    envNode.renderingAlgorithm = .HRTF
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

    // Install the audio tap once up-front so that opening the visualizer
    // later doesn't cause a glitch by reconfiguring the live audio graph.
    installTapOnce()
  }
  
  /// Client-provided callback; set before calling `start()` or at any time.
  /// Called on the audio-render thread with interleaved samples.
  /// The tap is installed once at engine start to avoid audio glitches.
  private let tapCallback = OSAllocatedUnfairLock<(([Float]) -> Void)?>(initialState: nil)
  private var tapInstalled = false

  func setTapCallback(_ block: (([Float]) -> Void)?) {
    tapCallback.withLock { $0 = block }
  }

  /// Install the tap on the envNode. Called once during `start()`.
  private func installTapOnce() {
    guard !tapInstalled else { return }
    tapInstalled = true

    let node = envNode
    let format = node.outputFormat(forBus: 0)

    node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
      guard let self else { return }
      guard let callback = self.tapCallback.withLock({ $0 }) else { return }
      guard let channelData = buffer.floatChannelData else { return }
      let frameLength = Int(buffer.frameLength)
      let channels = Int(format.channelCount)

      // Prepare interleaved buffer, to be re-interleaved by JavaScript
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

      callback(samples)
    }
  }
  
  /// Rapidly fade output to silence to avoid a click/pop when the engine stops.
  func fadeOutAndStop(duration: TimeInterval = 0.05) {
    guard audioEngine.isRunning else { return }
    
    let startVolume = envNode.outputVolume
    let steps = 10
    let interval = duration / Double(steps)
    
    for i in 1...steps {
      let volume = startVolume * Float(1.0 - Double(i) / Double(steps))
      DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
        self?.envNode.outputVolume = volume
      }
    }
    
    // Stop the engine after the fade completes.
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) { [weak self] in
      self?.audioEngine.stop()
    }
  }
  
  func stop() {
    audioEngine.stop()
  }
  
  func pause() {
    audioEngine.pause()
  }
}
