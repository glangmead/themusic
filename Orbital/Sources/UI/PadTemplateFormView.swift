//
//  PadTemplateFormView.swift
//  Orbital
//

import AVFAudio
import Keyboard
import MIDIKitIO
import SwiftUI
import Tonic

// MARK: - OscChoice

/// One entry in the oscillator picker: either a standard waveform shape or a named wavetable file.
enum OscChoice: Equatable {
  case standard(BasicOscillator.OscShape)
  case wavetable(String)  // curated_wavetables filename without extension

  var displayName: String {
    switch self {
    case .standard(let s):
      switch s {
      case .sine:     return "Sine"
      case .triangle: return "Triangle"
      case .sawtooth: return "Sawtooth"
      case .square:   return "Square"
      case .noise:    return "Noise"
      }
    case .wavetable(let name):
      return name
    }
  }
}

// MARK: - PadTemplateFormView (outer)

struct PadTemplateFormView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @State private var synth: SyntacticSynth?
  @State private var mood: PadMood = .cosmic
  @State private var sliders: PadSliders = .cosmicDefaults
  @State private var oscChoices: [OscChoice] = []

  var body: some View {
    NavigationStack {
      if let synth {
        PadTemplateFormContent(synth: synth, mood: $mood, sliders: $sliders, oscChoices: oscChoices)
      } else {
        ProgressView()
          .onAppear {
            let choices = Self.loadCuratedChoices()
            oscChoices = choices
            let preset = Self.buildPreset(mood: mood, sliders: sliders, oscChoices: choices)
            synth = SyntacticSynth(engine: engine, presetSpec: preset)
          }
      }
    }
  }

  // MARK: - Oscillator choice list

  /// Standard shapes (no noise) followed by sorted curated wavetable names from WavetableLibrary.
  static func loadCuratedChoices() -> [OscChoice] {
    let standard: [OscChoice] = [
      .standard(.sine), .standard(.triangle), .standard(.sawtooth), .standard(.square)
    ]
    let synthesized = WavetableLibrary.tables.keys.sorted().map { OscChoice.wavetable($0) }
    let curated = WavetableLibrary.curatedTableNames.map { OscChoice.wavetable($0) }
    return standard + synthesized + curated
  }

  // MARK: - Mood-specific template construction

  // Each mood uses different oscillator shapes and structural settings so the character
  // is immediately audible. Abstract sliders (smooth/bite/motion/width/grit) then refine
  // within that character — filter differences are far more perceptible on sawtooth/square
  // than on sine/triangle which have weak or no upper harmonics.
  // The osc1Index/osc2Index in sliders select the waveform; mood governs all other structure.
  // swiftlint:disable:next function_body_length
  static func buildTemplate(mood: PadMood, sliders: PadSliders, oscChoices: [OscChoice]) -> PadTemplateSyntax {
    switch mood {
    case .cosmic:
      // Smooth, evolving: osc2 one octave up
      return PadTemplateSyntax(
        name: "Pad Design",
        oscillators: [
          oscDescriptor(index: sliders.osc1Index, detuneCents: -7, octave: 0, choices: oscChoices),
          oscDescriptor(index: sliders.osc2Index, detuneCents: 7, octave: 1, choices: oscChoices)
        ],
        crossfade: .noiseSmoothStep, crossfadeRate: nil,
        vibratoEnabled: true, vibratoRate: nil, vibratoDepth: 0.0005,
        ampAttack: nil, ampDecay: 0.1, ampSustain: 1.0, ampRelease: nil,
        filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
        filterEnvAttack: 0.1, filterEnvDecay: 0.5, filterEnvSustain: 0.8, filterEnvRelease: 0.5,
        filterCutoffLow: 60, mood: mood, sliders: sliders
      )
    case .dark:
      // Harmonically rich, filter clearly audible; osc2 one octave down
      return PadTemplateSyntax(
        name: "Pad Design",
        oscillators: [
          oscDescriptor(index: sliders.osc1Index, detuneCents: -5, octave: 0, choices: oscChoices),
          oscDescriptor(index: sliders.osc2Index, detuneCents: 5, octave: -1, choices: oscChoices)
        ],
        crossfade: .lfo, crossfadeRate: nil,
        vibratoEnabled: false, vibratoRate: nil, vibratoDepth: 0.0003,
        ampAttack: nil, ampDecay: 0.1, ampSustain: 1.0, ampRelease: nil,
        filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
        filterEnvAttack: 0.05, filterEnvDecay: 0.4, filterEnvSustain: 0.7, filterEnvRelease: 0.4,
        filterCutoffLow: 80, mood: mood, sliders: sliders
      )
    case .warm:
      // Medium harmonics, slow filter LFO adds movement; both oscs at same octave
      return PadTemplateSyntax(
        name: "Pad Design",
        oscillators: [
          oscDescriptor(index: sliders.osc1Index, detuneCents: -3, octave: 0, choices: oscChoices),
          oscDescriptor(index: sliders.osc2Index, detuneCents: 3, octave: 0, choices: oscChoices)
        ],
        crossfade: .noiseSmoothStep, crossfadeRate: nil,
        vibratoEnabled: true, vibratoRate: nil, vibratoDepth: 0.0003,
        ampAttack: nil, ampDecay: 0.1, ampSustain: 1.0, ampRelease: nil,
        filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: 0,
        filterEnvAttack: 0.1, filterEnvDecay: 0.3, filterEnvSustain: 0.75, filterEnvRelease: 0.4,
        filterCutoffLow: 70, mood: mood, sliders: sliders
      )
    case .ethereal:
      // Transparent, spacious: osc2 one octave up, wide detune
      return PadTemplateSyntax(
        name: "Pad Design",
        oscillators: [
          oscDescriptor(index: sliders.osc1Index, detuneCents: -12, octave: 0, choices: oscChoices),
          oscDescriptor(index: sliders.osc2Index, detuneCents: 12, octave: 1, choices: oscChoices)
        ],
        crossfade: .noiseSmoothStep, crossfadeRate: nil,
        vibratoEnabled: true, vibratoRate: nil, vibratoDepth: 0.0007,
        ampAttack: nil, ampDecay: 0.05, ampSustain: 1.0, ampRelease: nil,
        filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
        filterEnvAttack: 0.2, filterEnvDecay: 0.8, filterEnvSustain: 0.9, filterEnvRelease: 0.8,
        filterCutoffLow: 50, mood: mood, sliders: sliders
      )
    case .gritty:
      // Aggressive, resonance very obvious; no vibrato
      return PadTemplateSyntax(
        name: "Pad Design",
        oscillators: [
          oscDescriptor(index: sliders.osc1Index, detuneCents: 0, octave: 0, choices: oscChoices),
          oscDescriptor(index: sliders.osc2Index, detuneCents: 0, octave: 0, choices: oscChoices)
        ],
        crossfade: .noiseSmoothStep, crossfadeRate: nil,
        vibratoEnabled: false, vibratoRate: nil, vibratoDepth: 0.0001,
        ampAttack: nil, ampDecay: 0.05, ampSustain: 1.0, ampRelease: nil,
        filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
        filterEnvAttack: 0.03, filterEnvDecay: 0.2, filterEnvSustain: 0.6, filterEnvRelease: 0.3,
        filterCutoffLow: 100, mood: mood, sliders: sliders
      )
    case .custom:
      // Neutral starting point: same structure as cosmic
      return PadTemplateSyntax(
        name: "Pad Design",
        oscillators: [
          oscDescriptor(index: sliders.osc1Index, detuneCents: -7, octave: 0, choices: oscChoices),
          oscDescriptor(index: sliders.osc2Index, detuneCents: 7, octave: 0, choices: oscChoices)
        ],
        crossfade: .noiseSmoothStep, crossfadeRate: nil,
        vibratoEnabled: true, vibratoRate: nil, vibratoDepth: 0.0005,
        ampAttack: nil, ampDecay: 0.1, ampSustain: 1.0, ampRelease: nil,
        filterCutoffMultiplier: nil, filterResonance: nil, filterLFORate: nil,
        filterEnvAttack: 0.1, filterEnvDecay: 0.5, filterEnvSustain: 0.8, filterEnvRelease: 0.5,
        filterCutoffLow: 60, mood: mood, sliders: sliders
      )
    }
  }

  static func buildPreset(mood: PadMood, sliders: PadSliders, oscChoices: [OscChoice]) -> PresetSyntax {
    let template = buildTemplate(mood: mood, sliders: sliders, oscChoices: oscChoices)
    return PresetSyntax(
      name: "Pad Design",
      arrow: nil,
      samplerFilenames: nil,
      samplerProgram: nil,
      samplerBank: nil,
      library: nil,
      rose: RoseSyntax(amp: 0, leafFactor: 3, freq: 0.2, phase: 0),
      effects: EffectsSyntax(
        reverbPreset: CoreFloat(AVAudioUnitReverbPreset.mediumRoom.rawValue),
        reverbWetDryMix: 30,
        delayTime: 0,
        delayFeedback: 0,
        delayLowPassCutoff: 0,
        delayWetDryMix: 0
      ),
      padTemplate: template
    )
  }

  // MARK: - Private helpers

  private static func oscDescriptor(index: Int, detuneCents: CoreFloat, octave: CoreFloat, choices: [OscChoice]) -> PadOscDescriptor {
    guard !choices.isEmpty else {
      return PadOscDescriptor(kind: .standard, shape: .sine, file: nil, detuneCents: detuneCents, octave: octave)
    }
    let clamped = min(max(0, index), choices.count - 1)
    switch choices[clamped] {
    case .standard(let shape):
      return PadOscDescriptor(kind: .standard, shape: shape, file: nil, detuneCents: detuneCents, octave: octave)
    case .wavetable(let filename):
      return PadOscDescriptor(kind: .wavetable, shape: nil, file: filename, detuneCents: detuneCents, octave: octave)
    }
  }
}

// MARK: - PadTemplateFormContent (inner)

private struct PadTemplateFormContent: View {
  @Bindable var synth: SyntacticSynth
  @Binding var mood: PadMood
  @Binding var sliders: PadSliders
  let oscChoices: [OscChoice]

  @State private var midiManager = ObservableMIDIManager(
    clientName: "Orbital",
    model: "Orbital",
    manufacturer: "Orbital"
  )

  private static let allMoods: [PadMood] = [.cosmic, .dark, .warm, .ethereal, .gritty, .custom]

  private func setupMIDI() {
    guard midiManager.managedInputConnections["orbital-pad-design"] == nil else { return }
    let s = synth
    do {
      try midiManager.start()
      try midiManager.addInputConnection(
        to: .allOutputs,
        tag: "orbital-pad-design",
        receiver: .events { events, _, _ in
          for event in events {
            switch event {
            case .noteOn(let e):
              let noteNum = e.note.number.uInt8Value
              let vel = e.velocity.midi1Value.uInt8Value
              Task { @MainActor in
                if vel == 0 {
                  s.noteHandler?.noteOff(MidiNote(note: noteNum, velocity: vel))
                } else {
                  if !s.engine.audioEngine.isRunning { try? s.engine.start() }
                  s.noteHandler?.noteOn(MidiNote(note: noteNum, velocity: vel))
                }
              }
            case .noteOff(let e):
              let noteNum = e.note.number.uInt8Value
              let vel = e.velocity.midi1Value.uInt8Value
              Task { @MainActor in
                s.noteHandler?.noteOff(MidiNote(note: noteNum, velocity: vel))
              }
            default:
              break
            }
          }
        }
      )
    } catch {
      // MIDI not available on this device/simulator
    }
  }

  // Ensure any selected wavetable oscillators are loaded into WavetableLibrary before rebuilding.
  // Must run on the main thread; WavetableLibrary.loadCuratedTable is @MainActor and idempotent.
  @MainActor
  private func ensureWavetablesLoaded() {
    for idx in [sliders.osc1Index, sliders.osc2Index] {
      guard !oscChoices.isEmpty else { continue }
      let choice = oscChoices[min(max(0, idx), oscChoices.count - 1)]
      if case .wavetable(let name) = choice {
        WavetableLibrary.loadCuratedTable(name)
      }
    }
  }

  private func applyRandomEffects() {
    synth.reverbPreset = AVAudioUnitReverbPreset.allCases.randomElement()!
    synth.reverbMix = .random(in: 0...50)
    synth.delayTime = .random(in: 0...30)
    synth.delayFeedback = .random(in: 0...30)
    synth.delayWetDryMix = .random(in: 0...50)
    synth.delayLowPassCutoff = .random(in: 0...1000)
  }

  private func rebuildSynth() {
    ensureWavetablesLoaded()
    let preset = PadTemplateFormView.buildPreset(mood: mood, sliders: sliders, oscChoices: oscChoices)
    synth.loadPreset(preset)
  }

  private func defaultSliders(for m: PadMood) -> PadSliders {
    switch m {
    case .cosmic:   return .cosmicDefaults
    case .dark:     return .darkDefaults
    case .warm:     return .warmDefaults
    case .ethereal: return .etherealDefaults
    case .gritty:   return .grittyDefaults
    case .custom:   return sliders
    }
  }

  private func oscName(_ index: Int) -> String {
    guard !oscChoices.isEmpty else { return "Sine" }
    return oscChoices[min(max(0, index), oscChoices.count - 1)].displayName
  }

  var body: some View {
    VStack(spacing: 0) {
      Keyboard(
        layout: .piano(pitchRange: Pitch(intValue: 48)...Pitch(intValue: 84)),
        noteOn: { pitch, _ in
          if !synth.engine.audioEngine.isRunning {
            try? synth.engine.start()
          }
          synth.noteHandler?.noteOn(MidiNote(note: MidiValue(pitch.intValue), velocity: 100))
        },
        noteOff: { pitch in
          synth.noteHandler?.noteOff(MidiNote(note: MidiValue(pitch.intValue), velocity: 0))
        }
      )
      .frame(height: 120)

      Button {
        mood = .custom
        let count = oscChoices.count
        sliders = PadSliders(
          smooth: .random(in: 0...1),
          bite: .random(in: 0...1),
          motion: .random(in: 0...1),
          width: .random(in: 0...1),
          grit: .random(in: 0...0.3),
          osc1Index: count > 0 ? Int.random(in: 0..<count) : 0,
          osc2Index: count > 0 ? Int.random(in: 0..<count) : 0
        )
        applyRandomEffects()
      } label: {
        Label("Randomize", systemImage: "dice")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .padding(.horizontal)
      .padding(.vertical, 8)

      Form {
        Section("Character") {
          Picker("Mood", selection: $mood) {
            ForEach(Self.allMoods, id: \.self) { m in
              Text(m.rawValue.capitalized).tag(m)
            }
          }
          oscSliderRow(label: "Oscillator 1", index: $sliders.osc1Index)
          oscSliderRow(label: "Oscillator 2", index: $sliders.osc2Index)
          LabeledSlider(value: $sliders.smooth, label: "Smooth", range: 0...1)
          LabeledSlider(value: $sliders.bite, label: "Bite", range: 0...1)
          LabeledSlider(value: $sliders.motion, label: "Motion", range: 0...1)
          LabeledSlider(value: $sliders.width, label: "Width", range: 0...1)
          LabeledSlider(value: $sliders.grit, label: "Grit", range: 0...1)
        }

        Section("Effects") {
          Picker("Reverb Preset", selection: $synth.reverbPreset) {
            ForEach(AVAudioUnitReverbPreset.allCases, id: \.self) { option in
              Text(option.name)
            }
          }
          LabeledSlider(value: $synth.reverbMix, label: "Reverb Wet/Dry", range: 0...100)
          if synth.delayAvailable {
            LabeledSlider(value: $synth.delayTime, label: "Delay Time", range: 0...30)
            LabeledSlider(value: $synth.delayFeedback, label: "Delay Feedback", range: 0...30)
            LabeledSlider(value: $synth.delayWetDryMix, label: "Delay Wet/Dry", range: 0...100)
            LabeledSlider(value: $synth.delayLowPassCutoff, label: "Delay LowPass", range: 0...1000)
          }
        }
      }
    }
    .onAppear { setupMIDI() }
    .navigationTitle("Sound Design")
    .onChange(of: mood) { _, newMood in
      if newMood != .custom {
        sliders = defaultSliders(for: newMood)
      }
      rebuildSynth()
    }
    .onChange(of: sliders) { _, _ in
      rebuildSynth()
    }
  }

  @ViewBuilder
  private func oscSliderRow(label: String, index: Binding<Int>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(label): \(oscName(index.wrappedValue))")
        .font(.caption)
        .foregroundStyle(.secondary)
      if oscChoices.count > 1 {
        Slider(
          value: Binding(
            get: { Double(index.wrappedValue) },
            set: { index.wrappedValue = Int($0.rounded()) }
          ),
          in: 0...Double(oscChoices.count - 1),
          step: 1
        )
      }
    }
    .padding(.vertical, 2)
  }
}

#Preview {
  PadTemplateFormView()
    .environment(SpatialAudioEngine())
}
