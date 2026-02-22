//
//  Preset.swift
//  Orbital
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
  let samplerFilenames: [String]? // a sound from an audio file(s) in our bundle; mutually exclusive with an arrow
  let samplerProgram: UInt8? // a soundfont idiom: the instrument/preset index
  let samplerBank: UInt8? // a soundfont idiom: the grouping of instruments, e.g. usually 121 for sounds and 120 for percussion
  let rose: RoseSyntax
  let effects: EffectsSyntax
  
  func compile(numVoices: Int = 12, initEffects: Bool = true) -> Preset {
    let preset: Preset
    if let arrowSyntax = arrow {
      preset = Preset(arrowSyntax: arrowSyntax, numVoices: numVoices, initEffects: initEffects)
    } else if let samplerFilenames = samplerFilenames, let samplerBank = samplerBank, let samplerProgram = samplerProgram {
      preset = Preset(sampler: Sampler(fileNames: samplerFilenames, bank: samplerBank, program: samplerProgram), initEffects: initEffects)
    } else {
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
class Preset: NoteHandler {
  var name: String = "Noname"
  let numVoices: Int
  
  // Arrow voices (polyphonic): each is an independently compiled ArrowWithHandles
  private(set) var voices: [ArrowWithHandles] = []
  private var voiceLedger: VoiceLedger?
  private(set) var mergedHandles: ArrowWithHandles? = nil
  
  // The ArrowSum of all voices, wrapped as ArrowWithHandles
  var sound: ArrowWithHandles? = nil
  var audioGate: AudioGate? = nil
  private var sourceNode: AVAudioSourceNode? = nil
  
  // sound from an audio sample
  var sampler: Sampler? = nil
  var samplerNode: AVAudioUnitSampler? { sampler?.node }
  
  // movement of the mixerNode in the environment node (see SpatialAudioEngine)
  var positionLFO: Rose? = nil
  var timeOrigin: Double = 0
  private var positionTask: Task<(), Error>?
  
  // FX nodes: members whose params we can expose
  private var reverbNode: AVAudioUnitReverb? = nil
  private var mixerNode: AVAudioMixerNode? = nil
  private var delayNode: AVAudioUnitDelay? = nil
  private var distortionNode: AVAudioUnitDistortion? = nil
  
  var distortionAvailable: Bool {
    distortionNode != nil
  }
  
  var delayAvailable: Bool {
    delayNode != nil
  }
  
  // NoteHandler conformance
  var globalOffset: Int = 0
  var activeNoteCount = 0
  var handles: ArrowWithHandles? { mergedHandles }
  
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
        env.finishCallbacks.append { [weak self] in
          if let self = self {
            let allClosed = ampEnvs.allSatisfy { $0.state == .closed }
            if allClosed {
              // Delay gate close to avoid race with incoming noteOn during fast trills.
              // If a new noteOn arrives within 50ms, envelopes won't be .closed anymore.
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                let stillAllClosed = ampEnvs.allSatisfy { $0.state == .closed }
                if stillAllClosed {
                  self.deactivate()
                }
              }
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
  
  /// Create a polyphonic Arrow-based Preset with N independent voice copies.
  init(arrowSyntax: ArrowSyntax, numVoices: Int = 12, initEffects: Bool = true) {
    self.numVoices = numVoices
    
    // Compile N independent voice arrow trees
    for _ in 0..<numVoices {
      voices.append(arrowSyntax.compile())
    }
    
    // Sum all voices into one signal
    let sum = ArrowSum(innerArrs: voices)
    let combined = ArrowWithHandles(sum)
    let _ = combined.withMergeDictsFromArrows(voices)
    self.sound = combined
    
    // Merged handles for external access (UI knobs, modulation)
    let handleHolder = ArrowWithHandles(ArrowIdentity())
    let _ = handleHolder.withMergeDictsFromArrows(voices)
    self.mergedHandles = handleHolder
    
    // Gate + voice ledger
    self.audioGate = AudioGate(innerArr: combined)
    self.audioGate?.isOpen = false
    self.voiceLedger = VoiceLedger(voiceCount: numVoices)
    
    // Register ampEnv envelopes per voice so the ledger can
    // auto-release voices when envelope release completes.
    for (voiceIdx, voice) in voices.enumerated() {
      if let ampEnvs = voice.namedADSREnvelopes["ampEnv"] {
        self.voiceLedger?.registerEnvelopes(forVoice: voiceIdx, envelopes: ampEnvs)
      }
    }
    
    if initEffects { self.initEffects() }
    setupLifecycleCallbacks()
  }
  
  init(sampler: Sampler, initEffects: Bool = true) {
    self.numVoices = 1
    self.sampler = sampler
    self.voiceLedger = VoiceLedger(voiceCount: 1)
    if initEffects { self.initEffects() }
  }
  
  // MARK: - NoteHandler
  
  func noteOn(_ noteVelIn: MidiNote) {
    let noteVel = MidiNote(note: applyOffset(note: noteVelIn.note), velocity: noteVelIn.velocity)
    
    if let sampler = sampler {
      guard let ledger = voiceLedger else { return }
      // Re-trigger: stop then start so the note restarts cleanly
      if ledger.voiceIndex(for: noteVelIn.note) != nil {
        sampler.node.stopNote(noteVel.note, onChannel: 0)
      } else {
        activeNoteCount += 1
        let _ = ledger.takeAvailableVoice(noteVelIn.note)
      }
      sampler.node.startNote(noteVel.note, withVelocity: noteVel.velocity, onChannel: 0)
      return
    }
    
    guard let ledger = voiceLedger else { return }
    
    // Re-trigger if this note is already playing on a voice
    if let voiceIdx = ledger.voiceIndex(for: noteVelIn.note) {
      triggerVoice(voiceIdx, note: noteVel, isRetrigger: true)
    }
    // Otherwise allocate a fresh voice
    else if let voiceIdx = ledger.takeAvailableVoice(noteVelIn.note) {
      triggerVoice(voiceIdx, note: noteVel, isRetrigger: false)
    } else {
    }
  }
  
  func noteOff(_ noteVelIn: MidiNote) {
    let noteVel = MidiNote(note: applyOffset(note: noteVelIn.note), velocity: noteVelIn.velocity)
    
    if let sampler = sampler {
      guard let ledger = voiceLedger else { return }
      if ledger.releaseVoice(noteVelIn.note) != nil {
        activeNoteCount -= 1
      }
      sampler.node.stopNote(noteVel.note, onChannel: 0)
      return
    }
    
    guard let ledger = voiceLedger else { return }
    if let voiceIdx = ledger.beginRelease(noteVelIn.note) {
      releaseVoice(voiceIdx, note: noteVel)
    }
  }
  
  private func triggerVoice(_ voiceIdx: Int, note: MidiNote, isRetrigger: Bool = false) {
    if !isRetrigger {
      activeNoteCount += 1
    }
    let voice = voices[voiceIdx]
    for key in voice.namedADSREnvelopes.keys {
      for env in voice.namedADSREnvelopes[key]! {
        env.noteOn(note)
      }
    }
    if let freqConsts = voice.namedConsts["freq"] {
      for const in freqConsts {
        const.val = note.freq
      }
    }
  }
  
  private func releaseVoice(_ voiceIdx: Int, note: MidiNote) {
    activeNoteCount -= 1
    let voice = voices[voiceIdx]
    for key in voice.namedADSREnvelopes.keys {
      for env in voice.namedADSREnvelopes[key]! {
        env.noteOff(note)
      }
    }
  }
  
  func initEffects() {
    self.reverbNode = AVAudioUnitReverb()
    self.delayNode = AVAudioUnitDelay()
    self.mixerNode = AVAudioMixerNode()
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
      if positionLFO != nil && (audioGate?.isOpen ?? (activeNoteCount > 0)) { // Always open for sampler
        if (t - lastTimeWeSetPosition) > setPositionMinWaitTimeSecs {
          lastTimeWeSetPosition = t
          let (x, y, z) = positionLFO!.of(t - 1)
          mixerNode?.position.x = Float(x)
          mixerNode?.position.y = Float(y)
          mixerNode?.position.z = Float(z)
        }
      }
    }
  }
  
  func wrapInAppleNodes(forEngine engine: SpatialAudioEngine) async throws -> AVAudioMixerNode {
    guard let mixerNode = self.mixerNode else {
      fatalError()
    }
    
    let sampleRate = engine.sampleRate
    
    // recursively tell all arrows their sample rate
    sound?.setSampleRateRecursive(rate: sampleRate)
    
    // connect our synthesis engine to an AVAudioSourceNode as the initial node in the chain,
    // else create an AVAudioUnitSampler to fill that role
    var initialNode: AVAudioNode?
    if let audioGate = audioGate {
      sourceNode = AVAudioSourceNode.withSource(
        source: audioGate,
        sampleRate: sampleRate
      )
      initialNode = sourceNode
    } else if let sampler = sampler {
      engine.attach([sampler.node])
      do {
        try await sampler.loadInstrument()
      } catch {
        // Detach the sampler node we just attached before re-throwing
        engine.detach([sampler.node])
        throw error
      }
      initialNode = sampler.node
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
        guard let engine = self.mixerNode!.engine else {
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
    let allNodes: [AVAudioNode?] = [sourceNode, sampler?.node, distortionNode, delayNode, reverbNode, mixerNode]
    let nodes = allNodes.compactMap { $0 }
    engine.detach(nodes)
  }
  
}
