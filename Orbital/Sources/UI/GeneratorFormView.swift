//
//  GeneratorFormView.swift
//  Orbital
//
//  High-level generator controls that produce a ScorePatternSyntax on the fly.
//  Changes take effect immediately (hot-reload via SongDocument.replaceGeneratorPattern).
//

import SwiftUI

// MARK: - GeneratorFormView

struct GeneratorFormView: View {
  @Environment(SongDocument.self) private var playbackState

  @State private var rootNote: String
  @State private var scaleType: GeneratorScaleType
  @State private var motion: GeneratorMotion
  @State private var chordType: GeneratorChordType
  @State private var texture: GeneratorTexture
  @State private var bpm: Double
  @State private var beatsPerChord: Double
  @State private var voicing: VoicingStyle?
  @State private var randomSeed: Int
  @State private var seedLocked: Bool

  private static let rootNotes = ["C", "C#", "Db", "D", "Eb", "E", "F", "F#", "Gb", "G", "Ab", "A", "Bb", "B"]

  init(params: GeneratorSyntax) {
    _rootNote = State(initialValue: params.rootNote)
    _scaleType = State(initialValue: params.scaleType)
    _motion = State(initialValue: params.motion)
    _chordType = State(initialValue: params.chordType)
    _texture = State(initialValue: params.texture)
    _bpm = State(initialValue: params.bpm)
    _beatsPerChord = State(initialValue: params.beatsPerChord)
    _voicing = State(initialValue: params.voicing)
    _randomSeed = State(initialValue: params.randomSeed ?? Int.random(in: 0...Int.max))
    _seedLocked = State(initialValue: params.randomSeed != nil)
  }

  var body: some View {
    Form {
      keyAndScaleSection
      harmonicMotionSection
      textureSection
      timingSection
      randomizationSection
    }
    .navigationTitle("Generator")
    .toolbar {
      ToolbarItemGroup {
        Button {
          playbackState.togglePlayback()
        } label: {
          Image(systemName: playbackState.isPlaying && !playbackState.isPaused ? "pause.fill" : "play.fill")
        }
        Button {
          apply()
          playbackState.restart()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
    }
    .onChange(of: rootNote) { _, _ in applyIfLive() }
    .onChange(of: scaleType) { _, _ in applyIfLive() }
    .onChange(of: motion) { _, _ in applyIfLive() }
    .onChange(of: chordType) { _, _ in applyIfLive() }
    .onChange(of: texture) { _, _ in applyIfLive() }
    .onChange(of: bpm) { _, _ in applyIfLive() }
    .onChange(of: beatsPerChord) { _, _ in applyIfLive() }
    .onChange(of: voicing) { _, _ in applyIfLive() }
  }

  // MARK: - Sections

  private var keyAndScaleSection: some View {
    Section("Key & Scale") {
      Picker("Root", selection: $rootNote) {
        ForEach(Self.rootNotes, id: \.self) { note in
          Text(note).tag(note)
        }
      }
      Picker("Scale", selection: $scaleType) {
        ForEach(GeneratorScaleType.allCases, id: \.self) { scale in
          Text(scale.displayName).tag(scale)
        }
      }
    }
  }

  private var harmonicMotionSection: some View {
    Section("Harmonic Motion") {
      Picker("Motion", selection: $motion) {
        ForEach(GeneratorMotion.allCases, id: \.self) { m in
          Text(m.displayName).tag(m)
        }
      }
      if !scaleType.supportsFunctionalMotion && isFunctionalMotion(motion) {
        Text("This scale type doesn't support functional harmony. Consider a Parallel or Debussy motion.")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      Picker("Chord Type", selection: $chordType) {
        ForEach(GeneratorChordType.allCases, id: \.self) { ct in
          Text(ct.displayName).tag(ct)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text("Beats per Chord: \(Int(beatsPerChord))")
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(value: $beatsPerChord, in: 1...16, step: 1)
      }
    }
  }

  private var textureSection: some View {
    Section("Texture & Voicing") {
      Picker("Texture", selection: $texture) {
        ForEach(GeneratorTexture.allCases, id: \.self) { t in
          Text(t.displayName).tag(t)
        }
      }
      Picker("Voicing", selection: $voicing) {
        Text("Auto").tag(nil as VoicingStyle?)
        ForEach(VoicingStyle.allCases, id: \.self) { v in
          Text(voicingDisplayName(v)).tag(Optional(v))
        }
      }
    }
  }

  private var timingSection: some View {
    Section("Timing") {
      VStack(alignment: .leading, spacing: 2) {
        Text("BPM: \(Int(bpm))")
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(value: $bpm, in: 40...200, step: 1)
      }
    }
  }

  private var randomizationSection: some View {
    Section("Randomization") {
      Toggle("Lock Seed", isOn: $seedLocked)
      Button("Re-roll") {
        randomSeed = Int.random(in: 0...Int.max)
        apply()
        if playbackState.isPlaying {
          playbackState.restart()
        }
      }
      .disabled(seedLocked)
      Text("Seed: \(randomSeed)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Apply

  private func currentParams() -> GeneratorSyntax {
    GeneratorSyntax(
      rootNote: rootNote,
      scaleType: scaleType,
      motion: motion,
      chordType: chordType,
      texture: texture,
      bpm: bpm,
      beatsPerChord: beatsPerChord,
      voicing: voicing,
      randomSeed: seedLocked ? randomSeed : nil
    )
  }

  private func apply() {
    playbackState.replaceGeneratorPattern(currentParams())
  }

  private func applyIfLive() {
    if playbackState.isPlaying {
      apply()
      playbackState.restart()
    }
  }

  // MARK: - Helpers

  private func isFunctionalMotion(_ m: GeneratorMotion) -> Bool {
    switch m {
    case .drone, .shuttle, .plagal, .fourChords, .oneLoop, .twoLoop,
         .descendingThirds, .descendingFifths:
      return true
    default:
      return false
    }
  }

  private func voicingDisplayName(_ v: VoicingStyle) -> String {
    switch v {
    case .closed:    return "Closed"
    case .open:      return "Open"
    case .dropTwo:   return "Drop-2"
    case .spread:    return "Spread"
    case .shell:     return "Shell"
    case .fifthsOnly: return "Fifths Only"
    }
  }
}

// MARK: - Preview

#Preview {
  let song = SongRef(name: "Generator Preview", patternFileName: "table/aurora_arpeggio.json")
  let doc = SongDocument(song: song)
  NavigationStack {
    GeneratorFormView(params: GeneratorSyntax())
      .environment(doc)
  }
}
