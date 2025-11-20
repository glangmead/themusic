//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import AVFAudio
import SwiftUI
import Tonic

// the knobs i want visible here:
// - oscillator
// - vibrato
// - envelope
// - filter envelope
// - reverb
// -

struct TheoryView: View {
  let engine: SpatialAudioEngine
  
  let numVoices = 8
  // the layer cake of tone generation: oscillator, wrapped in filter, then voice, then preset
  var oscillators: [BasicOscillator]
  var filters: [HasFactor]
  var voices: [SimpleVoice]
  let presets: [Preset]
  
  let voiceMixerNodes: [AVAudioMixerNode]
  let voicePool: NoteHandler

  let seq: Sequencer?
  
  // Bindings for properties of the oscillator and filter
  let oscillatorShapeBinding: Binding<BasicOscillator.OscShape>
  // Bindings for the effects
  let reverbWetDryMixBinding: Binding<Double>
  let spatialPositionBinding: Binding<(Double, Double, Double)>
  let delayTimeBinding: Binding<Double>
  let delayFeedbackBinding: Binding<Double>
  let delayLowPassCutoffBinding: Binding<Double>
  let delayWetDryMixBinding: Binding<Double>
  let distortionPreGainBinding: Binding<Double>
  let distortionWetDryMixBinding: Binding<Double>
  let reverbPresetBinding: Binding<AVAudioUnitReverbPreset>
  let distortionPresetBinding: Binding<AVAudioUnitDistortionPreset>
  let filterCutoffBinding: Binding<Double>

  @State private var key = Key.C
  @State private var octave: Int
  @State private var error: Error?
  @State private var isImporting = false
  
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
    let engine = SpatialAudioEngine()
    
    var oscillators: [BasicOscillator] = []
    var filters: [LowPassFilter] = []
    var voices: [SimpleVoice] = []
    for _ in 0..<numVoices {
      let osc = BasicOscillator(shape: .sawtooth)
      oscillators.append(osc)
      let filteredOsc = LowPassFilter(of: osc, cutoff: 100000, resonance: 0)
      filters.append(filteredOsc)
      
      voices.append(SimpleVoice(
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
      ))
    }
    
    voicePool = PoolVoice(voices: voices)
    
    let presets = voices.map { Preset(sound: $0) }
    
    // animate the voices with various Roses
    var roseAmount = 3.0
    for preset in presets {
      preset.positionLFO = Rose(
        amplitude: 2,
        leafFactor: roseAmount,
        frequency: 0.5,
        startingPhase: roseAmount * 2 * .pi / Double(presets.count)
      )
      roseAmount += 2.0
    }
    
    voiceMixerNodes = presets.map {  $0.buildChainAndGiveOutputNode(forEngine: engine) }
    engine.connectToEnvNode(voiceMixerNodes)
    
    do {
      try engine.start()
    } catch {
      print("engine failed")
    }
    self.engine = engine
    
    // the sequencer will pluck on the arrows
    self.seq = Sequencer(engine: engine.audioEngine, numTracks: 2,  sourceNode: voicePool)
    
    reverbWetDryMixBinding = Binding<Double>(
      get: { presets[0].getReverbWetDryMix() },
      set: { for preset in presets { preset.setReverbWetDryMix($0) } }
    )
    spatialPositionBinding = Binding<(Double, Double, Double)>(
      get: { presets[0].getSpatialPosition() },
      set: { for preset in presets { preset.setSpatialPosition($0) } }
    )
    delayTimeBinding = Binding<Double>(
      get: { presets[0].getDelayTime() },
      set: { for preset in presets { preset.setDelayTime($0) } }
    )
    delayFeedbackBinding = Binding<Double>(
      get: { presets[0].getDelayFeedback() },
      set: { for preset in presets { preset.setDelayFeedback($0) } }
    )
    delayLowPassCutoffBinding = Binding<Double>(
      get: { presets[0].getDelayFeedback() },
      set: { for preset in presets { preset.setDelayLowPassCutoff($0) } }
    )
    delayWetDryMixBinding = Binding<Double>(
      get: { presets[0].getDelayWetDryMix() },
      set: { for preset in presets { preset.setDelayWetDryMix($0) } }
    )
    distortionPreGainBinding = Binding<Double>(
      get: { presets[0].getDelayFeedback() },
      set: { for preset in presets { preset.setDistortionPreGain($0) } }
    )
    distortionWetDryMixBinding = Binding<Double>(
      get: { presets[0].getDelayFeedback() },
      set: { for preset in presets { preset.setDistortionWetDryMix($0) } }
    )
    reverbPresetBinding = Binding<AVAudioUnitReverbPreset>(
      get: { return presets[0].reverbPreset },
      set: { for preset in presets { preset.reverbPreset = $0 } }
    )
    distortionPresetBinding = Binding<AVAudioUnitDistortionPreset>(
      get: { presets[0].getDistortionPreset() },
      set: { for preset in presets { preset.setDistortionPreset($0) } }
    )
    oscillatorShapeBinding = Binding<BasicOscillator.OscShape>(
      get: { oscillators[0].shape },
      set: { for osc in oscillators { osc.shape = $0 }}
    )
    filterCutoffBinding = Binding<Double>(
      get: { return 0 },
      set: { _ in () }
    )
    self.presets = presets
    self.oscillators = oscillators
    self.filters = filters
    self.voices = voices
    self.octave = 2
  }
  
  var body: some View {
    NavigationStack {
      Picker("Instrument", selection: oscillatorShapeBinding) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)

      HStack {
        Text("Reverb preset")
        Picker("Reverb preset", selection: reverbPresetBinding) {
          ForEach(AVAudioUnitReverbPreset.allCases, id: \.self) {
            Text($0.name)
          }
        }.pickerStyle(.menu)
      }
      HStack {
        Text("Reverb wet/dry mix")
        Slider(value: reverbWetDryMixBinding, in: 0...100)
      }
      HStack {
        Text("Delay time")
        Slider(value: delayTimeBinding, in: 0...5)
      }
      Spacer()
      Picker("Key", selection: $key) {
        Text("C").tag(Key.C)
        Text("G").tag(Key.G)
        Text("D").tag(Key.D)
        Text("A").tag(Key.A)
        Text("E").tag(Key.E)
      }.pickerStyle(.segmented)
      Picker("Octave", selection: $octave) {
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
            ForEach(keyChords, id: \.self) { chord in
              Button(chord.romanNumeralNotation(in: key) ?? chord.description) {
                seq?.sendTonicChord(chord: chord, octave: octave)
                seq?.play()
              }
              .frame(maxWidth: .infinity)
              //.font(.largeTitle)
              .buttonStyle(.borderedProminent)
            }
          }
        )
      }
      .navigationTitle("Scape")
      Button("Play beat.aiff") {
        presets[0].playerNode?.play()
      }
      Button("Stop") {
        seq?.stop()
        seq?.rewind()
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
          seq?.playURL(url: urls[0])
        case .failure(let error):
          print("\(error.localizedDescription)")
        }
      }
    }
    
  }
}

#Preview {
  TheoryView()
}
