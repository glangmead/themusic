//
//  SyntacticSynth.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 12/5/25.
//

import AudioKitUI
import AVFAudio
import SwiftUI


/// TODO
/// A button to save the current synth as a preset
/// Move on to assigning different presets to different seq tracks
/// Pulse oscillator? Or a param for the square?
/// Build a library of presets
///   - Minifreak V presets that use basic oscillators
///     - 5th Clue
protocol EngineAndVoicePool: AnyObject {
  var engine: SpatialAudioEngine { get }
  var voicePool: NoteHandler? { get }
}

// The Synth is the object that contains a pool of voices. So for params that are meant to influence all voices
// in the same way, the Synth must do that copying.
@Observable
class SyntacticSynth: EngineAndVoicePool {
  let engine: SpatialAudioEngine
  var voicePool: NoteHandler? = nil
  var poolVoice: PoolVoice? = nil
  #if DEBUG
  private let numVoices = 3
  #else
  private let numVoices = 12
  #endif
  private var tones = [ArrowWithHandles]()
  private var presets = [Preset]()
  let cent: CoreFloat = 1.0005777895065548 // '2 ** (1/1200)' in python
  
  // Tone params
  var ampAttack: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.attackTime = ampAttack } }
  }
  var ampDecay: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.decayTime = ampDecay } }
  }
  var ampSustain: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.sustainLevel = ampSustain } }
  }
  var ampRelease: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["ampEnv"]!.forEach { $0.env.releaseTime = ampRelease } }
  }
  var filterAttack: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["filterEnv"]!.forEach { $0.env.attackTime = filterAttack } }
  }
  var filterDecay: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["filterEnv"]!.forEach { $0.env.decayTime = filterDecay } }
  }
  var filterSustain: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["filterEnv"]!.forEach { $0.env.sustainLevel = filterSustain } }
  }
  var filterRelease: CoreFloat = 0 { didSet {
    poolVoice?.namedADSREnvelopes["filterEnv"]!.forEach { $0.env.releaseTime = filterRelease } }
  }
  var filterCutoff: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["cutoff"]!.forEach { $0.val = filterCutoff } }
  }
  var filterResonance: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["resonance"]!.forEach { $0.val = filterResonance } }
  }
  var vibratoAmp: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["vibratoAmp"]!.forEach { $0.val = vibratoAmp } }
  }
  var vibratoFreq: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["vibratoFreq"]!.forEach { $0.val = vibratoFreq } }
  }
  var osc1Mix: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc1Mix"]!.forEach { $0.val = osc1Mix } }
  }
  var osc2Mix: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc2Mix"]!.forEach { $0.val = osc2Mix } }
  }
  var osc3Mix: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc3Mix"]!.forEach { $0.val = osc3Mix } }
  }
  var oscShape1: BasicOscillator.OscShape = .noise { didSet {
    poolVoice?.namedBasicOscs["osc1"]!.forEach { $0.shape = oscShape1 } }
  }
  var oscShape2: BasicOscillator.OscShape = .noise { didSet {
    poolVoice?.namedBasicOscs["osc2"]!.forEach { $0.shape = oscShape2 } }
  }
  var oscShape3: BasicOscillator.OscShape = .noise { didSet {
    poolVoice?.namedBasicOscs["osc3"]!.forEach { $0.shape = oscShape3 } }
  }
  var osc1Width: CoreFloat = 0 { didSet {
    poolVoice?.namedBasicOscs["osc1"]!.forEach { $0.width = osc1Width } }
  }
  var osc1ChorusCentRadius: CoreFloat = 0 { didSet {
    poolVoice?.namedChorusers["osc1Choruser"]!.forEach { $0.chorusCentRadius = Int(osc1ChorusCentRadius) } }
  }
  var osc1ChorusNumVoices: CoreFloat = 0 { didSet {
    poolVoice?.namedChorusers["osc1Choruser"]!.forEach { $0.chorusNumVoices = Int(osc1ChorusNumVoices) } }
  }
  var osc1CentDetune: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc1CentDetune"]!.forEach { $0.val = osc1CentDetune } }
  }
  var osc1Octave: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc1Octave"]!.forEach { $0.val = osc1Octave } }
  }
  var osc2CentDetune: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc2CentDetune"]!.forEach { $0.val = osc2CentDetune } }
  }
  var osc2Octave: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc2Octave"]!.forEach { $0.val = osc2Octave } }
  }
  var osc3CentDetune: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc3CentDetune"]!.forEach { $0.val = osc3CentDetune } }
  }
  var osc3Octave: CoreFloat = 0 { didSet {
    poolVoice?.namedConsts["osc3Octave"]!.forEach { $0.val = osc3Octave } }
  }
  var osc2Width: CoreFloat = 0 { didSet {
    poolVoice?.namedBasicOscs["osc2"]!.forEach { $0.width = osc2Width } }
  }
  var osc2ChorusCentRadius: CoreFloat = 0 { didSet {
    poolVoice?.namedChorusers["osc2Choruser"]!.forEach { $0.chorusCentRadius = Int(osc2ChorusCentRadius) } }
  }
  var osc2ChorusNumVoices: CoreFloat = 0 { didSet {
    poolVoice?.namedChorusers["osc1Choruser"]!.forEach { $0.chorusNumVoices = Int(osc2ChorusNumVoices) } }
  }
  var osc3Width: CoreFloat = 0 { didSet {
    poolVoice?.namedBasicOscs["osc3"]!.forEach { $0.width = osc3Width } }
  }
  var osc3ChorusCentRadius: CoreFloat = 0 { didSet {
    poolVoice?.namedChorusers["osc3Choruser"]!.forEach { $0.chorusCentRadius = Int(osc3ChorusCentRadius) } }
  }
  var osc3ChorusNumVoices: CoreFloat = 0 { didSet {
    poolVoice?.namedChorusers["osc3Choruser"]!.forEach { $0.chorusNumVoices = Int(osc3ChorusNumVoices) } }
  }
  var roseFreq: CoreFloat = 0 { didSet {
    presets.forEach { $0.positionLFO?.freq.val = roseFreq } }
  }
  var roseAmp: CoreFloat = 0 { didSet {
    presets.forEach { $0.positionLFO?.amp.val = roseAmp } }
  }
  var roseLeaves: CoreFloat = 0 { didSet {
    presets.forEach { $0.positionLFO?.leafFactor.val = roseLeaves } }
  }

  // FX params
  var distortionAvailable: Bool {
    presets[0].distortionAvailable
  }
  
  var delayAvailable: Bool {
    presets[0].delayAvailable
  }
  
  var reverbMix: CoreFloat = 50 {
    didSet {
      for preset in self.presets { preset.setReverbWetDryMix(reverbMix) }
      // not effective: engine.envNode.reverbBlend = reverbMix / 100 // (env node uses 0-1 instead of 0-100)
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

  init(engine: SpatialAudioEngine) {
    self.engine = engine
    var avNodes = [AVAudioMixerNode]()
    let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")
    for _ in 1...numVoices {
      let preset = presetSpec.compile()
      presets.append(preset)
      let sound = preset.sound
      tones.append(sound)
      
      let node = preset.wrapInAppleNodes(forEngine: self.engine)
      avNodes.append(node)
    }
    engine.connectToEnvNode(avNodes)
    // voicePool is the object that the sequencer plays
    let poolVoice = PoolVoice(voices: tones.map { EnvelopeHandlePlayer(arrow: $0) })
    self.poolVoice = poolVoice
    voicePool = poolVoice
    
    // read from poolVoice to see what keys we must support getting/setting
    if poolVoice.namedADSREnvelopes["ampEnv"] != nil {
      ampAttack  = poolVoice.namedADSREnvelopes["ampEnv"]!.first!.env.attackTime
      ampDecay   = poolVoice.namedADSREnvelopes["ampEnv"]!.first!.env.decayTime
      ampSustain = poolVoice.namedADSREnvelopes["ampEnv"]!.first!.env.sustainLevel
      ampRelease = poolVoice.namedADSREnvelopes["ampEnv"]!.first!.env.releaseTime
    }

    if poolVoice.namedADSREnvelopes["filterEnv"] != nil {
      filterAttack  = poolVoice.namedADSREnvelopes["filterEnv"]!.first!.env.attackTime
      filterDecay   = poolVoice.namedADSREnvelopes["filterEnv"]!.first!.env.decayTime
      filterSustain = poolVoice.namedADSREnvelopes["filterEnv"]!.first!.env.sustainLevel
      filterRelease = poolVoice.namedADSREnvelopes["filterEnv"]!.first!.env.releaseTime
    }
    
    filterCutoff = poolVoice.namedConsts["cutoff"]!.first!.val
    filterResonance = poolVoice.namedConsts["resonance"]!.first!.val
    
    vibratoAmp = poolVoice.namedConsts["vibratoAmp"]!.first!.val
    vibratoFreq = poolVoice.namedConsts["vibratoFreq"]!.first!.val
    
    osc1Mix = poolVoice.namedConsts["osc1Mix"]!.first!.val
    osc2Mix = poolVoice.namedConsts["osc2Mix"]!.first!.val
    osc3Mix = poolVoice.namedConsts["osc3Mix"]!.first!.val
    
    osc1ChorusCentRadius = CoreFloat(poolVoice.namedChorusers["osc1Choruser"]!.first!.chorusCentRadius)
    osc1ChorusNumVoices  = CoreFloat(poolVoice.namedChorusers["osc1Choruser"]!.first!.chorusNumVoices)
    osc2ChorusCentRadius = CoreFloat(poolVoice.namedChorusers["osc2Choruser"]!.first!.chorusCentRadius)
    osc2ChorusNumVoices  = CoreFloat(poolVoice.namedChorusers["osc2Choruser"]!.first!.chorusNumVoices)
    osc3ChorusCentRadius = CoreFloat(poolVoice.namedChorusers["osc3Choruser"]!.first!.chorusCentRadius)
    osc3ChorusNumVoices  = CoreFloat(poolVoice.namedChorusers["osc3Choruser"]!.first!.chorusNumVoices)

    oscShape1 = poolVoice.namedBasicOscs["osc1"]!.first!.shape
    oscShape2 = poolVoice.namedBasicOscs["osc2"]!.first!.shape
    oscShape3 = poolVoice.namedBasicOscs["osc3"]!.first!.shape

    osc1Width = poolVoice.namedBasicOscs["osc1"]!.first!.width
    osc2Width = poolVoice.namedBasicOscs["osc2"]!.first!.width
    osc3Width = poolVoice.namedBasicOscs["osc3"]!.first!.width

    osc1Octave = poolVoice.namedConsts["osc1Octave"]!.first!.val
    osc2Octave = poolVoice.namedConsts["osc2Octave"]!.first!.val
    osc3Octave = poolVoice.namedConsts["osc3Octave"]!.first!.val

    osc1CentDetune = poolVoice.namedConsts["osc1CentDetune"]!.first!.val
    osc2CentDetune = poolVoice.namedConsts["osc2CentDetune"]!.first!.val
    osc3CentDetune = poolVoice.namedConsts["osc3CentDetune"]!.first!.val
    
    roseAmp = presets[0].positionLFO!.amp.val
    roseFreq = presets[0].positionLFO!.freq.val
    roseLeaves = presets[0].positionLFO!.leafFactor.val
    
    reverbPreset = presets[0].reverbPreset
    reverbMix = presets[0].getReverbWetDryMix()
    
    delayTime = presets[0].getDelayTime()
    delayFeedback = presets[0].getDelayFeedback()
    delayWetDryMix = presets[0].getDelayWetDryMix()
    delayLowPassCutoff = presets[0].getDelayLowPassCutoff()
    
    distortionPreset = presets[0].getDistortionPreset()
    distortionPreGain = presets[0].getDistortionPreGain()
    distortionWetDryMix = presets[0].getDistortionWetDryMix()
  }
}

struct SyntacticSynthView: View {
  @State private var synth: SyntacticSynth
  @State private var seq: Sequencer? = nil
  
  init(synth: SyntacticSynth) {
    self.synth = synth
  }
  
  var body: some View {

    ScrollView {
      Spacer()
      
      ArrowChart(arrow: (synth.poolVoice!.namedBasicOscs["osc1"]!.first)!)
      
      Picker("Instrument 1", selection: $synth.oscShape1) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)
      Picker("Instrument 2", selection: $synth.oscShape2) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)
      Picker("Instrument 3", selection: $synth.oscShape3) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)
      HStack {
        KnobbyKnob(value: $synth.osc1CentDetune, label: "Detune1", range: -500...500, stepSize: 1)
        KnobbyKnob(value: $synth.osc1Octave, label: "Oct1", range: -5...5, stepSize: 1)
        KnobbyKnob(value: $synth.osc1ChorusCentRadius, label: "Cents1", range: 0...30, stepSize: 1)
        KnobbyKnob(value: $synth.osc1ChorusNumVoices, label: "Voices1", range: 1...12, stepSize: 1)
        KnobbyKnob(value: $synth.osc1Width, label: "PulseW1", range: 0...1)
      }
      HStack {
        KnobbyKnob(value: $synth.osc2CentDetune, label: "Detune2", range: -500...500, stepSize: 1)
        KnobbyKnob(value: $synth.osc2Octave, label: "Oct2", range: -5...5, stepSize: 1)
        KnobbyKnob(value: $synth.osc2ChorusCentRadius, label: "Cents2", range: 0...30, stepSize: 1)
        KnobbyKnob(value: $synth.osc2ChorusNumVoices, label: "Voices2", range: 1...12, stepSize: 1)
        KnobbyKnob(value: $synth.osc2Width, label: "PulseW2", range: 0...1)
      }
      HStack {
        KnobbyKnob(value: $synth.osc3CentDetune, label: "Detune3", range: -500...500, stepSize: 1)
        KnobbyKnob(value: $synth.osc3Octave, label: "Oct3", range: -5...5, stepSize: 1)
        KnobbyKnob(value: $synth.osc3ChorusCentRadius, label: "Cents3", range: 0...30, stepSize: 1)
        KnobbyKnob(value: $synth.osc3ChorusNumVoices, label: "Voices3", range: 1...12, stepSize: 1)
        KnobbyKnob(value: $synth.osc3Width, label: "PulseW3", range: 0...1)
      }
      HStack {
        KnobbyKnob(value: $synth.osc1Mix, label: "Osc1", range: 0...1)
        KnobbyKnob(value: $synth.osc2Mix, label: "Osc2", range: 0...1)
        KnobbyKnob(value: $synth.osc3Mix, label: "Osc3", range: 0...1)
      }
      HStack {
        KnobbyKnob(value: $synth.ampAttack, label: "Amp atk", range: 0...2)
        KnobbyKnob(value: $synth.ampDecay, label: "Amp dec", range: 0...2)
        KnobbyKnob(value: $synth.ampSustain, label: "Amp sus")
        KnobbyKnob(value: $synth.ampRelease, label: "Amp rel", range: 0...2)
      }
      HStack {
        KnobbyKnob(value: $synth.filterAttack, label:  "Filter atk", range: 0...2)
        KnobbyKnob(value: $synth.filterDecay, label:   "Filter dec", range: 0...2)
        KnobbyKnob(value: $synth.filterSustain, label: "Filter sus")
        KnobbyKnob(value: $synth.filterRelease, label: "Filter rel", range: 0.03...2)
      }
      HStack {
        KnobbyKnob(value: $synth.filterCutoff, label:  "Filter cut", range: 1...20000, stepSize: 1)
        KnobbyKnob(value: $synth.filterResonance, label: "Filter res", range: 0.1...15, stepSize: 0.01)
      }
      HStack {
        KnobbyKnob(value: $synth.vibratoAmp, label:  "Vib amp", range: 0...20)
        KnobbyKnob(value: $synth.vibratoFreq, label: "Vib freq", range: 0...30)
      }
      HStack {
        KnobbyKnob(value: $synth.roseAmp, label:  "Rose amp", range: 0...20)
        KnobbyKnob(value: $synth.roseFreq, label: "Rose freq", range: 0...30)
        KnobbyKnob(value: $synth.roseLeaves, label: "Rose leaves", range: 0...30)
      }
      HStack {
        VStack {
          Picker("Preset", selection: $synth.reverbPreset) {
            ForEach(AVAudioUnitReverbPreset.allCases, id: \.self) { option in
              Text(option.name)
            }
          }
          .pickerStyle(.menu)
          Text("Reverb")
        }
        KnobbyKnob(value: $synth.reverbMix, label:  "Dry/Wet", range: 0...100)
      }
      if synth.delayAvailable {
        HStack {
          KnobbyKnob(value: $synth.delayTime, label: "Delay", range: 0...30)
          KnobbyKnob(value: $synth.delayFeedback, label: "Dly fdbk", range: 0...30)
          KnobbyKnob(value: $synth.delayWetDryMix, label: "Dly mix", range: 0...100)
          KnobbyKnob(value: $synth.delayLowPassCutoff, label: "Dly flt", range: 0...1000)
        }
      }
      if synth.distortionAvailable {
        HStack {
          VStack {
            Picker("Preset", selection: $synth.distortionPreset) {
              ForEach(AVAudioUnitDistortionPreset.allCases, id: \.self) { option in
                Text(option.name)
              }
            }
            .pickerStyle(.menu)
            Text("Distortion")
          }
          KnobbyKnob(value: $synth.distortionPreGain, label: "Pregain", range: 0...30)
          KnobbyKnob(value: $synth.distortionWetDryMix, label: "Dry/wet", range: 0...100)
        }
      }
    }
    .onAppear {
      if seq == nil {
        do {
          try! synth.engine.start()
        }
        seq = Sequencer(synth: synth, numTracks: 2)
      }
    }
  }
}

#Preview {
  SyntacticSynthView(synth: SyntacticSynth(engine: SpatialAudioEngine()))
}
