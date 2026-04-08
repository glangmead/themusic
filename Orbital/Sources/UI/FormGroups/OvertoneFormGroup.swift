//
//  OvertoneFormGroup.swift
//  Orbital
//

import SwiftUI

struct OvertoneFormGroup: View {
  @Bindable var synth: SyntacticSynth
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      SliderWithField(
        value: $synth.padSynthStretch,
        label: "Stretch",
        range: 0.9...1.5,
        step: 0.01
      )
    } label: {
      summary()
    }
  }

  private func summary() -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Overtones")
        .font(.headline)
      Text("Stretch: \(synth.padSynthStretch, format: .number.precision(.fractionLength(2)))")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }
}
