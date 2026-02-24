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
  @Environment(SongDocument.self) private var playbackState: SongDocument?
  let presetSpec: PresetSyntax
  @State private var synth: SyntacticSynth?
  private let externalSynth: SyntacticSynth?
  /// Live spatial preset from a song track; used for the keyboard so
  /// edits made in SpatialFormView are heard immediately.
  private let liveSpatialPreset: SpatialPreset?

  /// Create a PresetFormView that builds its own SyntacticSynth.
  init(presetSpec: PresetSyntax) {
    self.presetSpec = presetSpec
    self.externalSynth = nil
    self.liveSpatialPreset = nil
  }

  /// Create a PresetFormView that uses an existing SyntacticSynth.
  init(synth: SyntacticSynth) {
    self.presetSpec = synth.presetSpec
    self.externalSynth = synth
    self.liveSpatialPreset = nil
  }

  /// Create a PresetFormView backed by a live SpatialPreset from a song track.
  /// The keyboard plays through this preset so spatial parameter edits are heard.
  init(presetSpec: PresetSyntax, spatialPreset: SpatialPreset) {
    self.presetSpec = presetSpec
    self.externalSynth = nil
    self.liveSpatialPreset = spatialPreset
  }

  var body: some View {
    if let resolved = externalSynth ?? synth {
      PresetFormContent(
        synth: resolved,
        presetSpec: presetSpec,
        playbackState: playbackState,
        liveSpatialPreset: liveSpatialPreset
      )
    } else {
      ProgressView()
        .onAppear {
          if let liveSpatialPreset {
            let s = SyntacticSynth(engine: engine, presetSpec: presetSpec, deferSetup: true)
            s.attachToLivePreset(liveSpatialPreset)
            synth = s
          } else {
            let s = SyntacticSynth(engine: engine, presetSpec: presetSpec)
            synth = s
          }
        }
    }
  }
}

/// Extracted so that `synth` is guaranteed non-nil and we can use `@Bindable`.
private struct PresetFormContent: View {
  @Bindable var synth: SyntacticSynth
  let presetSpec: PresetSyntax
  var playbackState: SongDocument?
  /// When provided, the keyboard plays through this preset instead of the
  /// synth's own spatial preset, so spatial edits are reflected.
  var liveSpatialPreset: SpatialPreset?

  /// The note handler the keyboard uses: prefer the live spatial preset
  /// from the song track when available, fall back to the synth's own.
  private var keyboardNoteHandler: NoteHandler? {
    liveSpatialPreset ?? synth.noteHandler
  }

  var body: some View {
    VStack(spacing: 0) {
      Keyboard(
        layout: .piano(pitchRange: Pitch(intValue: 48)...Pitch(intValue: 84)),
        noteOn: { pitch, _ in
          if !synth.engine.audioEngine.isRunning {
            try? synth.engine.start()
          }
          keyboardNoteHandler?.noteOn(MidiNote(note: MidiValue(pitch.intValue), velocity: 100))
        },
        noteOff: { pitch in
          keyboardNoteHandler?.noteOff(MidiNote(note: MidiValue(pitch.intValue), velocity: 0))
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

