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

struct RoseSyntax: Codable {
  let amp: CoreFloat
  let leafFactor: CoreFloat
  let freq: CoreFloat
  let phase: CoreFloat
}

struct EffectsSyntax: Codable {
  let reverbPreset: CoreFloat
  let reverbWetDryMix: CoreFloat
  let delayTime: TimeInterval
  let delayFeedback: CoreFloat
  let delayLowPassCutoff: CoreFloat
  let delayWetDryMix: CoreFloat
}

struct PresetSyntax: Codable {
  let name: String
  let arrow: ArrowSyntax
  let rose: RoseSyntax
  let effects: EffectsSyntax
  
  func compile() -> Preset {
    let sound = arrow.compile()
    let preset = Preset(sound: sound)
    preset.reverbPreset = AVAudioUnitReverbPreset(rawValue: Int(effects.reverbPreset)) ?? .mediumRoom
    preset.setReverbWetDryMix(effects.reverbWetDryMix)
    preset.setDelayTime(effects.delayTime)
    preset.setDelayFeedback(effects.delayFeedback)
    preset.setDelayLowPassCutoff(effects.delayLowPassCutoff)
    preset.setDelayWetDryMix(effects.delayWetDryMix)
    preset.positionLFO = Rose(
      amp: ArrowConst(value: rose.amp),
      leafFactor: ArrowConst(value: rose.leafFactor),
      freq: ArrowConst(value: rose.freq),
      phase: rose.phase
    )
    return preset
  }
}

@Observable
class InstrumentWithAVAudioUnitEffects {
  var sound: ArrowWithHandles
  var positionLFO: Rose? = nil
  var timeOrigin: Double = 0
  
  private var positionTask: Task<(), Error>?
  
  private var sourceNode: AVAudioSourceNode? = nil
  private var playerNode: AVAudioPlayerNode? = nil//AVAudioPlayerNode()
  
  // members whose params we can expose
  private var reverbNode: AVAudioUnitReverb?
  private var mixerNode = AVAudioMixerNode()
  private var delayNode: AVAudioUnitDelay? = AVAudioUnitDelay()
  private var distortionNode: AVAudioUnitDistortion? = nil
  
  var distortionAvailable: Bool {
    distortionNode != nil
  }
  
  var delayAvailable: Bool {
    delayNode != nil
  }
  
  // the parameters of the effects and the position arrow
  
  // effect enums
  var reverbPreset: AVAudioUnitReverbPreset {
    didSet {
      reverbNode?.loadFactoryPreset(reverbPreset)
    }
  }
  var distortionPreset: AVAudioUnitDistortionPreset
  // .drumsBitBrush, .drumsBufferBeats, .drumsLoFi, .multiBrokenSpeaker, .multiCellphoneConcert, .multiDecimated1, .multiDecimated2, .multiDecimated3, .multiDecimated4, .multiDistortedFunk, .multiDistortedCubed, .multiDistortedSquared, .multiEcho1, .multiEcho2, .multiEchoTight1, .multiEchoTight2, .multiEverythingIsBroken, .speechAlienChatter, .speechCosmicInterference, .speechGoldenPi, .speechRadioTower, .speechWaves
  func getDistortionPreset() -> AVAudioUnitDistortionPreset {
    distortionPreset
  }
  func setDistortionPreset(_ val: AVAudioUnitDistortionPreset) {
    distortionNode?.loadFactoryPreset(val)
    self.distortionPreset = val
  }

  // effect float values
  func getReverbWetDryMix() -> CoreFloat {
    CoreFloat(reverbNode?.wetDryMix ?? 0)
  }
  func setReverbWetDryMix(_ val: CoreFloat) {
    reverbNode?.wetDryMix = Float(val)
  }
  func getDelayTime() -> CoreFloat {
    CoreFloat(delayNode?.delayTime ?? 0)
  }
  func setDelayTime(_ val: TimeInterval) {
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
  
  private var lastTimeWeSetPosition: CoreFloat = 0.0
  
  // setting position is expensive, so limit how often
  // at 0.1 this makes my phone hot
  private let setPositionMinWaitTimeSecs: CoreFloat = 0.01
  
  init(sound: ArrowWithHandles) {
    self.sound = sound
    self.reverbNode = AVAudioUnitReverb()
    //self.delayNode = AVAudioUnitDelay()
    //self.distortionNode = AVAudioUnitDistortion()
    //self.distortionNode?.wetDryMix = 0
    self.distortionPreset = .defaultValue
    self.reverbPreset = .cathedral
    self.delayNode?.delayTime = 0
    self.reverbNode?.wetDryMix = 0
    self.timeOrigin = Date.now.timeIntervalSince1970
    self.positionTask = Task.detached(priority: .medium) {
      repeat {
        do {
          try await Task.sleep(for: .seconds(0.01))
          self.setPosition(CoreFloat(Date.now.timeIntervalSince1970 - self.timeOrigin))
        } catch {
          break
        }
      } while !Task.isCancelled
    }
  }
  
  func setPosition(_ t: CoreFloat) {
    if t > 1 { // fixes some race on startup
      if positionLFO != nil {
        if (t - lastTimeWeSetPosition) > setPositionMinWaitTimeSecs {
          lastTimeWeSetPosition = t
          let (x, y, z) = positionLFO!.of(t - 1)
          mixerNode.position.x = Float(x)
          mixerNode.position.y = Float(y)
          mixerNode.position.z = Float(z)
        }
      }
    }
  }
  
  func wrapInAppleNodes(forEngine engine: SpatialAudioEngine) -> AVAudioMixerNode {
    let sampleRate = engine.sampleRate
    sourceNode = AVAudioSourceNode.withSource(
      source: sound,
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
  
  func detachAppleNodes(from engine: SpatialAudioEngine) {
    positionTask?.cancel()
    let nodes = [sourceNode, playerNode, distortionNode, delayNode, reverbNode, mixerNode].compactMap { $0 }
    engine.detach(nodes)
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects


