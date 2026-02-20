//
//  PresetFormView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import AVFAudio
import Keyboard
import SwiftUI
import Tonic

struct PresetFormView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongPlaybackState.self) private var playbackState: SongPlaybackState?
  let presetSpec: PresetSyntax
  @State private var synth: SyntacticSynth?
  private let externalSynth: SyntacticSynth?

  /// Create a PresetFormView that builds its own SyntacticSynth.
  init(presetSpec: PresetSyntax) {
    self.presetSpec = presetSpec
    self.externalSynth = nil
  }

  /// Create a PresetFormView that uses an existing SyntacticSynth.
  init(synth: SyntacticSynth) {
    self.presetSpec = synth.presetSpec
    self.externalSynth = synth
  }

  var body: some View {
    if let resolved = externalSynth ?? synth {
      PresetFormContent(
        synth: resolved,
        presetSpec: presetSpec,
        playbackState: playbackState
      )
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
  var playbackState: SongPlaybackState?

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

      Form {
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

        if let handler = synth.arrowHandler {
          ForEach(handler.groupedDescriptors(), id: \.0) { title, descs in
            Section(title) {
              ForEach(descs) { desc in
                ArrowParamRow(descriptor: desc, handler: handler)
              }
            }
          }
        }

        if let arrow = presetSpec.arrow, let handler = synth.arrowHandler {
          DisclosureGroup("Advanced") {
            ArrowSyntaxEditorView(syntax: arrow, handler: handler)
          }
        }
      }
    }
    .navigationTitle(presetSpec.name)
    .toolbar {
      if let playbackState {
        ToolbarItemGroup {
          Button {
            playbackState.togglePlayback()
          } label: {
            Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
          }
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
// MARK: - ArrowParamRow

#Preview {
  let presetSpec = Bundle.main.decode(
    PresetSyntax.self,
    from: "auroraBorealis.json",
    subdirectory: "presets"
  )
  NavigationStack {
    PresetFormView(presetSpec: presetSpec)
  }
  .environment(SpatialAudioEngine())
}

/// A single row in the dynamic arrow parameter form. Renders a Picker for osc
/// shapes and a LabeledSlider for everything else.
private struct ArrowParamRow: View {
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
      LabeledSlider(
        value: handler.floatBinding(for: descriptor.id),
        label: descriptor.displayName,
        range: descriptor.suggestedRange,
        step: descriptor.stepSize
      )
    }
  }
}

