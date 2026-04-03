//
//  PADSynthFormView.swift
//  Orbital
//

import Keyboard
import MIDIKitIO
import SwiftUI
import Tonic

struct PADSynthFormView: View {
  @State private var engine = PADSynthEngine()
  @State private var player = PADSynthPlayer()
  @State private var recomputeTask: Task<Void, Never>?
  @State private var midiManager = ObservableMIDIManager(
    clientName: "Orbital",
    model: "Orbital",
    manufacturer: "Orbital"
  )

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Keyboard(
          layout: .piano(pitchRange: Pitch(intValue: 48)...Pitch(intValue: 84)),
          noteOn: { pitch, _ in
            player.noteOn(note: UInt8(pitch.intValue), velocity: 100)
          },
          noteOff: { pitch in
            player.noteOff(note: UInt8(pitch.intValue))
          }
        )
        .frame(height: 120)

        PADSynthGraphView(engine: engine, onEnvelopeChanged: {
          player.invalidateCache()
        })
          .padding(8)
          .background(.black.opacity(0.05))
          .frame(minHeight: 200, maxHeight: .infinity)

        PADSynthControlsView(
          engine: engine,
          onParameterChange: { scheduleRecompute() },
          onClearEnvelope: {
            engine.envelopeCoefficients = nil
            scheduleRecompute()
          }
        )
        .frame(minHeight: 250, maxHeight: .infinity)
      }
      .navigationTitle("Sound Design 2")
      .task {
        player.configure(engine: engine)
        setupMIDI()
        await engine.recomputeDisplay()
      }
    }
  }

  private func setupMIDI() {
    guard midiManager.managedInputConnections["orbital-padsynth"] == nil else { return }
    let p = player
    do {
      try midiManager.start()
      try midiManager.addInputConnection(
        to: .allOutputs,
        tag: "orbital-padsynth",
        receiver: .events { events, _, _ in
          for event in events {
            switch event {
            case .noteOn(let e):
              let noteNum = e.note.number.uInt8Value
              let vel = e.velocity.midi1Value.uInt8Value
              Task { @MainActor in
                if vel == 0 {
                  p.noteOff(note: noteNum)
                } else {
                  p.noteOn(note: noteNum, velocity: vel)
                }
              }
            case .noteOff(let e):
              let noteNum = e.note.number.uInt8Value
              Task { @MainActor in
                p.noteOff(note: noteNum)
              }
            default:
              break
            }
          }
        }
      )
    } catch {
      // MIDI not available
    }
  }

  private func scheduleRecompute() {
    // Invalidate wavetable cache immediately so stale sounds are never played.
    // The fallback in noteOn generates on-the-fly with current parameters.
    player.invalidateCache()

    // Debounce the display update (expensive)
    recomputeTask?.cancel()
    recomputeTask = Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      await engine.recomputeDisplay()
    }
  }
}

// MARK: - Controls

private struct PADSynthControlsView: View {
  @Bindable var engine: PADSynthEngine
  var onParameterChange: () -> Void
  var onClearEnvelope: () -> Void

  var body: some View {
    Form {
      Section {
        Button {
          onClearEnvelope()
        } label: {
          Label("Clear Envelope", systemImage: "xmark.circle")
        }
        .disabled(engine.envelopeCoefficients == nil)
      }

      Section("Instrument") {
        Picker("Timbre source", selection: $engine.selectedInstrument) {
          Text("Custom").tag(String?.none)
          ForEach(SharcDatabase.shared.instruments) { inst in
            Text(inst.displayName).tag(Optional(inst.id))
          }
        }
        .onChange(of: engine.selectedInstrument) { onParameterChange() }
      }

      Section("Harmonics") {
        if engine.selectedInstrument == nil {
          Picker("Base shape", selection: $engine.baseShape) {
            ForEach(PADBaseShape.allCases) { shape in
              Text(shape.rawValue).tag(shape)
            }
          }
          .onChange(of: engine.baseShape) { onParameterChange() }
        }

        LabeledSlider(value: $engine.tilt, label: "Tilt", range: -2.0...2.0, step: 0.1)
          .onChange(of: engine.tilt) { onParameterChange() }
      }

      Section("Bandwidth") {
        LabeledSlider(value: $engine.bandwidthCents, label: "Bandwidth (cents)", range: 1...200, step: 1)
          .onChange(of: engine.bandwidthCents) { onParameterChange() }

        LabeledSlider(value: $engine.bwScale, label: "BW scale", range: 0.5...2.0, step: 0.05)
          .onChange(of: engine.bwScale) { onParameterChange() }

        Picker("Profile", selection: $engine.profileShape) {
          ForEach(PADProfileShape.allCases) { profile in
            Text(profile.rawValue).tag(profile)
          }
        }
        .onChange(of: engine.profileShape) { onParameterChange() }
      }

      Section("Overtones") {
        Picker("Preset", selection: $engine.overtonePreset) {
          ForEach(PADOvertonePreset.allCases) { preset in
            Text(preset.rawValue).tag(preset)
          }
        }
        .onChange(of: engine.overtonePreset) { _, newPreset in
          engine.stretch = newPreset.stretchValue
          onParameterChange()
        }

        LabeledSlider(value: $engine.stretch, label: "Stretch", range: 0.9...1.5, step: 0.01)
          .onChange(of: engine.stretch) { onParameterChange() }
      }
    }
  }
}

#Preview {
  PADSynthFormView()
}
