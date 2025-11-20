//
//  ContentView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/9/25.
//

import AVFoundation
import SwiftUI

// https://developer.apple.com/forums/thread/772475
class EngineerPlayer {
  let audioEngine = AVAudioEngine()
  let playerNode = AVAudioPlayerNode()
  let environmentNode = AVAudioEnvironmentNode()
  let effectNode = AVAudioUnitReverb()
  let mixerNode = AVAudioMixerNode()
  
  init(_ url: URL) throws {
    let audioFile = try AVAudioFile(forReading: url)
    let mono = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 1)
    let stereo = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 2)
    
    effectNode.loadFactoryPreset(.largeHall)
    effectNode.wetDryMix = 50
    audioEngine.attach(playerNode)
    audioEngine.attach(environmentNode)
    audioEngine.attach(effectNode)
    audioEngine.attach(mixerNode)
    audioEngine.connect(playerNode, to: effectNode, format: mono)
    audioEngine.connect(effectNode, to: mixerNode, format: stereo)
    audioEngine.connect(mixerNode, to: environmentNode, format: mono)
    audioEngine.connect(environmentNode, to: audioEngine.mainMixerNode, format: stereo)
    audioEngine.prepare()
    try audioEngine.start()
    
    environmentNode.renderingAlgorithm = .HRTFHQ
    
    playerNode.pointSourceInHeadMode = .mono
    playerNode.position = AVAudio3DPoint(x: 0, y: 2, z: 10)
    playerNode.scheduleFile(audioFile, at: nil, completionHandler: nil)
  }
  
  func updatePosition(_ angleInDegrees: Float) {
    environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: angleInDegrees, pitch: 0, roll: 0)
  }
}

struct SpatialView: View {
  var player: EngineerPlayer
  
  init() {
    do {
      try player = EngineerPlayer(Bundle.main.url(forResource: "beat", withExtension: "aiff")!)
    } catch {
      fatalError("error with aiff")
    }
  }
  
  var body: some View {
    Button("Start") {
      player.playerNode.play()
    }
    Button("Move it") {
      player.playerNode.position.y -= 0.5
    }
    Button("Move it back") {
      player.playerNode.position.y = 2.0
    }
  }
}

#Preview {
  SpatialView()
}
