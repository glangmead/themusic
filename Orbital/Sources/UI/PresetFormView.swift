//
//  PresetFormView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import AVFAudio
import Keyboard
import MIDIKitIO
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

  @State private var midiManager = ObservableMIDIManager(
    clientName: "Orbital",
    model: "Orbital",
    manufacturer: "Orbital"
  )
  @State private var padSynthRebuildTask: Task<Void, Never>?

  /// The note handler the keyboard uses: prefer the live spatial preset
  /// from the song track when available, fall back to the synth's own.
  private var keyboardNoteHandler: NoteHandler? {
    liveSpatialPreset ?? synth.noteHandler
  }

  private func setupMIDI() {
    guard midiManager.managedInputConnections["orbital-midi-in"] == nil else { return }
    let lsp = liveSpatialPreset
    let s = synth
    do {
      try midiManager.start()
      try midiManager.addInputConnection(
        to: .allOutputs,
        tag: "orbital-midi-in",
        receiver: .events { events, _, _ in
          for event in events {
            switch event {
            case .noteOn(let e):
              let noteNum = e.note.number.uInt8Value
              let vel = e.velocity.midi1Value.uInt8Value
              Task { @MainActor in
                let handler = lsp ?? s.noteHandler
                if vel == 0 {
                  handler?.noteOff(MidiNote(note: noteNum, velocity: vel))
                } else {
                  if !s.engine.audioEngine.isRunning { try? s.engine.start() }
                  handler?.noteOn(MidiNote(note: noteNum, velocity: vel))
                }
              }
            case .noteOff(let e):
              let noteNum = e.note.number.uInt8Value
              let vel = e.velocity.midi1Value.uInt8Value
              Task { @MainActor in
                let handler = lsp ?? s.noteHandler
                handler?.noteOff(MidiNote(note: noteNum, velocity: vel))
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
        EffectsFormGroup(synth: synth)

        if synth.hasPadSynth {
          HarmonicsFormGroup(synth: synth)
          BandwidthFormGroup(synth: synth)
          OvertoneFormGroup(synth: synth)
          InstrumentFormGroup(synth: synth)
        }

        if let handler = synth.arrowHandler {
          ForEach(handler.groupedDescriptors(), id: \.0) { title, descs in
            ArrowParamFormGroup(title: title, descriptors: descs, handler: handler)
          }
        }

        if let arrow = presetSpec.arrow, let handler = synth.arrowHandler {
          DisclosureGroup("Advanced") {
            ArrowSyntaxEditorView(syntax: arrow, handler: handler)
          }
        }
      }
      .controlSize(.small)
    }
    .onAppear { setupMIDI() }
    .navigationTitle(presetSpec.name)
    .onChange(of: synth.padSynthBaseShape) { rebuildPadSynth() }
    .onChange(of: synth.padSynthTilt) { rebuildPadSynth() }
    .onChange(of: synth.padSynthBandwidthCents) { rebuildPadSynth() }
    .onChange(of: synth.padSynthBwScale) { rebuildPadSynth() }
    .onChange(of: synth.padSynthProfileShape) { rebuildPadSynth() }
    .onChange(of: synth.padSynthStretch) { rebuildPadSynth() }
    .onChange(of: synth.padSynthSelectedInstrument) { rebuildPadSynth() }
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

  private func rebuildPadSynth() {
    guard synth.hasPadSynth else { return }
    padSynthRebuildTask?.cancel()
    padSynthRebuildTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      let newPadSynth = PADSynthSyntax(
        baseShape: synth.padSynthBaseShape,
        tilt: synth.padSynthTilt,
        bandwidthCents: synth.padSynthBandwidthCents,
        bwScale: synth.padSynthBwScale,
        profileShape: synth.padSynthProfileShape,
        stretch: synth.padSynthStretch,
        selectedInstrument: synth.padSynthSelectedInstrument,
        envelopeCoefficients: synth.presetSpec.effectivePadSynth?.envelopeCoefficients
      )
      let newSpec = PresetSyntax(
        name: synth.presetSpec.name,
        arrow: synth.presetSpec.arrow,
        samplerFilenames: nil,
        samplerProgram: nil,
        samplerBank: nil,
        library: synth.presetSpec.library,
        rose: synth.presetSpec.rose,
        effects: synth.presetSpec.effects,
        padTemplate: nil,
        padSynth: newPadSynth
      )
      synth.loadPreset(newSpec)
    }
  }
}

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
