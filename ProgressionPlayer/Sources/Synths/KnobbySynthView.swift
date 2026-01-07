//
//  KnobbySynthView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/28/25.
//

import AudioKitUI
import SwiftUI
import Tonic

struct KnobbySynthView: View {
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
                         valueString: { String(format: "%.0f", $0)})
            }
            VStack {
              Text("Delay (s)").font(.headline)
              KnobbyKnob(value: $synth.delayTime,
                         range: 0...10,
                         size: 80,
                         stepSize: 0.1,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.1f", $0)})
            }
            VStack {
              Text("Filter (Hz)").font(.headline)
              KnobbyKnob(value: $synth.filterScale,
                         range: 20...10000,
                         size: 80,
                         stepSize: 1,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.1f", $0)})
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
              KnobbyKnob(value: $synth.ampAttack,
                         range: 0...2,
                         size: 80,
                         stepSize: 0.05,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.2f", $0)})
            }
            VStack {
              Text("Decay (s)").font(.headline)
              KnobbyKnob(value: $synth.ampDecay,
                         range: 0...2,
                         size: 80,
                         stepSize: 0.05,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.2f", $0)})
            }
            VStack {
              Text("Sus").font(.headline)
              KnobbyKnob(value: $synth.ampSustain,
                         range: 0...1,
                         size: 80,
                         stepSize: 0.01,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.2f", $0)})
            }
            VStack {
              Text("Rel (s)").font(.headline)
              KnobbyKnob(value: $synth.ampRelease,
                         range: 0...2,
                         size: 80,
                         stepSize: 0.05,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.2f", $0)})
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
                         valueString: { String(format: "%.0f", $0)})
            }
            VStack {
              Text("⌘ Speed").font(.headline)
              KnobbyKnob(value: $synth.roseFrequency.val,
                         range: 0...10,
                         size: 80,
                         stepSize: 0.1,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.1f", $0)})
            }
            VStack {
              Text("⌘ Distance").font(.headline)
              KnobbyKnob(value: $synth.roseAmplitude.val,
                         range: 0...10,
                         size: 80,
                         stepSize: 0.1,
                         allowPoweroff: false,
                         ifShowValue: true,
                         valueString: { String(format: "%.1f", $0)})
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
    }
  }
}

#Preview {
  KnobbySynthView(synth: KnobbySynth())
}
