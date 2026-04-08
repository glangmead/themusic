//
//  SliderWithField.swift
//  Orbital
//

import SwiftUI

/// A slider paired with an editable text field. Adapts decimal precision
/// to show meaningful digits even for very small values (e.g. 0.00002).
struct SliderWithField: View {
  @Binding var value: CoreFloat
  let label: String
  let range: ClosedRange<CoreFloat>
  var step: CoreFloat?
  var logarithmic: Bool = false

  @State private var textValue = ""
  @FocusState private var isEditing: Bool

  /// Internal slider position: linear in [0,1] when logarithmic, else the value itself.
  private var sliderBinding: Binding<CoreFloat> {
    if logarithmic {
      let lo = log(max(range.lowerBound, 1e-10))
      let hi = log(max(range.upperBound, 1e-10))
      return Binding(
        get: { (log(max(value, 1e-10)) - lo) / (hi - lo) },
        set: { value = exp(lo + $0 * (hi - lo)).clamped(to: range) }
      )
    } else {
      return $value
    }
  }

  private var sliderRange: ClosedRange<CoreFloat> {
    logarithmic ? 0...1 : range
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label)
        Spacer()
        TextField("", text: $textValue)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .frame(width: 100)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .focused($isEditing)
          .onSubmit { applyText() }
          .onChange(of: isEditing) { _, focused in
            if !focused { applyText() }
          }
      }
      if let step, !logarithmic {
        Slider(value: sliderBinding, in: sliderRange, step: step)
          .onChange(of: value) { _, newValue in
            if !isEditing { textValue = Self.formatAdaptive(newValue) }
          }
      } else {
        Slider(value: sliderBinding, in: sliderRange)
          .onChange(of: value) { _, newValue in
            if !isEditing { textValue = Self.formatAdaptive(newValue) }
          }
      }
    }
    .onAppear { textValue = Self.formatAdaptive(value) }
  }

  private func applyText() {
    if let parsed = Double(textValue) {
      value = parsed.clamped(to: range)
    }
    textValue = Self.formatAdaptive(value)
  }

  /// Formats a number with enough decimal places to show significant digits.
  /// For values >= 0.01, uses 3 decimal places. For smaller values, shows
  /// enough places to reveal at least 2 significant digits.
  static func formatAdaptive(_ v: CoreFloat) -> String {
    if v == 0 { return "0" }
    let absV = abs(v)
    if absV >= 0.01 {
      return String(format: "%.3f", v)
    }
    // For very small numbers, compute how many decimals we need
    let digits = max(3, Int(ceil(-log10(absV))) + 2)
    return String(format: "%.\(digits)f", v)
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
