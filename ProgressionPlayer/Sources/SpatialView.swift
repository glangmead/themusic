//
//  ContentView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/9/25.
//

import AudioKit
//import AudioKitEX
//import AudioKitUI
import AVFoundation
import ComposableArchitecture
import Overture
//import SoundpipeAudioKit
import SwiftUI
//import Tonic

// AVAudioSession
// spatialCapabilitiesChangedNotification
// AVAudioSessionSpatialAudioEnabledKey
// AVAudioSessionPortDescription.isSpatialAudioEnabled
// AVAudioSession.setSupportsMultichannelContent(<#T##Bool#>)
// AVAudioSession.supportsMultichannelContent

// there are spatial audio APIs in AVPlayer, AVSampleBufferAudioRenderer, AudioQueue (tv/iOS only), AURemoteIO (tv/iOS only)

class Music {
  var mixer = Mixer3D(name: "ProgressionPlayer 3D Mixer")
  var environmentalNode = EnvironmentalNode()
  var player: AudioPlayer
  var engine = AudioEngine()
//  var testBuffer: AVAudioPCMBuffer 
//  static var sourceBuffer: AVAudioPCMBuffer {
//    let fileURL = Bundle.main.url(forResource: "beat", withExtension: "aiff")
//    let file = try! AVAudioFile(forReading: fileURL!)
//    return try! AVAudioPCMBuffer(file: file)!
//  }

  init() {
    let fileURL = Bundle.main.url(forResource: "beat", withExtension: "aiff")
    let file = try! AVAudioFile(forReading: fileURL!)
    let mono = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)!
    let stereo = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)
    player = AudioPlayer(file: file)!


    mixer.addInput(player)
    environmentalNode.connect(mixer3D: mixer)

    engine.output = environmentalNode

    mixer.pointSourceInHeadMode = .mono
    mixer.position = AVAudio3DPoint(x: 0.0, y: 1.0, z: 1.0)
    environmentalNode.avAudioEnvironmentNode.position = AVAudio3DPoint(x: 0.0, y: 1.0, z: 1.0)

    engine.mainMixerNode?.pan = -1.0
    engine.outputAudioFormat = stereo
    try! engine.start()
    environmentalNode.renderingAlgorithm = .HRTFHQ
    environmentalNode.avAudioEnvironmentNode.isListenerHeadTrackingEnabled = true
    print(engine.avEngine)
  }
}

// https://developer.apple.com/forums/thread/772475
class EngineerPlayer {
  let engine = AVAudioEngine()
  let player = AVAudioPlayerNode()
  let mixer = AVAudioMixerNode()
  let environmentalNode = AVAudioEnvironmentNode()
  
  init(_ inUrl: URL?) throws {
    if let url = inUrl {
      let audioFile = try AVAudioFile(forReading: url)
      let mono = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 1)
      let stereo = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 2)
      
      engine.attach(player)
      engine.attach(mixer)
      engine.attach(environmentalNode)
      engine.connect(player, to: mixer, format: mono)
      engine.connect(mixer, to: environmentalNode, format: mono)
      engine.connect(environmentalNode, to: engine.mainMixerNode, format: stereo)
      engine.prepare()
      try engine.start()
      print(engine)
      
      environmentalNode.renderingAlgorithm = .HRTFHQ
      environmentalNode.isListenerHeadTrackingEnabled = true
      
      mixer.pointSourceInHeadMode = .mono
      mixer.position = AVAudio3DPoint(x: 0, y: 1, z: 1)
      //player.position = AVAudio3DPoint(x: 0, y: 1, z: 1)
      environmentalNode.position = AVAudio3DPoint(x: 0, y: 1, z: 1)
      player.scheduleFile(audioFile, at: nil, completionHandler: nil)
    }
  }
  
  func updatePosition(_ angleInDegrees: Float) {
    environmentalNode.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: angleInDegrees, pitch: 0, roll: 0)
  }
}

struct SpatialView: View {
  var music1: Music
  var music2: EngineerPlayer
  
  init() {
    // init both methods
    music1 = Music()
    do {
      try music2 = EngineerPlayer(Bundle.main.url(forResource: "beat", withExtension: "aiff"))

    } catch {
      fatalError("error with aiff")
    }
  }
    
  var body: some View {
    Button("Stop") {
      music1.player.stop()
    }
    Button("Start") {
      music1.player.play()
    }
    Button("Move it") {
      music1.mixer.position.x += 0.1
      music1.mixer.position.y -= 0.1
    }
  }
}

#Preview {
  SpatialView()
}
