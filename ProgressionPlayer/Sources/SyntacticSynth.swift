//
//  SyntacticSynth.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 12/5/25.
//

import AVFAudio
import SwiftUI

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

@Observable
class SyntacticSynth: EngineAndVoicePool {
  let engine = SpatialAudioEngine()
  var voicePool: NoteHandler? = nil
  let numVoices = 4
  var tones = [ArrowWithHandles]()
  var presets = [Preset]()
  var ampAttack: CoreFloat = 0.1 {
    didSet {
      print("\(ampAttack)")
      tones[0].namedADSREnvelopes["ampEnv"]!.env.attackTime = ampAttack
    }
  }
  
  func featurefulSynth1() -> ArrowSyntax {
    // working inside out, from raw time to the full synth
    
    // 1. the time, multiplied for frequency purposes
    let time = ArrowSyntax.identity
    let freq = ArrowSyntax.const(NamedFloat (name: "freq", val: 300))
    let freqTime = ArrowSyntax.nary (NamedArrowSyntaxList (name: "prod", arrows: [freq, time]))
    // 2. the vibrato wave
    let vibratoFreq = ArrowSyntax.const(NamedFloat (name: "vibratoFreq", val: 3))
    let vibratoFreqTime = ArrowSyntax.nary (NamedArrowSyntaxList (name: "prod", arrows: [vibratoFreq, time]))
    let vibratoWave = ArrowSyntax.unary(NamedArrowSyntax (name: BasicOscillator.OscShape.sine.rawValue, arrow: vibratoFreqTime))
    let vibratoAmp = ArrowSyntax.const(NamedFloat (name: "vibratoAmp", val: 0))
    let vibrato = ArrowSyntax.unary(NamedArrowSyntax(name: "control", arrow: ArrowSyntax.nary (NamedArrowSyntaxList (name: "prod", arrows: [vibratoAmp, vibratoWave]))))
    // 3. vibrato on the time -- this is ready for doing wavy stuff now
    let vibratoNote = ArrowSyntax.nary (NamedArrowSyntaxList (name: "sum", arrows: [freqTime, vibrato]))
    // 4. the oscillator
    let oscTone = ArrowSyntax.unary(NamedArrowSyntax(name: BasicOscillator.OscShape.sawtooth.rawValue, arrow: vibratoNote))
    // 5. the envelopes
    let ampEnv = ArrowSyntax.envelope(ADSRSyntax(name: "ampEnv", attack: ampAttack, decay: 0.1, sustain: 1.0, release: 0.1, scale: 1.0))
    let filterEnv = ArrowSyntax.envelope(ADSRSyntax(name: "filterEnv", attack: 0.3, decay: 0.1, sustain: 1.0, release: 0.1, scale: 1.0))
    // 6. multiply the envelopes
    let cutoff = ArrowSyntax.const(NamedFloat(name: "cutoff", val: 1000.0))
    //let vibratoCutoff = ArrowSyntax.nary (NamedArrowSyntaxList (name: "sum", arrows: [cutoff, vibratoWave]))
    
    let envelopedCutoff = ArrowSyntax.nary(NamedArrowSyntaxList(name: "prod", arrows: [cutoff, filterEnv]))
    let envelopedOscTone = ArrowSyntax.nary(NamedArrowSyntaxList(name: "prod", arrows: [oscTone, ampEnv]))
    
    // 5. the filter
    let filteredTone = ArrowSyntax.lowPassFilter(LowPassArrowSyntax(
      name: "filter",
      cutoff: envelopedCutoff,
      resonance: ArrowSyntax.const(NamedFloat(name: "resonance", val: 1000.0)),
      arrow: envelopedOscTone
    ))
    return filteredTone
  }
  
  init() {
    var avNodes = [AVAudioMixerNode]()
    for _ in 1...8 {
      let sound = featurefulSynth1().compile()
      tones.append(sound) 
      let preset = Preset(sound: sound)
      preset.positionLFO = Rose(
        amp: ArrowConst(5),
        leafFactor: ArrowConst(3),
        freq: ArrowConst(0.1),
        phase: CoreFloat.random(in: 0.0...(2 * .pi))
      )
      preset.setReverbWetDryMix(50)
      presets.append(preset)
      let node = preset.buildChainAndGiveOutputNode(forEngine: self.engine)
      avNodes.append(node)
    }
    engine.connectToEnvNode(avNodes)
    voicePool = PoolVoice(voices: tones.map { EnvelopeHandlePlayer(arrow: $0) })
  }
}

struct SyntacticSynthView: View {
  @State private var synth = SyntacticSynth()
  @State private var seq: Sequencer? = nil
  @State private var error: Error? = nil
  @State private var isImporting = false
  @State private var songURL: URL? = nil
  
  var body: some View {
    ForEach(["D_Loop_01", "MSLFSanctus"], id: \.self) { song in
      Button("Play \(song)") {
        songURL = Bundle.main.url(forResource: song, withExtension: "mid")  
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
    // NOTE: I have removed @Observable from some classes in an attempt to resolve perf problems, so this knob is
    // not going to reflect the attackTime in all likelihood
    KnobbyKnob(value: Binding($synth.tones[0].namedADSREnvelopes["ampEnv"])!.env.attackTime,
               range: 0...2,
               size: 80,
               stepSize: 0.05,
               allowPoweroff: false,
               ifShowValue: true,
               valueFormatter: { String(format: "%.2f", $0)})

  }
}

#Preview {
  SyntacticSynthView()
}
