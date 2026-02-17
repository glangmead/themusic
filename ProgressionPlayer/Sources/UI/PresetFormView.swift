//
//  PresetFormView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import AVFAudio
import SwiftUI

struct PresetFormView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongPlaybackState.self) private var playbackState
  let presetSpec: PresetSyntax
  @State private var isShowingVisualizer = false
  @State private var synth: SyntacticSynth?

  var body: some View {
    if let synth {
      PresetFormContent(
        synth: synth,
        presetSpec: presetSpec,
        playbackState: playbackState,
        engine: engine,
        isShowingVisualizer: $isShowingVisualizer
      )
      .fullScreenCover(isPresented: $isShowingVisualizer) {
        VisualizerView(engine: engine, noteHandler: playbackState.noteHandler, isPresented: $isShowingVisualizer)
          .ignoresSafeArea()
      }
    } else {
      ProgressView()
        .onAppear {
          let s = SyntacticSynth(engine: engine, presetSpec: presetSpec)
          s.loadPreset(presetSpec)
          synth = s
        }
    }
  }
}

/// Extracted so that `synth` is guaranteed non-nil and we can use `@Bindable`.
private struct PresetFormContent: View {
  @Bindable var synth: SyntacticSynth
  let presetSpec: PresetSyntax
  @Bindable var playbackState: SongPlaybackState
  let engine: SpatialAudioEngine
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    Form {
      Section("Rose (Spatial Movement)") {
        LabeledSlider(value: $synth.roseAmp, label: "Amplitude", range: 0...20)
        LabeledSlider(value: $synth.roseFreq, label: "Frequency", range: 0...30)
        LabeledSlider(value: $synth.roseLeaves, label: "Leaves", range: 0...30)
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

      Section("Oscillator 1") {
        Picker("Shape", selection: $synth.oscShape1) {
          ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
            Text(String(describing: option))
          }
        }
        LabeledSlider(value: $synth.osc1Mix, label: "Mix", range: 0...1)
        LabeledSlider(value: $synth.osc1Octave, label: "Octave", range: -5...5, step: 1)
        LabeledSlider(value: $synth.osc1CentDetune, label: "Cent Detune", range: -500...500, step: 1)
        LabeledSlider(value: $synth.osc1Width, label: "Pulse Width", range: 0...1)
        LabeledSlider(value: $synth.osc1ChorusCentRadius, label: "Chorus Cents", range: 0...30, step: 1)
        LabeledSlider(value: $synth.osc1ChorusNumVoices, label: "Chorus Voices", range: 1...12, step: 1)
      }

      Section("Oscillator 2") {
        Picker("Shape", selection: $synth.oscShape2) {
          ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
            Text(String(describing: option))
          }
        }
        LabeledSlider(value: $synth.osc2Mix, label: "Mix", range: 0...1)
        LabeledSlider(value: $synth.osc2Octave, label: "Octave", range: -5...5, step: 1)
        LabeledSlider(value: $synth.osc2CentDetune, label: "Cent Detune", range: -500...500, step: 1)
        LabeledSlider(value: $synth.osc2Width, label: "Pulse Width", range: 0...1)
        LabeledSlider(value: $synth.osc2ChorusCentRadius, label: "Chorus Cents", range: 0...30, step: 1)
        LabeledSlider(value: $synth.osc2ChorusNumVoices, label: "Chorus Voices", range: 1...12, step: 1)
      }

      Section("Oscillator 3") {
        Picker("Shape", selection: $synth.oscShape3) {
          ForEach(BasicOscillator.OscShape.allCases, id: \.self) { option in
            Text(String(describing: option))
          }
        }
        LabeledSlider(value: $synth.osc3Mix, label: "Mix", range: 0...1)
        LabeledSlider(value: $synth.osc3Octave, label: "Octave", range: -5...5, step: 1)
        LabeledSlider(value: $synth.osc3CentDetune, label: "Cent Detune", range: -500...500, step: 1)
        LabeledSlider(value: $synth.osc3Width, label: "Pulse Width", range: 0...1)
        LabeledSlider(value: $synth.osc3ChorusCentRadius, label: "Chorus Cents", range: 0...30, step: 1)
        LabeledSlider(value: $synth.osc3ChorusNumVoices, label: "Chorus Voices", range: 1...12, step: 1)
      }

      Section("Amp Envelope") {
        LabeledSlider(value: $synth.ampAttack, label: "Attack", range: 0...2)
        LabeledSlider(value: $synth.ampDecay, label: "Decay", range: 0...2)
        LabeledSlider(value: $synth.ampSustain, label: "Sustain", range: 0...1)
        LabeledSlider(value: $synth.ampRelease, label: "Release", range: 0...2)
      }

      Section("Filter") {
        LabeledSlider(value: $synth.filterCutoff, label: "Cutoff", range: 1...20000, step: 1)
        LabeledSlider(value: $synth.filterResonance, label: "Resonance", range: 0.1...15, step: 0.01)
      }

      Section("Filter Envelope") {
        LabeledSlider(value: $synth.filterAttack, label: "Attack", range: 0...2)
        LabeledSlider(value: $synth.filterDecay, label: "Decay", range: 0...2)
        LabeledSlider(value: $synth.filterSustain, label: "Sustain", range: 0...1)
        LabeledSlider(value: $synth.filterRelease, label: "Release", range: 0.03...2)
      }

      Section("Vibrato") {
        LabeledSlider(value: $synth.vibratoAmp, label: "Amplitude", range: 0...20)
        LabeledSlider(value: $synth.vibratoFreq, label: "Frequency", range: 0...30)
      }

      if let arrow = presetSpec.arrow {
        DisclosureGroup("Advanced") {
          ArrowSyntaxEditorView(syntax: arrow, synth: synth)
        }
      }
    }
    .navigationTitle(presetSpec.name)
    .toolbar {
      ToolbarItem {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
        }
      }
      ToolbarItem {
        Button {
          withAnimation(.easeInOut(duration: 0.4)) {
            isShowingVisualizer = true
          }
        } label: {
          Label("Visualizer", systemImage: "sparkles.tv")
        }
      }
    }
  }
}

// MARK: - LabeledSlider

/// A slider with a label and current value display, for use in Forms.
struct LabeledSlider: View {
  @Binding var value: CoreFloat
  let label: String
  let range: ClosedRange<CoreFloat>
  var step: CoreFloat? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label)
        Spacer()
        Text(formattedValue)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      if let step = step {
        Slider(value: $value, in: range, step: step)
      } else {
        Slider(value: $value, in: range)
      }
    }
  }

  private var formattedValue: String {
    if let step = step, step >= 1 {
      return String(format: "%.0f", value)
    }
    return String(format: "%.3f", value)
  }
}
