//
//  ContentView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/9/25.
//

import AudioKit
import AudioKitEX
import AudioKitUI
import AVFoundation
import ComposableArchitecture
import Overture
import SoundpipeAudioKit
import SwiftUI
import Tonic

// AVAudioSession
// spatialCapabilitiesChangedNotification
// AVAudioSessionSpatialAudioEnabledKey
// AVAudioSessionPortDescription.isSpatialAudioEnabled
// AVAudioSession.setSupportsMultichannelContent(<#T##Bool#>)
// AVAudioSession.supportsMultichannelContent

// there are spatial audio APIs in AVPlayer, AVSampleBufferAudioRenderer, AudioQueue (tv/iOS only), AURemoteIO (tv/iOS only)

class Music: NSObject, ObservableObject {
  var mixer = Mixer3D(name: "ProgressionPlayer 3D Mixer")
  var environmentalNode = MyEnvNode()
  var player = AudioPlayer()
  var engine = AudioEngine()
  var testBuffer: AVAudioPCMBuffer
  static var sourceBuffer: AVAudioPCMBuffer {
    let fileURL = Bundle.main.url(forResource: "beat", withExtension: "aiff")
    let file = try! AVAudioFile(forReading: fileURL!)
    return try! AVAudioPCMBuffer(file: file)!
  }
  override init() {
    let avAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000.0, channelLayout: AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_AudioUnit_8)!)
    engine.outputAudioFormat = avAudioFormat
    testBuffer = Music.sourceBuffer
    player.buffer = testBuffer
    player.isLooping = true
//    mixer.addInput(player)
//    mixer.pointSourceInHeadMode = .bypass
//    mixer.position = AVAudio3DPoint(x: 0.0, y: 1.0, z: 1.0)

    environmentalNode.renderingAlgorithm = .HRTFHQ
    environmentalNode.reverbParameters.loadFactoryReverbPreset(.smallRoom)
    environmentalNode.reverbBlend = 0.75
    environmentalNode.avAudioEnvironmentNode.isListenerHeadTrackingEnabled = true
    environmentalNode.avAudioEnvironmentNode.sourceMode = .pointSource
    environmentalNode.avAudioEnvironmentNode.pointSourceInHeadMode = .mono
    environmentalNode.position = AVAudio3DPoint(x: 10.0, y: 1.0, z: 1.0)
    environmentalNode.listenerPosition = AVAudio3DPoint(x: 0.0, y: 0.0, z: 0.0)
    environmentalNode.listenerAngularOrientation = AVAudioMake3DAngularOrientation(0.0, 0.0, 0.0)
    environmentalNode.listenerVectorOrientation = AVAudio3DVectorOrientation(
      forward: AVAudio3DVector(x: 0.0, y: 1.0, z: 0.0),
      up: AVAudio3DVector(x: 0.0, y: 0.0, z: 1.0)
    )

    environmentalNode.connect(node: player)
    engine.output = environmentalNode
    try! engine.start()
    player.play()
    super.init()

  }
}

// https://developer.apple.com/forums/thread/772475
class EngineerPlayer {
  let audioEngine = AVAudioEngine()
  let player = AVAudioPlayerNode()
  let environmentalNode = AVAudioEnvironmentNode()
  
  init(_ inUrl: URL?) throws {
    if let url = inUrl {
      let audioFile = try AVAudioFile(forReading: url)
      let mono = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 1)
      let stereo = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 4)
      
      audioEngine.attach(player)
      audioEngine.attach(environmentalNode)
      audioEngine.connect(player, to: environmentalNode, format: mono)
      audioEngine.connect(environmentalNode, to: audioEngine.mainMixerNode, format: stereo)
      audioEngine.prepare()
      try audioEngine.start()
      
      environmentalNode.renderingAlgorithm = .HRTFHQ
      environmentalNode.isListenerHeadTrackingEnabled = true
      
      player.pointSourceInHeadMode = .mono
      player.position = AVAudio3DPoint(x: 0, y: 10, z: 10)
      environmentalNode.position = AVAudio3DPoint(x: 0, y: 10, z: 10)
      player.scheduleFile(audioFile, at: nil, completionHandler: nil)
      player.play()
    }
  }
  
  func updatePosition(_ angleInDegrees: Float) {
    environmentalNode.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: angleInDegrees, pitch: 0, roll: 0)
  }
}

struct ContentView: View {
  var music: EngineerPlayer
  
  init() {
    do {
      try music = EngineerPlayer(Bundle.main.url(forResource: "beat", withExtension: "aiff"))
    } catch {
      fatalError("error with aiff")
    }
  }
  
  
  var body: some View {
    Button("Stop") {
      music.player.stop()
    }
    Button("Start") {
      music.player.play()
    }
    Button("Move it") {
      music.player.position.x += 1
      music.player.position.y += 0.1
      music.player.position.z += 0.1
//      music.environmentalNode.listenerPosition.x -= 0.1
//      music.environmentalNode.listenerPosition.y -= 0.1
//      music.environmentalNode.listenerPosition.z -= 0.1
    }
  }
}

extension MyEnvNode {
  /// The listener’s position in the 3D environment.
  public var position: AVAudio3DPoint {
    get {
      avAudioEnvironmentNode.position
    }
    set {
      print("EnvironmentalNode position: \(newValue.x) \(newValue.y) \(newValue.z)")
      avAudioEnvironmentNode.position = newValue
    }
  }
}

#Preview {
  ContentView()
}
