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
/// Knobs
/// A button to save the current synth as a preset
/// Move on to assigning different presets to different seq tracks
/// Build a library of presets
protocol EngineAndVoicePool {
  var engine: SpatialAudioEngine { get }
  var voicePool: NoteHandler? { get }
}

class PlayableArrowWithHandles: NoteHandler {
  var arrow: ArrowWithHandles
  var noteHandleKeys: [String]
  init(arrow: ArrowWithHandles, noteHandleKeys: [String]) {
    self.arrow = arrow
    self.noteHandleKeys = noteHandleKeys
  }
  
  func noteOn(_ note: MidiNote) {
    // play the designated note
    for noteHandleKey in noteHandleKeys {
      arrow.namedConsts[noteHandleKey]?.val = note.freq
    }
    // play all the envelopes
    for env in arrow.namedADSREnvelopes.values {
      env.noteOn(note)
    }
  }
  
  func noteOff(_ note: MidiNote) {
    for env in arrow.namedADSREnvelopes.values {
      env.noteOff(note)
    }
  }
}

// The Synth is the object that contains a pool of voices. So for params that are meant to influence all voices
// in the same way, the Synth must do that copying.
@Observable
class SyntacticSynth: EngineAndVoicePool {
  let engine = SpatialAudioEngine()
  var voicePool: NoteHandler? = nil
  
  private let numVoices = 8
  private var tones = [ArrowWithHandles]()
  private var presets = [Preset]()
  private var basicOscHandles = [String]()
  private var lowPassFilterHandles = [String]()
  private var constsHandles = [String]()
  private var envelopesHandles = [String]()
  
  // Tone params
  var ampAttack: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["ampEnv"]!.env.attackTime = ampAttack } }
  }
  var ampDecay: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["ampEnv"]!.env.decayTime = ampDecay } }
  }
  var ampSustain: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["ampEnv"]!.env.sustainLevel = ampSustain } }
  }
  var ampRelease: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["ampEnv"]!.env.releaseTime = ampRelease } }
  }
  var filterAttack: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["filterEnv"]!.env.attackTime = filterAttack } }
  }
  var filterDecay: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["filterEnv"]!.env.decayTime = filterDecay } }
  }
  var filterSustain: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["filterEnv"]!.env.sustainLevel = filterSustain } }
  }
  var filterRelease: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedADSREnvelopes["filterEnv"]!.env.releaseTime = filterRelease } }
  }
  var filterCutoff: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedConsts["cutoff"]!.val = filterCutoff } }
  }
  var filterResonance: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedConsts["resonance"]!.val = filterCutoff } }
  }
  var vibratoAmp: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedConsts["vibratoAmp"]!.val = vibratoAmp } }
  }
  var vibratoFreq: CoreFloat = 0 { didSet {
    for tone in tones { tone.namedConsts["vibratoFreq"]!.val = vibratoFreq } }
  }
  var oscShape: BasicOscillator.OscShape = .noise { didSet {
    for tone in tones { tone.namedBasicOscs["osc1"]!.shape = oscShape } }
  }
  var roseFreq: CoreFloat = 0 { didSet {
    for preset in presets { preset.positionLFO?.freq.val = roseFreq } }
  }
  var roseAmp: CoreFloat = 0 { didSet {
    for preset in presets { preset.positionLFO?.amp.val = roseAmp } }
  }
  var roseLeaves: CoreFloat = 0 { didSet {
    for preset in presets { preset.positionLFO?.leafFactor.val = roseLeaves } }
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


  init() {
    var avNodes = [AVAudioMixerNode]()
    let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")
    for _ in 1...numVoices {
      let preset = presetSpec.compile()
      presets.append(preset)
      let sound = preset.sound
      tones.append(sound)
      
      let node = preset.buildChainAndGiveOutputNode(forEngine: self.engine)
      avNodes.append(node)
    }
    engine.connectToEnvNode(avNodes)
    voicePool = PoolVoice(voices: tones.map { EnvelopeHandlePlayer(arrow: $0) })
    
    // read from tones[0] to see what keys we must support getting/setting
    ampAttack = tones[0].namedADSREnvelopes["ampEnv"]!.env.attackTime
    ampDecay = tones[0].namedADSREnvelopes["ampEnv"]!.env.decayTime
    ampSustain = tones[0].namedADSREnvelopes["ampEnv"]!.env.sustainLevel
    ampRelease = tones[0].namedADSREnvelopes["ampEnv"]!.env.releaseTime

    filterAttack = tones[0].namedADSREnvelopes["filterEnv"]!.env.attackTime
    filterDecay = tones[0].namedADSREnvelopes["filterEnv"]!.env.decayTime
    filterSustain = tones[0].namedADSREnvelopes["filterEnv"]!.env.sustainLevel
    filterRelease = tones[0].namedADSREnvelopes["filterEnv"]!.env.releaseTime
    
    filterCutoff = tones[0].namedConsts["cutoff"]!.val
    filterResonance = tones[0].namedConsts["resonance"]!.val
    
    vibratoAmp = tones[0].namedConsts["vibratoAmp"]!.val
    vibratoFreq = tones[0].namedConsts["vibratoFreq"]!.val
    
    oscShape = tones[0].namedBasicOscs["osc1"]!.shape
    
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
    ForEach(["D_Loop_01", "MSLFSanctus"], id: \.self) { song in
      Button("Play \(song)") {
        let songURL = Bundle.main.url(forResource: song, withExtension: "mid")
        seq?.playURL(url: songURL!)
      }
    }
    Button("Stop") {
      seq?.stop()
    }
    Button("Rewind") {
      seq?.stop()
      seq?.rewind()
    }
    .onAppear {
      if seq == nil {
        do {
          try! synth.engine.start()
        }
        seq = Sequencer(synth: synth, numTracks: 2) 
      }
    }

    ScrollView {
      Picker("Instrument", selection: $synth.oscShape) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)
      HStack {
        KnobbyKnob(value: $synth.ampAttack, label: "Amp env", range: 0...2)
        KnobbyKnob(value: $synth.ampDecay, label: "Amp dec", range: 0...2)
        KnobbyKnob(value: $synth.ampSustain, label: "Amp sus")
        KnobbyKnob(value: $synth.ampRelease, label: "Amp rel", range: 0...2)
      }
      HStack {
        KnobbyKnob(value: $synth.filterAttack, label:  "Filter env", range: 0...2)
        KnobbyKnob(value: $synth.filterDecay, label:   "Filter dec", range: 0...2)
        KnobbyKnob(value: $synth.filterSustain, label: "Filter sus")
        KnobbyKnob(value: $synth.filterRelease, label: "Filter rel", range: 0...2)
      }
      HStack {
        KnobbyKnob(value: $synth.filterCutoff, label:  "Filter cut", range: 0...10000, stepSize: 1)
        KnobbyKnob(value: $synth.filterRelease, label: "Filter res", range: 0...2)
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
  }
}

#Preview {
  SyntacticSynthView(synth: SyntacticSynth())
}
