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
  
  // members whose params we can expose
  var reverbNode = AVAudioUnitReverb()
  var mixerNode = AVAudioMixerNode()
  var delayNode = AVAudioUnitDelay()
  var distortionNode = AVAudioUnitDistortion()
  
  func set(reverbWetDryMix: Double) {
    reverbNode.wetDryMix = Float(reverbWetDryMix)
  }
  // .smallRoom, .mediumRoom, .largeRoom, .mediumHall, .largeHall, .plate, .mediumChamber, .largeChamber, .cathedral, .largeRoom2, .mediumHall2, .mediumHall3, .largeHall2
  func set(reverbPreset: AVAudioUnitReverbPreset) {
    reverbNode.loadFactoryPreset(reverbPreset)
  }
  func set(spatialPosition: (Double, Double, Double)) {
    mixerNode.position.x = Float(spatialPosition.0)
    mixerNode.position.y = Float(spatialPosition.1)
    mixerNode.position.z = Float(spatialPosition.2)
  }
  func set(delayTime: Double) {
    delayNode.delayTime = delayTime
  }
  func set(delayFeedback: Double) {
    delayNode.feedback = Float(delayFeedback)
  }
  func set(delayLowPassCutoff: Double) {
    delayNode.lowPassCutoff = Float(delayLowPassCutoff)
  }
  func set(delayWetDryMix: Double) {
    delayNode.wetDryMix = Float(delayWetDryMix)
  }
  // .drumsBitBrush, .drumsBufferBeats, .drumsLoFi, .multiBrokenSpeaker, .multiCellphoneConcert, .multiDecimated1, .multiDecimated2, .multiDecimated3, .multiDecimated4, .multiDistortedFunk, .multiDistortedCubed, .multiDistortedSquared, .multiEcho1, .multiEcho2, .multiEchoTight1, .multiEchoTight2, .multiEverythingIsBroken, .speechAlienChatter, .speechCosmicInterference, .speechGoldenPi, .speechRadioTower, .speechWaves
  func set(distortionPreset: AVAudioUnitDistortionPreset) {
    distortionNode.loadFactoryPreset(distortionPreset)
  }
  func set(distortionPreGain: Double) {
    distortionNode.preGain = Float(distortionPreGain)
  }
  func set(distortionWetDryMix: Double) {
    distortionNode.wetDryMix = Float(distortionWetDryMix)
  }


  
  private var lastTimeWeSetPosition = 0.0
  private let setPositionMinWaitTime = 441.0 / 44100.0 // setting position is expensive, so limit how often
  
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
  
  func buildChainAndGiveOutputNode(forEngine engine: SpatialAudioEngine) -> AVAudioNode {
    let sampleRate = engine.sampleRate
    //let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    let setPositionArrow = Arrow10(of: { x in self.setPosition(x) })
    sourceNode = AVAudioSourceNode.withSource(
      source: sound.withSidecar(setPositionArrow),
      sampleRate: sampleRate)
    reverbNode.loadFactoryPreset(.largeChamber)
    reverbNode.wetDryMix = 50
    
    let nodes = [sourceNode!, distortionNode, delayNode, reverbNode, mixerNode]
    engine.attach(nodes)
    for i in 0..<nodes.count-1 {
      engine.connect(nodes[i], to: nodes[i+1], format: nil) // having mono when the "to:" is reverb failed on my iPhone
    }
    return mixerNode
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects


