//
//  WavetableBrowserView.swift
//  Orbital
//
//  Lets you audition raw Serum-format wavetable WAV files without creating JSON presets.
//  Copy folders of .wav files into your presets/ directory (e.g. via Files.app),
//  then browse and play them here. Use the Frame slider to sweep through morph frames.
//  When you find a sound you like, create a JSON preset referencing the tableName.
//

import AVFAudio
import Keyboard
import MIDIKitIO
import SwiftUI
import Tonic

struct WavetableBrowserView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(ResourceManager.self) private var resourceManager

  @State private var packs: [WavetablePack] = []
  @State private var selectedFile: URL?
  @State private var frameIndex: Int = 0
  @State private var frameCount: Int = 1
  @State private var synth: SyntacticSynth?
  @State private var midiManager = ObservableMIDIManager(
    clientName: "OrbitalBrowser",
    model: "Orbital",
    manufacturer: "Orbital"
  )

  var body: some View {
    VStack(spacing: 0) {
      fileList
      if let s = synth {
        playerPanel(s)
      }
    }
    .navigationTitle("Wavetable Browser")
    .onAppear { loadPacks() }
    .onChange(of: resourceManager.isReady) { _, _ in loadPacks() }
  }

  // MARK: - File list

  private var fileList: some View {
    List {
      if packs.isEmpty {
        if resourceManager.isReady {
          Text("Copy wavetable folders (containing .wav files) into your presets/ folder to browse them here.")
            .foregroundStyle(.secondary)
            .font(.caption)
        } else {
          ProgressView("Loading…")
        }
      }
      ForEach(packs) { pack in
        Section(pack.name) {
          ForEach(pack.files, id: \.self) { file in
            Button {
              selectFile(file)
            } label: {
              HStack {
                Text(file.deletingPathExtension().lastPathComponent)
                Spacer()
                if file == selectedFile {
                  Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                }
              }
            }
            .foregroundStyle(.primary)
          }
        }
      }
    }
  }

  // MARK: - Player panel

  @ViewBuilder
  private func playerPanel(_ s: SyntacticSynth) -> some View {
    VStack(spacing: 8) {
      if frameCount > 1 {
        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text("Frame")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text("\(frameIndex + 1) / \(frameCount)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Slider(
            value: Binding(
              get: { Double(frameIndex) },
              set: { frameIndex = Int($0.rounded()) }
            ),
            in: 0...Double(max(frameCount - 1, 1)),
            step: 1,
            onEditingChanged: { editing in
              if !editing { reloadFrame() }
            }
          )
        }
        .padding(.horizontal)
        .padding(.top, 8)
      }
      Keyboard(
        layout: .piano(pitchRange: Pitch(intValue: 48)...Pitch(intValue: 84)),
        noteOn: { pitch, _ in
          if !s.engine.audioEngine.isRunning { try? s.engine.start() }
          s.noteHandler?.noteOn(MidiNote(note: MidiValue(pitch.intValue), velocity: 100))
        },
        noteOff: { pitch in
          s.noteHandler?.noteOff(MidiNote(note: MidiValue(pitch.intValue), velocity: 0))
        }
      )
      .frame(height: 120)
    }
    .background(.regularMaterial)
  }

  // MARK: - Selection & reload

  private func selectFile(_ url: URL) {
    selectedFile = url
    frameIndex = 0
    frameCount = WavetableLibrary.frameCount(url: url)
    WavetableLibrary.userTables["_audition_"] = WavetableLibrary.fromFile(url: url, frameIndex: 0)
    let spec = buildAuditionPreset(name: url.deletingPathExtension().lastPathComponent)
    if let s = synth {
      s.loadPreset(spec)
    } else {
      let s = SyntacticSynth(engine: engine, presetSpec: spec)
      synth = s
      setupMIDI(synth: s)
    }
  }

  private func reloadFrame() {
    guard let url = selectedFile else { return }
    WavetableLibrary.userTables["_audition_"] = WavetableLibrary.fromFile(url: url, frameIndex: frameIndex)
    synth?.loadPreset(buildAuditionPreset(name: url.deletingPathExtension().lastPathComponent))
  }

  // MARK: - Preset building

  private func buildAuditionPreset(name: String) -> PresetSyntax {
    PresetSyntax(
      name: name,
      arrow: .compose(arrows: [
        .prod(of: [
          .const(name: "overallAmp", val: 1.0),
          .compose(arrows: [
            .prod(of: [
              .const(name: "freq", val: 300),
              .constOctave(name: "osc1Octave", val: 0),
              .identity
            ]),
            .wavetable(name: "osc1", tableName: "_audition_",
                       width: .const(name: "width", val: 1.0))
          ]),
          .envelope(name: "ampEnv", attack: 0.02, decay: 0.5,
                    sustain: 0.8, release: 0.4, scale: 1.0)
        ]),
        .lowPassFilter(name: "filter",
                       cutoff: .const(name: "cutoff", val: 8000),
                       resonance: .const(name: "resonance", val: 0.5))
      ]),
      samplerFilenames: nil,
      samplerProgram: nil,
      samplerBank: nil,
      library: nil,
      rose: RoseSyntax(amp: 3, leafFactor: 4, freq: 0.3, phase: 0),
      effects: EffectsSyntax(
        reverbPreset: 3,
        reverbWetDryMix: 20,
        delayTime: 0,
        delayFeedback: 0,
        delayLowPassCutoff: 100_000,
        delayWetDryMix: 0
      )
    )
  }

  // MARK: - Pack loading

  // Scans both the app bundle (bundled wavetables) and Documents/iCloud (user-added folders).
  // ResourceManager only copies .json files, so WAV packs must be read from the bundle directly.
  private func loadPacks() {
    var seen = Set<String>()
    var result: [WavetablePack] = []
    // Always scan the bundle — WAV files are never copied to Documents by ResourceManager.
    if let bundlePresetsURL = Bundle.main.resourceURL?.appendingPathComponent("presets") {
      for pack in scanForWavetablePacks(at: bundlePresetsURL) where seen.insert(pack.name).inserted {
        result.append(pack)
      }
    }
    // Also scan Documents / iCloud for any user-added wavetable folders (via Files.app).
    if let base = resourceManager.resourceBaseURL {
      for pack in scanForWavetablePacks(at: base.appendingPathComponent("presets"))
        where seen.insert(pack.name).inserted {
        result.append(pack)
      }
    }
    packs = result.sorted { $0.name < $1.name }
  }

  private func scanForWavetablePacks(at presetsDir: URL) -> [WavetablePack] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
      at: presetsDir,
      includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return [] }
    return contents.compactMap { url -> WavetablePack? in
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
      let wavs = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "wav" }) ?? []
      guard !wavs.isEmpty else { return nil }
      return WavetablePack(
        name: url.lastPathComponent,
        files: wavs.sorted { $0.lastPathComponent < $1.lastPathComponent }
      )
    }
  }

  // MARK: - MIDI

  private func setupMIDI(synth s: SyntacticSynth) {
    guard midiManager.managedInputConnections["orbital-wt-browser"] == nil else { return }
    do {
      try midiManager.start()
      try midiManager.addInputConnection(
        to: .allOutputs,
        tag: "orbital-wt-browser",
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
      // MIDI unavailable on this device/simulator
    }
  }
}

// MARK: - WavetablePack

private struct WavetablePack: Identifiable {
  var id: String { name }
  let name: String
  let files: [URL]
}
