//
//  InstrumentFormGroup.swift
//  Orbital
//

import SwiftUI

struct InstrumentFormGroup: View {
  @Bindable var synth: SyntacticSynth
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Picker("Timbre source", selection: $synth.padSynthSelectedInstrument) {
        Text("Custom").tag(String?.none)
        ForEach(SharcDatabase.shared.instruments) { inst in
          Text(inst.displayName).tag(Optional(inst.id))
        }
      }
    } label: {
      summary()
    }
  }

  private func summary() -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Instrument")
        .font(.headline)
      Text(instrumentName)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }

  private var instrumentName: String {
    guard let id = synth.padSynthSelectedInstrument else { return "Custom" }
    return SharcDatabase.shared.instruments.first { $0.id == id }?.displayName ?? id
  }
}
