//
//  ArrowSyntaxEditorView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

/// Recursively renders editable controls for every node in an ArrowSyntax tree.
struct ArrowSyntaxEditorView: View {
    let syntax: ArrowSyntax
    let synth: SyntacticSynth

    var body: some View {
        switch syntax {
        case .const(let name, let val):
            ConstEditorRow(name: name, defaultValue: val, synth: synth)

        case .constOctave(let name, let val):
            ConstEditorRow(name: name, defaultValue: val, synth: synth, label: "\(name) (octave)")

        case .constCent(let name, let val):
            ConstEditorRow(name: name, defaultValue: val, synth: synth, label: "\(name) (cent)")

        case .envelope(let name, let attack, let decay, let sustain, let release, let scale):
            DisclosureGroup(name) {
                EnvelopeEditorRow(name: name, attack: attack, decay: decay, sustain: sustain, release: release, scale: scale, synth: synth)
            }

        case .osc(let name, _, let width):
            DisclosureGroup(name) {
                OscEditorRow(name: name, synth: synth)
                ArrowSyntaxEditorView(syntax: width, synth: synth)
            }

        case .choruser(let name, _, let centRadius, let numVoices):
            ChoruserEditorRow(name: name, centRadius: centRadius, numVoices: numVoices, synth: synth)

        case .lowPassFilter(let name, let cutoff, let resonance):
            DisclosureGroup(name) {
                ArrowSyntaxEditorView(syntax: cutoff, synth: synth)
                ArrowSyntaxEditorView(syntax: resonance, synth: synth)
            }

        case .compose(let arrows):
            ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
                ArrowSyntaxEditorView(syntax: child, synth: synth)
            }

        case .prod(let arrows):
            ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
                ArrowSyntaxEditorView(syntax: child, synth: synth)
            }

        case .sum(let arrows):
            ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
                ArrowSyntaxEditorView(syntax: child, synth: synth)
            }

        case .crossfade(let arrows, let name, let mixPoint):
            DisclosureGroup("Crossfade: \(name)") {
                ArrowSyntaxEditorView(syntax: mixPoint, synth: synth)
                ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
                    ArrowSyntaxEditorView(syntax: child, synth: synth)
                }
            }

        case .crossfadeEqPow(let arrows, let name, let mixPoint):
            DisclosureGroup("EqPow Crossfade: \(name)") {
                ArrowSyntaxEditorView(syntax: mixPoint, synth: synth)
                ForEach(Array(arrows.enumerated()), id: \.offset) { _, child in
                    ArrowSyntaxEditorView(syntax: child, synth: synth)
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
        }
    }
}

// MARK: - Const Editor

/// Edits a named constant by writing directly to the synth's handles.
private struct ConstEditorRow: View {
    let name: String
    let defaultValue: CoreFloat
    let synth: SyntacticSynth
    var label: String? = nil

    @State private var value: CoreFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label ?? name)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.3f", value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: sliderRange)
                .onChange(of: value) {
                    synth.spatialPreset?.handles?.namedConsts[name]?.forEach { $0.val = value }
                }
        }
        .onAppear {
            value = synth.spatialPreset?.handles?.namedConsts[name]?.first?.val ?? defaultValue
        }
    }

    private var sliderRange: ClosedRange<CoreFloat> {
        // Provide a reasonable range based on the default value
        let magnitude = abs(defaultValue)
        if magnitude < 0.01 { return -1...1 }
        if magnitude < 1 { return 0...2 }
        if magnitude < 10 { return 0...(magnitude * 4) }
        return 0...(magnitude * 2)
    }
}

// MARK: - Envelope Editor

private struct EnvelopeEditorRow: View {
    let name: String
    let attack: CoreFloat
    let decay: CoreFloat
    let sustain: CoreFloat
    let release: CoreFloat
    let scale: CoreFloat
    let synth: SyntacticSynth

    @State private var a: CoreFloat = 0
    @State private var d: CoreFloat = 0
    @State private var s: CoreFloat = 0
    @State private var r: CoreFloat = 0

    var body: some View {
        LabeledSlider(value: $a, label: "Attack", range: 0...5)
            .onChange(of: a) {
                synth.spatialPreset?.handles?.namedADSREnvelopes[name]?.forEach { $0.env.attackTime = a }
            }
        LabeledSlider(value: $d, label: "Decay", range: 0...5)
            .onChange(of: d) {
                synth.spatialPreset?.handles?.namedADSREnvelopes[name]?.forEach { $0.env.decayTime = d }
            }
        LabeledSlider(value: $s, label: "Sustain", range: 0...1)
            .onChange(of: s) {
                synth.spatialPreset?.handles?.namedADSREnvelopes[name]?.forEach { $0.env.sustainLevel = s }
            }
        LabeledSlider(value: $r, label: "Release", range: 0...5)
            .onChange(of: r) {
                synth.spatialPreset?.handles?.namedADSREnvelopes[name]?.forEach { $0.env.releaseTime = r }
            }
    }
}

// MARK: - Osc Editor

private struct OscEditorRow: View {
    let name: String
    let synth: SyntacticSynth

    @State private var shape: BasicOscillator.OscShape = .sine

    var body: some View {
        Picker("Shape", selection: $shape) {
            ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
                Text(String(describing: option))
            }
        }
        .onChange(of: shape) {
            synth.spatialPreset?.handles?.namedBasicOscs[name]?.forEach { $0.shape = shape }
        }
        .onAppear {
            shape = synth.spatialPreset?.handles?.namedBasicOscs[name]?.first?.shape ?? .sine
        }
    }
}

// MARK: - Choruser Editor

private struct ChoruserEditorRow: View {
    let name: String
    let centRadius: Int
    let numVoices: Int
    let synth: SyntacticSynth

    @State private var cents: CoreFloat = 0
    @State private var voices: CoreFloat = 1

    var body: some View {
        LabeledSlider(value: $cents, label: "\(name) Cents", range: 0...30, step: 1)
            .onChange(of: cents) {
                synth.spatialPreset?.handles?.namedChorusers[name]?.forEach { $0.chorusCentRadius = Int(cents) }
            }
        LabeledSlider(value: $voices, label: "\(name) Voices", range: 1...12, step: 1)
            .onChange(of: voices) {
                synth.spatialPreset?.handles?.namedChorusers[name]?.forEach { $0.chorusNumVoices = Int(voices) }
            }
            .onAppear {
                cents = CoreFloat(synth.spatialPreset?.handles?.namedChorusers[name]?.first?.chorusCentRadius ?? centRadius)
                voices = CoreFloat(synth.spatialPreset?.handles?.namedChorusers[name]?.first?.chorusNumVoices ?? numVoices)
            }
    }
}
