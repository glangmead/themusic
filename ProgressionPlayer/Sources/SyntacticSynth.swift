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
  let numVoices = 8
  var tones = [ArrowWithHandles]()
  var presets = [Preset]()
  
  init() {
    
    var avNodes = [AVAudioMixerNode]()
    for _ in 1...numVoices {
      let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")
      let preset = presetSpec.compile()
      presets.append(preset)
      let sound = preset.sound
      tones.append(sound)
      
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
