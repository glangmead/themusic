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
  let arrow: ArrowSyntax? // a sound synthesized in code, to be attached to an AVAudioSourceNode; mutually exclusive with a sample
  let samplerFilename: String? // a sound from an audio file in our bundle; mutually exclusive with an arrow
  let rose: RoseSyntax
  let effects: EffectsSyntax
  
  func compile() -> Preset {
    let preset: Preset
    if let arrowSyntax = arrow {
      let sound = arrowSyntax.compile()
      preset = Preset(sound: sound)
    } else if let samplerName = samplerFilename {
      preset = Preset(samplerFileName: samplerName)
    } else {
       preset = Preset(sound: ArrowWithHandles(ArrowConst(value: 0)))
       fatalError("PresetSyntax must have either arrow or sampler")
    }
    
    preset.name = name
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
  var name: String = "Noname"
  
  // sound synthesized in our code, and an audioGate to help control its perf
  var sound: ArrowWithHandles? = nil
  var audioGate: AudioGate? = nil
  private var sourceNode: AVAudioSourceNode? = nil

  // sound from an audio sample
  var samplerNode: AVAudioUnitSampler? = nil
  var samplerFileName: String? = nil
  
  // movement of the mixerNode in the environment node (see SpatialAudioEngine)
  var positionLFO: Rose? = nil
  var timeOrigin: Double = 0
  private var positionTask: Task<(), Error>?
  
  // FX nodes: members whose params we can expose
  private var reverbNode: AVAudioUnitReverb? = nil
  private var mixerNode = AVAudioMixerNode()
  private var delayNode: AVAudioUnitDelay? = AVAudioUnitDelay()
  private var distortionNode: AVAudioUnitDistortion? = nil
  
  var distortionAvailable: Bool {
    distortionNode != nil
  }
  
  var delayAvailable: Bool {
    delayNode != nil
  }
  
  func activate() {
    audioGate?.isOpen = true
  }

  func deactivate() {
    audioGate?.isOpen = false
  }

  private func setupLifecycleCallbacks() {
    if let sound = sound, let ampEnvs = sound.namedADSREnvelopes["ampEnv"] {
      for env in ampEnvs {
        env.startCallback = { [weak self] in
          self?.activate()
        }
        env.finishCallback = { [weak self] in
          if let self = self {
             let allClosed = ampEnvs.allSatisfy { $0.state == .closed }
             if allClosed {
               self.deactivate()
             }
          }
        }
      }
    }
  }

  // the parameters of the effects and the position arrow
  
  // effect enums
  var reverbPreset: AVAudioUnitReverbPreset = .smallRoom {
    didSet {
      reverbNode?.loadFactoryPreset(reverbPreset)
    }
  }
  var distortionPreset: AVAudioUnitDistortionPreset = .defaultValue
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
    self.audioGate = AudioGate(innerArr: sound)
    self.audioGate?.isOpen = false
    initEffects()
    setupLifecycleCallbacks()
  }
  
  init(samplerFileName: String) {
    self.samplerFileName = samplerFileName
    initEffects()
  }
  
  func initEffects() {
    self.reverbNode = AVAudioUnitReverb()
    self.distortionPreset = .defaultValue
    self.reverbPreset = .cathedral
    self.delayNode?.delayTime = 0
    self.reverbNode?.wetDryMix = 0
    self.timeOrigin = Date.now.timeIntervalSince1970
  }

  deinit {
    positionTask?.cancel()
  }
  
  func setPosition(_ t: CoreFloat) {
    if t > 1 { // fixes some race on startup
      if positionLFO != nil && (audioGate?.isOpen ?? true) { // Always open for sampler
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
    
    // connect our synthesis engine to an AVAudioSourceNode as the initial node in the chain,
    // else create an AVAudioUnitSampler to fill that role
    var initialNode: AVAudioNode?
    if let audioGate = audioGate {
      sourceNode = AVAudioSourceNode.withSource(
        source: audioGate,
        sampleRate: sampleRate
      )
      initialNode = sourceNode
    } else if let samplerFileName = samplerFileName {
      samplerNode = AVAudioUnitSampler()
      loadSamplerInstrument(samplerNode!, fileName: samplerFileName)
      initialNode = samplerNode
    }

    let nodes = [initialNode, distortionNode, delayNode, reverbNode, mixerNode].compactMap { $0 }
    engine.attach(nodes)
    
    for i in 0..<nodes.count-1 {
      engine.connect(nodes[i], to: nodes[i+1], format: nil) // having mono when the "to:" is reverb failed on my iPhone
    }

    positionTask?.cancel()
    positionTask = Task.detached(priority: .medium) { [weak self] in
      while let self = self, !Task.isCancelled {
        // If we are detached, kill the task
        guard let engine = self.mixerNode.engine else {
          break
        }

        if engine.isRunning {
          do {
            try await Task.sleep(for: .seconds(0.01))
            self.setPosition(CoreFloat(Date.now.timeIntervalSince1970 - self.timeOrigin))
          } catch {
            break
          }
        } else {
          // Engine attached but not running (starting up or paused).
          try? await Task.sleep(for: .seconds(0.2))
        }
      }
    }

    return mixerNode
  }
  
  func detachAppleNodes(from engine: SpatialAudioEngine) {
    positionTask?.cancel()
    let nodes = [sourceNode, samplerNode, distortionNode, delayNode, reverbNode, mixerNode].compactMap { $0 }
    engine.detach(nodes)
  }
  
  private func loadSamplerInstrument(_ node: AVAudioUnitSampler, fileName: String) {
    if let url = Bundle.main.url(forResource: fileName, withExtension: "wav") ??
                 Bundle.main.url(forResource: fileName, withExtension: "aiff") ??
        Bundle.main.url(forResource: fileName, withExtension: "aif") {
      do {
        try node.loadAudioFiles(at: [url])
      } catch {
        print("Error loading sampler instrument \(fileName): \(error.localizedDescription)")
      }
    } else if let url = Bundle.main.url(forResource: fileName, withExtension: "sf2") {
      do {
        try node.loadSoundBankInstrument(at: url, program: 4, bankMSB: 0x79, bankLSB: 0)
      } catch {
        print("Error loading sound bank instrument \(fileName): \(error.localizedDescription)")
      }
    } else {
      print("Could not find sampler file: \(fileName)")
    }
  }
}

typealias Preset = InstrumentWithAVAudioUnitEffects


