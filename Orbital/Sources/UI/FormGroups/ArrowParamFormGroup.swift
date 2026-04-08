//
//  ArrowParamFormGroup.swift
//  Orbital
//

import SwiftUI

struct ArrowParamFormGroup: View {
  let title: String
  let descriptors: [ArrowParamDescriptor]
  let handler: ArrowHandler
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      ForEach(descriptors) { desc in
        ArrowParamRow(descriptor: desc, handler: handler)
      }
    } label: {
      summary()
    }
  }

  private func summary() -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.headline)
      Text(summaryText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }

  private var summaryText: String {
    descriptors.prefix(3).map { desc in
      switch desc.kind {
      case .oscShape:
        let shape = handler.shapeValues[desc.id] ?? .sine
        return "\(desc.displayName): \(shape)"
      default:
        let val = handler.floatValues[desc.id] ?? desc.defaultValue
        return "\(desc.displayName): \(SliderWithField.formatAdaptive(val))"
      }
    }
    .joined(separator: "  ")
  }
}

/// A single row in the dynamic arrow parameter form. Renders a Picker for osc
/// shapes and a SliderWithField for everything else.
struct ArrowParamRow: View {
  let descriptor: ArrowParamDescriptor
  let handler: ArrowHandler

  var body: some View {
    switch descriptor.kind {
    case .oscShape:
      Picker(descriptor.displayName, selection: handler.shapeBinding(for: descriptor.id)) {
        ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
          Text(String(describing: option))
        }
      }
    default:
      SliderWithField(
        value: handler.floatBinding(for: descriptor.id),
        label: descriptor.displayName,
        range: descriptor.suggestedRange,
        step: descriptor.stepSize
      )
    }
  }
}
