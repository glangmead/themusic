//
//  KnobbySynth.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/28/25.
//

import AVFAudio

@Observable
class KnobbySynth {
  let engine = SpatialAudioEngine()
  
  let numVoices = 8
  
  // one oscillator and filtered oscillator is shared among all voices
  var oscillator: BasicOscillator? = nil
  var filteredOsc: LowPassFilter? = nil
  
  var roseAmount: ArrowConstF = ArrowConstF(1)
  var roseAmplitude: ArrowConstF = ArrowConstF(5)
  var roseFrequency: ArrowConstF = ArrowConstF(2)
  
  var ampEnvs: [ADSR] = []
  var filterEnvs: [ADSR] = []
  var voices: [SimpleVoice] = []
  var presets: [Preset] = []
  
  var ampAttack: CoreFloat = 0.01 {
    didSet {
      for adsr in ampEnvs { adsr.env.attackTime = ampAttack }
    }
  }
  var ampDecay: CoreFloat = 0 {
    didSet {
      for adsr in ampEnvs { adsr.env.decayTime = ampDecay }
    }
  }
  var ampSustain: CoreFloat = 1.0 {
    didSet {
      print("amp Sustain now \(ampSustain)")
      for adsr in ampEnvs { adsr.env.sustainLevel = ampSustain }
    }
  }
  var ampRelease: CoreFloat = 0.01 {
    didSet {
      for adsr in ampEnvs { adsr.env.releaseTime = ampRelease }
    }
  }
  var filterAttack: CoreFloat = 0 {
    didSet {
      for adsr in filterEnvs { adsr.env.attackTime = filterAttack }
    }
  }
  var filterDecay: CoreFloat = 0 {
    didSet {
      for adsr in filterEnvs { adsr.env.decayTime = filterDecay }
    }
  }
  var filterSustain: CoreFloat = 1.0 {
    didSet {
      for adsr in filterEnvs { adsr.env.sustainLevel = filterSustain }
    }
  }
  var filterRelease: CoreFloat = 0 {
    didSet {
      for adsr in filterEnvs { adsr.env.releaseTime = filterRelease }
    }
  }
  var filterScale: CoreFloat = 1000 {
    didSet {
      for adsr in filterEnvs { adsr.env.scale = filterScale }
    }
  }
  var reverbMix: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setReverbWetDryMix(reverbMix) }
      // not effective: engine.envNode.reverbBlend = reverbMix / 100 // env node uses 0-1 instead of 0-100
    }
  }
  var reverbPreset: AVAudioUnitReverbPreset = .largeRoom {
    didSet {
      for preset in self.presets { preset.reverbPreset = reverbPreset }
      // not effective: engine.envNode.reverbParameters.loadFactoryReverbPreset(reverbPreset)
    }
  }
  var delayTime: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDelayTime(delayTime) }
    }
  }
  var delayFeedback: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDelayFeedback(delayFeedback) }
    }
  }
  var delayLowPassCutoff: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDelayLowPassCutoff(delayLowPassCutoff) }
    }
  }
  var delayWetDryMix: CoreFloat = 50 {
    didSet {
      for preset in self.presets { preset.setDelayWetDryMix(delayWetDryMix) }
    }
  }
  var distortionPreGain: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDistortionPreGain(distortionPreGain) }
    }
  }
  var distortionWetDryMix: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDistortionWetDryMix(distortionWetDryMix) }
    }
  }
  var distortionPreset: AVAudioUnitDistortionPreset = .multiDecimated1 {
    didSet {
      for preset in self.presets { preset.setDistortionPreset(distortionPreset) }
    }
  }
  var voiceMixerNodes: [AVAudioMixerNode] = []
  var voicePool: NoteHandler? = nil
  
  init() {
    oscillator = BasicOscillator(shape: .sawtooth)
    filteredOsc = LowPassFilter(of: oscillator!, cutoff: 1000, resonance: 0)
    
    
    for _ in 0..<numVoices {
      let ampEnv = ADSR(envelope: EnvelopeData(
        attackTime: ampAttack,
        decayTime: ampDecay,
        sustainLevel: ampSustain,
        releaseTime: ampRelease
      ))
      let filterEnv = ADSR(envelope: EnvelopeData(
        attackTime: filterAttack,
        decayTime: filterDecay,
        sustainLevel: filterSustain,
        releaseTime: filterRelease,
        scale: filterScale
      ))
      ampEnvs.append(ampEnv)
      filterEnvs.append(filterEnv)
      let voice = SimpleVoice(
        oscillator:
          ModulatedPreMult(
            factor: 440.0,
            arrow: filteredOsc!,
            modulation:
              PostMult(
                factor: 0,
                arrow:  PreMult(factor: 5.0, arrow: Triangle)
              )
              .asControl()
          ),
        ampMod: ampEnv,
        filterMod: filterEnv
      )
      voices.append(voice)
      let preset = Preset(sound: voice)
      preset.positionLFO = Rose(
        amplitude: roseAmplitude,
        leafFactor: roseAmount,
        frequency: roseFrequency,
        startingPhase: CoreFloat.random(in: 0.0...(2 * .pi * roseAmount.of(0)))
      )
      presets.append(preset)
      voiceMixerNodes.append(preset.buildChainAndGiveOutputNode(forEngine: self.engine))
    }
    engine.connectToEnvNode(voiceMixerNodes)
    
    voicePool = PoolVoice(voices: voices)
    
    do {
      try engine.start()
      engine.pause()
    } catch {
      print("Scape engine not starting: \(error.localizedDescription)")
    }
    self.reverbMix = 50
  }
}

