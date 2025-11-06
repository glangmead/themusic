//
//  ContentView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/9/25.
//

import AVFoundation
import Overture
import SwiftUI

// https://developer.apple.com/forums/thread/772475
class EngineerPlayer {
  let engine = AVAudioEngine()
  let player = AVAudioPlayerNode()
//  let mixer = AVAudioMixerNode()
  //let reverb = AVAudioUnitReverb()
  let environmentalNode = AVAudioEnvironmentNode()
  
  init(_ inUrl: URL?) throws {
    if let url = inUrl {
      let audioSession = AVAudioSession.sharedInstance()
      try! audioSession.setActive(true)
      let audioFile = try AVAudioFile(forReading: url)
      let mono = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 1)
      let stereo = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 2)
      //reverb.loadFactoryPreset(.largeHall2)
      engine.attach(player)
//      engine.attach(mixer)
      engine.attach(environmentalNode)
      //engine.attach(reverb)
      engine.connect(player, to: environmentalNode, format: mono)
//      engine.connect(player, to: reverb, format: mono)
//      engine.connect(reverb, to: mixer, format: mono)
//      engine.connect(mixer, to: environmentalNode, format: mono)
      engine.connect(environmentalNode, to: engine.mainMixerNode, format: nil)
      engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
      engine.prepare()
      try engine.start()
      
      environmentalNode.renderingAlgorithm = .soundField
      //environmentalNode.isListenerHeadTrackingEnabled = true
      
      player.pointSourceInHeadMode = .mono
      player.position = AVAudio3DPoint(x: 0, y: 10, z: 1)
      //environmentalNode.position = AVAudio3DPoint(x: 0, y: 1, z: 1)
      player.scheduleFile(audioFile, at: nil, completionHandler: nil)
    }
  }
  
  func updatePosition(_ angleInDegrees: Float) {
    environmentalNode.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: angleInDegrees, pitch: 0, roll: 0)
  }
}

struct SpatialView: View {
  var music2: EngineerPlayer
  
  init() {
    // init both methods
    do {
      try music2 = EngineerPlayer(Bundle.main.url(forResource: "beat", withExtension: "aiff"))

    } catch {
      fatalError("error with aiff")
    }
  }
    
  var body: some View {
    Button("Stop") {
      music2.player.pause()
    }
    Button("Start") {
      music2.player.play()
    }
    Button("Move it") {
      //music2.player.position.x += 0.1
      music2.player.position.y -= 0.5
    }
    Button("Move it back") {
      //music2.player.position.x += 0.1 
      music2.player.position.y = 2.0
    }
  }
}

#Preview {
  SpatialView()
}
