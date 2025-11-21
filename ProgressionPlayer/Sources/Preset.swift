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
  // members that would have their own external params
  var sound: Arrow11
  var positionLFO: Arrow13? = nil
  
  var sourceNode: AVAudioSourceNode? = nil
  var playerNode: AVAudioPlayerNode? = nil//AVAudioPlayerNode()
  
  // members whose params we can expose
  var reverbNode: AVAudioUnitReverb?
  var mixerNode = AVAudioMixerNode()
  var delayNode: AVAudioUnitDelay? = AVAudioUnitDelay()
  var distortionNode: AVAudioUnitDistortion? = nil
  var reverbPreset: AVAudioUnitReverbPreset {
    didSet {
      reverbNode?.loadFactoryPreset(reverbPreset)
    }
  }
  var distortionPreset: AVAudioUnitDistortionPreset
  
  func getReverbWetDryMix() -> CoreFloat {
    CoreFloat(reverbNode?.wetDryMix ?? 0)
  }
  func setReverbWetDryMix(_ val: CoreFloat) {
    reverbNode?.wetDryMix = Float(val)
  }

  func getSpatialPosition() -> (CoreFloat, CoreFloat, CoreFloat) {
    (
      CoreFloat(mixerNode.position.x),
      CoreFloat(mixerNode.position.y),
      CoreFloat(mixerNode.position.z)
    )
  }
  func setSpatialPosition(_ pos: (CoreFloat, CoreFloat, CoreFloat)) {
    mixerNode.position.x = Float(pos.0)
    mixerNode.position.y = Float(pos.1)
    mixerNode.position.z = Float(pos.2)
  }
  
  func getDelayTime() -> CoreFloat {
    CoreFloat(delayNode?.delayTime ?? 0)
  }
  func setDelayTime(_ val: CoreFloat) {
    delayNode?.delayTime = val
  }
  func getDelayFeedback() -> CoreFloat {
    CoreFloat(delayNode?.feedback ?? 0)
  }
  func setDelayFeedback(_ val : CoreFloat) {
    delayNode?.feedback = Float(val)
  }
  func getDelayLowPassCutoff() -> CoreFloat {
    CoreFloat(delayNode?.lowPassCutoff ?? 0)
  }
  func setDelayLowPassCutoff(_ val: CoreFloat) {
    delayNode?.lowPassCutoff = Float(val)
  }
  func getDelayWetDryMix() -> CoreFloat {
    CoreFloat(delayNode?.wetDryMix ?? 0)
  }
  func setDelayWetDryMix(_ val: CoreFloat) {
    delayNode?.wetDryMix = Float(val)
  }
  // .drumsBitBrush, .drumsBufferBeats, .drumsLoFi, .multiBrokenSpeaker, .multiCellphoneConcert, .multiDecimated1, .multiDecimated2, .multiDecimated3, .multiDecimated4, .multiDistortedFunk, .multiDistortedCubed, .multiDistortedSquared, .multiEcho1, .multiEcho2, .multiEchoTight1, .multiEchoTight2, .multiEverythingIsBroken, .speechAlienChatter, .speechCosmicInterference, .speechGoldenPi, .speechRadioTower, .speechWaves
  func getDistortionPreset() -> AVAudioUnitDistortionPreset {
    distortionPreset
  }
  func setDistortionPreset(_ val: AVAudioUnitDistortionPreset) {
    distortionNode?.loadFactoryPreset(val)
    self.distortionPreset = val
  }
  func getDistortionPreGain() -> CoreFloat {
    CoreFloat(distortionNode?.preGain ?? 0)
  }
  func setDistortionPreGain(_ val: CoreFloat) {
    distortionNode?.preGain = Float(val)
  }
  func getDistortionWetDryMix() -> CoreFloat {
    CoreFloat(distortionNode?.wetDryMix ?? 0)
  }
  func setDistortionWetDryMix(_ val: CoreFloat) {
    distortionNode?.wetDryMix = Float(val)
  }
  
  private var lastTimeWeSetPosition = 0.0
  private let setPositionMinWaitTime = 441.0 / 44100.0 // setting position is expensive, so limit how often
  
  init(sound: Arrow11) {
    self.sound = sound
    self.reverbNode = AVAudioUnitReverb()
    //self.delayNode = AVAudioUnitDelay()
    //self.distortionNode = AVAudioUnitDistortion()
    //self.distortionNode?.wetDryMix = 0
    self.delayNode?.delayTime = 0
    self.distortionPreset = .defaultValue
    self.reverbPreset = .cathedral
    self.reverbNode?.wetDryMix = 0
  }
  
  func setPosition(_ t: CoreFloat) {
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
  
  func buildChainAndGiveOutputNode(forEngine engine: SpatialAudioEngine) -> AVAudioMixerNode {
    let sampleRate = engine.sampleRate
    //let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    let setPositionArrow = Arrow10(of: { x in self.setPosition(x) })
    sourceNode = AVAudioSourceNode.withSource(
      source: sound.withSidecar(setPositionArrow),
      sampleRate: sampleRate
    )
    if playerNode != nil {
      do {
        let audioFile = try AVAudioFile(forReading: Bundle.main.url(forResource: "beat", withExtension: "aiff")!)
        engine.attach([playerNode!])
        playerNode!.scheduleFile(audioFile, at: nil, completionHandler: nil)
      } catch {
        print("\(error.localizedDescription)")
      }
    }
    
    let nodes = [sourceNode, playerNode, distortionNode, delayNode, reverbNode, mixerNode].compactMap { $0 }
    engine.attach(nodes)
    for i in 0..<nodes.count-1 {
      engine.connect(nodes[i], to: nodes[i+1], format: nil) // having mono when the "to:" is reverb failed on my iPhone
    }
    return mixerNode
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects


