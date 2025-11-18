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
  var reverbNode: AVAudioUnitReverb?
  var mixerNode = AVAudioMixerNode()
  var delayNode: AVAudioUnitDelay?
  var distortionNode: AVAudioUnitDistortion?
  var reverbPreset: AVAudioUnitReverbPreset {
    didSet {
      reverbNode?.loadFactoryPreset(reverbPreset)
    }
  }
  var distortionPreset: AVAudioUnitDistortionPreset
  
  func getReverbWetDryMix() -> Double {
    Double(reverbNode?.wetDryMix ?? 0)
  }
  func setReverbWetDryMix(_ val: Double) {
    reverbNode?.wetDryMix = Float(val)
  }

  func getSpatialPosition() -> (Double, Double, Double) {
    (
      Double(mixerNode.position.x),
      Double(mixerNode.position.y),
      Double(mixerNode.position.z)
    )
  }
  func setSpatialPosition(_ pos: (Double, Double, Double)) {
    mixerNode.position.x = Float(pos.0)
    mixerNode.position.y = Float(pos.1)
    mixerNode.position.z = Float(pos.2)
  }
  
  func getDelayTime() -> Double {
    Double(delayNode?.delayTime ?? 0)
  }
  func setDelayTime(_ val: Double) {
    delayNode?.delayTime = val
  }
  func getDelayFeedback() -> Double {
    Double(delayNode?.feedback ?? 0)
  }
  func setDelayFeedback(_ val : Double) {
    delayNode?.feedback = Float(val)
  }
  func getDelayLowPassCutoff() -> Double {
    Double(delayNode?.lowPassCutoff ?? 0)
  }
  func setDelayLowPassCutoff(_ val: Double) {
    delayNode?.lowPassCutoff = Float(val)
  }
  func getDelayWetDryMix() -> Double {
    Double(delayNode?.wetDryMix ?? 0)
  }
  func setDelayWetDryMix(_ val: Double) {
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
  func getDistortionPreGain() -> Double {
    Double(distortionNode?.preGain ?? 0)
  }
  func setDistortionPreGain(_ val: Double) {
    distortionNode?.preGain = Float(val)
  }
  func getDistortionWetDryMix() -> Double {
    Double(distortionNode?.wetDryMix ?? 0)
  }
  func setDistortionWetDryMix(_ val: Double) {
    distortionNode?.wetDryMix = Float(val)
  }
  
  private var lastTimeWeSetPosition = 0.0
  private let setPositionMinWaitTime = 441.0 / 44100.0 // setting position is expensive, so limit how often
  
  init(sound: Arrow11) {
    self.sound = sound
    self.reverbNode = AVAudioUnitReverb()
    self.delayNode = AVAudioUnitDelay()
    self.distortionNode = AVAudioUnitDistortion()
    self.distortionPreset = .defaultValue
    self.distortionNode?.wetDryMix = 0
    self.reverbPreset = .cathedral
    self.reverbNode?.wetDryMix = 0
    self.setDelayTime(0)
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
  
  func buildChainAndGiveOutputNode(forEngine engine: SpatialAudioEngine) -> AVAudioMixerNode {
    let sampleRate = engine.sampleRate
    //let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    let setPositionArrow = Arrow10(of: { x in self.setPosition(x) })
    sourceNode = AVAudioSourceNode.withSource(
      source: sound.withSidecar(setPositionArrow),
      sampleRate: sampleRate)
    
    let nodes = [sourceNode!, distortionNode, delayNode, reverbNode, mixerNode].compactMap { $0 }
    engine.attach(nodes)
    for i in 0..<nodes.count-1 {
      engine.connect(nodes[i], to: nodes[i+1], format: nil) // having mono when the "to:" is reverb failed on my iPhone
    }
    return mixerNode
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects


