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
  var oscillator: BasicOscillator? = nil
  var filteredOsc: LowPassFilter? = nil
  var roseAmount: ArrowConstF = ArrowConstF(3)
  var roseAmplitude: ArrowConstF = ArrowConstF(2)
  var roseFrequency: ArrowConstF = ArrowConstF(0.5)
  var voices: [SimpleVoice] = []
  var presets: [Preset] = []
  var reverbMix: Float = 0 {
    didSet {
      for preset in self.presets { preset.setReverbWetDryMix(Double(reverbMix))
      }
    }
  }
  var reverbPreset: AVAudioUnitReverbPreset = .largeRoom {
    didSet {
      for preset in self.presets {
        preset.reverbPreset = reverbPreset
      }
    }
  }
  var delayTime: Float = 0 {
    didSet {
      for preset in self.presets {
        preset.setDelayTime(Double(delayTime))
      }
    }
  }
  
  var voiceMixerNodes: [AVAudioMixerNode] = []
  var voicePool: NoteHandler? = nil
  
  var seq: Sequencer? = nil
  
  // Bindings: for values we update by changing them from this class
  var spatialPositionBinding: Binding<(Double, Double, Double)>? = nil
  var delayFeedbackBinding: Binding<Double>? = nil
  var delayLowPassCutoffBinding: Binding<Double>? = nil
  var delayWetDryMixBinding: Binding<Double>? = nil
  var distortionPreGainBinding: Binding<Double>? = nil
  var distortionWetDryMixBinding: Binding<Double>? = nil
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
    oscillator = BasicOscillator(shape: .sawtooth)
    filteredOsc = LowPassFilter(of: oscillator!, cutoff: 100000, resonance: 0)
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
        amplitude: roseAmplitude,
        leafFactor: roseAmount,
        frequency: roseFrequency,
        startingPhase: CoreFloat.random(in: 0.0...(2 * .pi))
      )
      presets.append(preset)
      voiceMixerNodes.append(preset.buildChainAndGiveOutputNode(forEngine: self.engine))
    }
    engine.connectToEnvNode(voiceMixerNodes)

    voicePool = PoolVoice(voices: voices)
        
    spatialPositionBinding = Binding<(Double, Double, Double)>(
      get: { self.presets[0].getSpatialPosition() },
      set: { for preset in self.presets { preset.setSpatialPosition($0) } }
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
    distortionPresetBinding = Binding<AVAudioUnitDistortionPreset>(
      get: { self.presets[0].getDistortionPreset() },
      set: { for preset in self.presets { preset.setDistortionPreset($0) } }
    )
    filterCutoffBinding = Binding<Double>(
      get: { return 0 },
      set: { _ in () }
    )
    
    do {
      try engine.start()
    } catch {
      print("engine failed")
    }
    
    // the sequencer will pluck on the arrows
    self.seq = Sequencer(engine: engine.audioEngine, numTracks: 2,  sourceNode: voicePool!)
    
  }
}

struct TheoryView: View {
  @State private var synth: KnobbySynth
  @State private var error: Error?
  @State private var isImporting = false
  @State private var dummy: Float = 0

  init(synth: KnobbySynth) {
    self.synth = synth
  }
  
  var body: some View {
    NavigationStack {
      Picker("Instrument", selection: Binding($synth.oscillator)!.shape) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
      .pickerStyle(.segmented)
      
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
        Spacer()
      }
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
      Spacer()
      ScrollView {
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
        .navigationTitle("⌘Scape")
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
        Spacer()
      }
    }
  }
}

#Preview {
  TheoryView(synth: KnobbySynth())
}
