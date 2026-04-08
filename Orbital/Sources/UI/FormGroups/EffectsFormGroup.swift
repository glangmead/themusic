//
//  EffectsFormGroup.swift
//  Orbital
//

import AVFAudio
import SwiftUI

struct EffectsFormGroup: View {
  @Bindable var synth: SyntacticSynth
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Picker("Reverb Preset", selection: $synth.reverbPreset) {
        ForEach(AVAudioUnitReverbPreset.allCases, id: \.self) { option in
          Text(option.name)
        }
      }
      SliderWithField(value: $synth.reverbMix, label: "Reverb Wet/Dry", range: 0...100)
      if synth.delayAvailable {
        SliderWithField(value: $synth.delayTime, label: "Delay Time", range: 0...30)
        SliderWithField(value: $synth.delayFeedback, label: "Delay Feedback", range: 0...30)
        SliderWithField(value: $synth.delayWetDryMix, label: "Delay Wet/Dry", range: 0...100)
        SliderWithField(value: $synth.delayLowPassCutoff, label: "Delay LowPass", range: 0...1000)
      }
    } label: {
      summary()
    }
  }

  private func summary() -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Effects")
        .font(.headline)
      if synth.delayAvailable {
        Text("\(synth.reverbPreset.name) \(Int(synth.reverbMix))% | Delay \(Int(synth.delayTime))/\(Int(synth.delayFeedback))/\(Int(synth.delayWetDryMix))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text("\(synth.reverbPreset.name) \(Int(synth.reverbMix))%")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
