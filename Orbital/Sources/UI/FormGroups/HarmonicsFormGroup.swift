//
//  HarmonicsFormGroup.swift
//  Orbital
//

import SwiftUI

struct HarmonicsFormGroup: View {
  @Bindable var synth: SyntacticSynth
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      if synth.padSynthSelectedInstrument == nil {
        Picker("Base shape", selection: $synth.padSynthBaseShape) {
          ForEach(PADBaseShape.allCases) { shape in
            Text(shape.rawValue).tag(shape)
          }
        }
      }
      SliderWithField(
        value: $synth.padSynthTilt,
        label: "Tilt",
        range: -2.0...2.0,
        step: 0.1
      )
    } label: {
      summary()
    }
  }

  private func summary() -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Harmonics")
        .font(.headline)
      if synth.padSynthSelectedInstrument != nil {
        Text("Tilt: \(synth.padSynthTilt, format: .number.precision(.fractionLength(1)))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text("\(synth.padSynthBaseShape.rawValue) Tilt: \(synth.padSynthTilt, format: .number.precision(.fractionLength(1)))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
