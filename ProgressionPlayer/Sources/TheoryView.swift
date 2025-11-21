//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import AudioKitUI
import AVFAudio
import Controls
import SwiftUI
import Tonic

@Observable
class KnobbySynth {
  let engine = SpatialAudioEngine()
  
  let numVoices = 8
  
  // one oscillator and filtered oscillator is shared among all voices
  var oscillator: BasicOscillator? = nil
  var filteredOsc: LowPassFilter? = nil
  var ampEnv: ADSR? = nil
  var filterEnv: ADSR? = nil
  
  var roseAmount: ArrowConstF = ArrowConstF(1)
  var roseAmplitude: ArrowConstF = ArrowConstF(5)
  var roseFrequency: ArrowConstF = ArrowConstF(2)
  
  var voices: [SimpleVoice] = []
  var presets: [Preset] = []
  
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
  
  var seq: Sequencer? = nil
  
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
    oscillator = BasicOscillator(shape: .sawtooth)
    filteredOsc = LowPassFilter(of: oscillator!, cutoff: 1000, resonance: 0)
    ampEnv = ADSR(envelope: EnvelopeData(
      attackTime: 0.3,
      decayTime: 0,
      sustainLevel: 1.0,
      releaseTime: 0.2
    ))
    filterEnv = ADSR(envelope: EnvelopeData(
      attackTime: 0.3,
      decayTime: 0,
      sustainLevel: 1,
      releaseTime: 0.2,
      scale: 1000
    ))
    for _ in 0..<numVoices {
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
        ampMod: ampEnv!,
        filterMod: filterEnv!
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
    } catch {
      print("Scape engine not starting: \(error.localizedDescription)")
    }
    
    // the sequencer will pluck on the arrows
    self.seq = Sequencer(engine: engine.audioEngine, numTracks: 2,  sourceNode: voicePool!)
    self.reverbMix = 50
  }
}

struct TheoryView: View {
  @State private var synth: KnobbySynth
  @State private var error: Error?
  @State private var isImporting = false
  @State private var fxExpanded = true
  @State private var ampADSRExpanded = true
  @State private var roseParamsExpanded = true
  @State private var synthExpanded = true

  init(synth: KnobbySynth) {
    self.synth = synth
  }
  
  var body: some View {
    NavigationStack {
      Form {
        Section(isExpanded: $synthExpanded) {
          Section {
            Picker("Instrument", selection: Binding($synth.oscillator)!.shape) {
              ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
                Text(String(describing: option))
              }
            }
            .pickerStyle(.segmented)
          }
          Section(isExpanded: $fxExpanded) {
            ReverbPresetStepper(preset: $synth.reverbPreset)
              .frame(maxHeight: 60)
            HStack {
              Spacer()
              VStack {
                Text("Reverb (%)").font(.headline)
                KnobbyKnob(value: $synth.reverbMix,
                           range: 0...100,
                           size: 80,
                           stepSize: 1,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.0f", $0)})
              }
              VStack {
                Text("Delay (s)").font(.headline)
                KnobbyKnob(value: $synth.delayTime,
                           range: 0...10,
                           size: 80,
                           stepSize: 0.1,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.1f", $0)})
              }
              VStack {
                Text("Filter (Hz)").font(.headline)
                KnobbyKnob(value: Binding($synth.filterEnv)!.env.scale,
                           range: 20...10000,
                           size: 80,
                           stepSize: 1,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.1f", $0)})
              }
              Spacer()
            }
            
          } header: {
            Button("FX") {
              fxExpanded.toggle()
            }
          }
          Section(isExpanded: $ampADSRExpanded) {
            HStack {
              Spacer()
              VStack {
                Text("Attack (s)").font(.headline)
                KnobbyKnob(value: Binding($synth.ampEnv)!.env.attackTime,
                           range: 0...2,
                           size: 80,
                           stepSize: 0.05,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.2f", $0)})
              }
              VStack {
                Text("Decay (s)").font(.headline)
                KnobbyKnob(value: Binding($synth.ampEnv)!.env.decayTime,
                           range: 0...2,
                           size: 80,
                           stepSize: 0.05,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.2f", $0)})
              }
              VStack {
                Text("Sus").font(.headline)
                KnobbyKnob(value: Binding($synth.ampEnv)!.env.sustainLevel,
                           range: 0...1,
                           size: 80,
                           stepSize: 0.01,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.2f", $0)})
              }
              VStack {
                Text("Rel (s)").font(.headline)
                KnobbyKnob(value: Binding($synth.ampEnv)!.env.releaseTime,
                           range: 0...2,
                           size: 80,
                           stepSize: 0.05,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.2f", $0)})
              }
              Spacer()
            }
          } header: {
            Button("Amp Envelope") {
              ampADSRExpanded.toggle()
            }
          }
          Section(isExpanded: $roseParamsExpanded) {
            HStack {
              Spacer()
              VStack {
                Text("⌘ Loops").font(.headline)
                KnobbyKnob(value: $synth.roseAmount.val,
                           range: 0...10,
                           size: 80,
                           stepSize: 1,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.0f", $0)})
              }
              VStack {
                Text("⌘ Speed").font(.headline)
                KnobbyKnob(value: $synth.roseFrequency.val,
                           range: 0...10,
                           size: 80,
                           stepSize: 0.1,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.1f", $0)})
              }
              VStack {
                Text("⌘ Distance").font(.headline)
                KnobbyKnob(value: $synth.roseAmplitude.val,
                           range: 0...10,
                           size: 80,
                           stepSize: 0.1,
                           allowPoweroff: false,
                           ifShowValue: true,
                           valueFormatter: { String(format: "%.1f", $0)})
              }
              Spacer()
            }
          } header: {
            Button("Trajectory") {
              roseParamsExpanded.toggle()
            }
          }
        } header: {
          Button("Synth") {
            synthExpanded.toggle()
          }
        }
        Section {
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
          Button("Stop") {
            synth.seq?.stop()
            synth.seq?.rewind()
          }
          .font(.largeTitle)
          .buttonStyle(.borderedProminent)
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
        .navigationTitle("⌘Scape")
      }
    }
  }
}

#Preview {
  TheoryView(synth: KnobbySynth())
}
