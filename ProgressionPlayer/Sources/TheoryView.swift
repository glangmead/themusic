//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import AVFAudio
import SwiftUI
import Tonic

class KnobbySynth {
  let engine = SpatialAudioEngine()
  
  let numVoices = 8
  // the layer cake of tone generation: oscillator, wrapped in filter, then voice, then preset
  var oscillators: [BasicOscillator] = []
  var filters: [HasFactor] = []
  var voices: [SimpleVoice] = []
  var presets: [Preset] = []
  
  var voiceMixerNodes: [AVAudioMixerNode] = []
  let voicePool: NoteHandler
  
  var seq: Sequencer? = nil
  
  // Bindings
  var oscillatorShapeBinding: Binding<BasicOscillator.OscShape>? = nil
  var reverbWetDryMixBinding: Binding<Double>? = nil
  var spatialPositionBinding: Binding<(Double, Double, Double)>? = nil
  var delayTimeBinding: Binding<Double>? = nil
  var delayFeedbackBinding: Binding<Double>? = nil
  var delayLowPassCutoffBinding: Binding<Double>? = nil
  var delayWetDryMixBinding: Binding<Double>? = nil
  var distortionPreGainBinding: Binding<Double>? = nil
  var distortionWetDryMixBinding: Binding<Double>? = nil
  var reverbPresetBinding: Binding<AVAudioUnitReverbPreset>? = nil
  var distortionPresetBinding: Binding<AVAudioUnitDistortionPreset>? = nil
  var filterCutoffBinding: Binding<Double>? = nil
  
  var key = Key.C
  var octave: Int = 2
  
  var keyChords: [Chord] {
    get {
      key.chords.filter { chord in
        [.major, .minor, .dim, .dom7, .maj7, .min7].contains(chord.type)
      }
      .sorted {
        $0.description < $1.description
      }
    }
  }
  
  init() {
    for _ in 0..<numVoices {
      let osc = BasicOscillator(shape: .sawtooth)
      oscillators.append(osc)
      let filteredOsc = LowPassFilter(of: osc, cutoff: 100000, resonance: 0)
      filters.append(filteredOsc)
      
      var roseAmount = 3.0
      let voice = SimpleVoice(
        oscillator:
          ModulatedPreMult(
            factor: 440.0,
            arrow: filteredOsc,
            modulation:
              PostMult(
                factor: 0,
                arrow:  PreMult(factor: 5.0, arrow: Triangle)
              )
              .asControl()
          ),
        ampMod:
          ADSR(
            envelope:
              EnvelopeData(
                attackTime: 0.3,
                decayTime: 0,
                sustainLevel: 1.0,
                releaseTime: 0.2
              )
          ),
        filterMod:
          ADSR(
            envelope:
              EnvelopeData(
                attackTime: 0.3,
                decayTime: 0,
                sustainLevel: 1,
                releaseTime: 0.2,
                scale: 1000
              )
          )
      )
      voices.append(voice)
      let preset = Preset(sound: voice)
      preset.positionLFO = Rose(
        amplitude: 2,
        leafFactor: roseAmount,
        frequency: 0.5,
        startingPhase: roseAmount * 2 * .pi / Double(presets.count)
      )
      roseAmount += 2.0
      presets.append(preset)
    }
    
    voicePool = PoolVoice(voices: voices)
        
    reverbWetDryMixBinding = Binding<Double>(
      get: { self.presets[0].getReverbWetDryMix() },
      set: { for preset in self.presets { preset.setReverbWetDryMix($0) } }
    )
    spatialPositionBinding = Binding<(Double, Double, Double)>(
      get: { self.presets[0].getSpatialPosition() },
      set: { for preset in self.presets { preset.setSpatialPosition($0) } }
    )
    delayTimeBinding = Binding<Double>(
      get: { self.presets[0].getDelayTime() },
      set: { for preset in self.presets { preset.setDelayTime($0) } }
    )
    delayFeedbackBinding = Binding<Double>(
      get: { self.presets[0].getDelayFeedback() },
      set: { for preset in self.presets { preset.setDelayFeedback($0) } }
    )
    delayLowPassCutoffBinding = Binding<Double>(
      get: { self.presets[0].getDelayFeedback() },
      set: { for preset in self.presets { preset.setDelayLowPassCutoff($0) } }
    )
    delayWetDryMixBinding = Binding<Double>(
      get: { self.presets[0].getDelayWetDryMix() },
      set: { for preset in self.presets { preset.setDelayWetDryMix($0) } }
    )
    distortionPreGainBinding = Binding<Double>(
      get: { self.presets[0].getDelayFeedback() },
      set: { for preset in self.presets { preset.setDistortionPreGain($0) } }
    )
    distortionWetDryMixBinding = Binding<Double>(
      get: { self.presets[0].getDelayFeedback() },
      set: { for preset in self.presets { preset.setDistortionWetDryMix($0) } }
    )
    reverbPresetBinding = Binding<AVAudioUnitReverbPreset>(
      get: { return self.presets[0].reverbPreset },
      set: { for preset in self.presets { preset.reverbPreset = $0 } }
    )
    distortionPresetBinding = Binding<AVAudioUnitDistortionPreset>(
      get: { self.presets[0].getDistortionPreset() },
      set: { for preset in self.presets { preset.setDistortionPreset($0) } }
    )
    oscillatorShapeBinding = Binding<BasicOscillator.OscShape>(
      get: { self.oscillators[0].shape },
      set: { for osc in self.oscillators { osc.shape = $0 }}
    )
    filterCutoffBinding = Binding<Double>(
      get: { return 0 },
      set: { _ in () }
    )
    voiceMixerNodes = presets.map {  $0.buildChainAndGiveOutputNode(forEngine: self.engine) }
    engine.connectToEnvNode(voiceMixerNodes)
    
    do {
      try engine.start()
    } catch {
      print("engine failed")
    }
    
    // the sequencer will pluck on the arrows
    self.seq = Sequencer(engine: engine.audioEngine, numTracks: 2,  sourceNode: voicePool)
    
  }
}

struct TheoryView: View {
  @State private var synth: KnobbySynth
  @State private var error: Error?
  @State private var isImporting = false

  init(synth: KnobbySynth) {
    self.synth = synth
  }
  
  var body: some View {
    NavigationStack {
      Picker("Instrument", selection: synth.oscillatorShapeBinding!) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)

      HStack {
        Text("Reverb preset")
        Picker("Reverb preset", selection: synth.reverbPresetBinding!) {
          ForEach(AVAudioUnitReverbPreset.allCases, id: \.self) {
            Text($0.name)
          }
        }.pickerStyle(.menu)
      }
      HStack {
        Text("Reverb wet/dry mix")
        Slider(value: synth.reverbWetDryMixBinding!, in: 0...100)
      }
      HStack {
        Text("Delay time")
        Slider(value: synth.delayTimeBinding!, in: 0...5)
      }
      Spacer()
      Picker("Key", selection: $synth.key) {
        Text("C").tag(Key.C)
        Text("G").tag(Key.G)
        Text("D").tag(Key.D)
        Text("A").tag(Key.A)
        Text("E").tag(Key.E)
      }.pickerStyle(.segmented)
      Picker("Octave", selection: $synth.octave) {
        ForEach(1..<7) { octave in
          Text("\(octave)")
        }
      }.pickerStyle(.segmented)
      
      ScrollView {
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 100, maximum: .infinity))
          ],
          content: {
            ForEach(synth.keyChords, id: \.self) { chord in
              Button(chord.romanNumeralNotation(in: synth.key) ?? chord.description) {
                synth.seq?.sendTonicChord(chord: chord, octave: synth.octave)
                synth.seq?.play()
              }
              .frame(maxWidth: .infinity)
              //.font(.largeTitle)
              .buttonStyle(.borderedProminent)
            }
          }
        )
      }
      .navigationTitle("Scape")
      Button("Stop") {
        synth.seq?.stop()
        synth.seq?.rewind()
      }
      .toolbar {
        ToolbarItem() {
          Button {
            isImporting = true
          } label: {
            Label("Import file",
                  systemImage: "square.and.arrow.down")
          }
        }
      }
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.midi],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          synth.seq?.playURL(url: urls[0])
        case .failure(let error):
          print("\(error.localizedDescription)")
        }
      }
    }
    
  }
}

#Preview {
  TheoryView(synth: KnobbySynth())
}
