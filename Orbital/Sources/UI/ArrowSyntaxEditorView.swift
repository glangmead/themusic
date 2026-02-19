//
//  ArrowSyntaxEditorView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

/// Recursively renders editable controls for every node in an ArrowSyntax tree.
struct ArrowSyntaxEditorView: View {
  let syntax: ArrowSyntax
  let handler: ArrowHandler

  var body: some View {
    switch syntax {
    case .const(let name, _):
      ConstEditorRow(name: name, handler: handler)

    case .constOctave(let name, _):
      ConstEditorRow(name: name, handler: handler, label: "\(name) (octave)")

    case .constCent(let name, _):
      ConstEditorRow(name: name, handler: handler, label: "\(name) (cent)")

    case .envelope(let name, _, _, _, _, _):
      DisclosureGroup(name) {
        EnvelopeEditorRow(name: name, handler: handler)
      }

    case .osc(let name, _, let width):
      DisclosureGroup(name) {
        OscEditorRow(name: name, handler: handler)
        ArrowSyntaxEditorView(syntax: width, handler: handler)
      }

    case .choruser(let name, _, _, _):
      ChoruserEditorRow(name: name, handler: handler)

    case .lowPassFilter(let name, let cutoff, let resonance):
      DisclosureGroup(name) {
        ArrowSyntaxEditorView(syntax: cutoff, handler: handler)
        ArrowSyntaxEditorView(syntax: resonance, handler: handler)
      }

    case .compose(let arrows):
      ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
        ArrowSyntaxEditorView(syntax: child, handler: handler)
      }

    case .prod(let arrows):
      ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
        ArrowSyntaxEditorView(syntax: child, handler: handler)
      }

    case .sum(let arrows):
      ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
        ArrowSyntaxEditorView(syntax: child, handler: handler)
      }

    case .crossfade(let arrows, let name, let mixPoint):
      DisclosureGroup("Crossfade: \(name)") {
        ArrowSyntaxEditorView(syntax: mixPoint, handler: handler)
        ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
          ArrowSyntaxEditorView(syntax: child, handler: handler)
        }
      }

    case .crossfadeEqPow(let arrows, let name, let mixPoint):
      DisclosureGroup("EqPow Crossfade: \(name)") {
        ArrowSyntaxEditorView(syntax: mixPoint, handler: handler)
        ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
          ArrowSyntaxEditorView(syntax: child, handler: handler)
        }
      }

    case .noiseSmoothStep(let noiseFreq, let min, let max):
      VStack(alignment: .leading) {
        Text("NoiseSmoothStep")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("freq: \(noiseFreq, specifier: "%.2f"), range: \(min, specifier: "%.2f")–\(max, specifier: "%.2f")")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

    case .rand(let min, let max):
      Text("Random: \(min, specifier: "%.2f")–\(max, specifier: "%.2f")")
        .font(.caption)
        .foregroundStyle(.secondary)

    case .exponentialRand(let min, let max):
      Text("ExpRandom: \(min, specifier: "%.2f")–\(max, specifier: "%.2f")")
        .font(.caption)
        .foregroundStyle(.secondary)

    case .line(let duration, let min, let max):
      Text("Line: \(min, specifier: "%.2f")→\(max, specifier: "%.2f") over \(duration, specifier: "%.2f")s")
        .font(.caption)
        .foregroundStyle(.secondary)

    case .identity:
      EmptyView()

    case .control:
      EmptyView()

    case .reciprocalConst(let name, _):
      ConstEditorRow(name: name, handler: handler, label: "\(name) (reciprocal)")

    case .reciprocal(of: let inner):
      DisclosureGroup("1/x") {
        ArrowSyntaxEditorView(syntax: inner, handler: handler)
      }

    case .eventNote:
      Text("Event Note")
        .font(.caption)
        .foregroundStyle(.secondary)

    case .eventVelocity:
      Text("Event Velocity")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Const Editor

/// Edits a named constant via the ArrowHandler.
private struct ConstEditorRow: View {
  let name: String
  let handler: ArrowHandler
  var label: String? = nil

  var body: some View {
    if let desc = handler.descriptorMap(for: name) {
      LabeledSlider(
        value: handler.floatBinding(for: name),
        label: label ?? desc.displayName,
        range: desc.suggestedRange,
        step: desc.stepSize
      )
      .font(.caption)
    }
  }
}

// MARK: - Envelope Editor

private struct EnvelopeEditorRow: View {
  let name: String
  let handler: ArrowHandler

  var body: some View {
    LabeledSlider(value: handler.floatBinding(for: "\(name).attack"), label: "Attack", range: 0...5)
    LabeledSlider(value: handler.floatBinding(for: "\(name).decay"), label: "Decay", range: 0...5)
    LabeledSlider(value: handler.floatBinding(for: "\(name).sustain"), label: "Sustain", range: 0...1)
    LabeledSlider(value: handler.floatBinding(for: "\(name).release"), label: "Release", range: 0...5)
  }
}

// MARK: - Osc Editor

private struct OscEditorRow: View {
  let name: String
  let handler: ArrowHandler

  var body: some View {
    Picker("Shape", selection: handler.shapeBinding(for: "\(name).shape")) {
      ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
        Text(String(describing: option))
      }
    }
  }
}

// MARK: - Choruser Editor

private struct ChoruserEditorRow: View {
  let name: String
  let handler: ArrowHandler

  var body: some View {
    LabeledSlider(value: handler.floatBinding(for: "\(name).centRadius"), label: "\(name) Cents", range: 0...30, step: 1)
    LabeledSlider(value: handler.floatBinding(for: "\(name).numVoices"), label: "\(name) Voices", range: 1...12, step: 1)
  }
}

#Preview {
  let presetSpec = Bundle.main.decode(
    PresetSyntax.self,
    from: "auroraBorealis.json",
    subdirectory: "presets"
  )
  let handler = ArrowHandler(syntax: presetSpec.arrow!)
  Form {
    ArrowSyntaxEditorView(syntax: presetSpec.arrow!, handler: handler)
  }
}
