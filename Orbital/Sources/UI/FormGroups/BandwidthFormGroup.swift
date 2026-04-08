//
//  BandwidthFormGroup.swift
//  Orbital
//

import SwiftUI

struct BandwidthFormGroup: View {
  @Bindable var synth: SyntacticSynth
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      SliderWithField(
        value: $synth.padSynthBandwidthCents,
        label: "Bandwidth (cents)",
        range: 1...200,
        step: 1
      )
      SliderWithField(
        value: $synth.padSynthBwScale,
        label: "BW scale",
        range: 0.5...2.0,
        step: 0.05
      )
      Picker("Profile", selection: $synth.padSynthProfileShape) {
        ForEach(PADProfileShape.allCases) { profile in
          Text(profile.rawValue).tag(profile)
        }
      }
    } label: {
      summary()
    }
  }

  private func summary() -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Bandwidth")
        .font(.headline)
      Text("\(Int(synth.padSynthBandwidthCents))\u{00A2} \u{00D7} \(synth.padSynthBwScale, format: .number.precision(.fractionLength(2))) \(synth.padSynthProfileShape.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }
}
