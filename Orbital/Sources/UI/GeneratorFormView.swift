//
//  GeneratorFormView.swift
//  Orbital
//
//  Chorale-based generator controls. Produces a ScorePatternSyntax via
//  GeneratorEngine.generate(); changes take effect immediately via
//  SongDocument.replaceGeneratorPattern.
//

import SwiftUI

// MARK: - GeneratorFormView

struct GeneratorFormView: View {
  @Environment(SongDocument.self) private var playbackState

  @State private var rootNote: String
  @State private var scaleType: GeneratorScaleType
  @State private var motion: GeneratorMotion
  @State private var chordType: GeneratorChordType
  @State private var bpm: Double
  @State private var beatsPerChord: Double
  @State private var bassOctave: Int
  @State private var upperVoiceLowOctave: Int
  @State private var upperVoiceHighOctave: Int
  @State private var tPowerSequenceText: String
  @State private var ttPowerSequenceText: String
  @State private var randomSeed: Int
  @State private var seedLocked: Bool
  @State private var melody: GeneratorMelody

  private static let rootNotes = ["C", "C#", "Db", "D", "Eb", "E", "F", "F#", "Gb", "G", "Ab", "A", "Bb", "B"]

  init(params: GeneratorSyntax) {
    _rootNote = State(initialValue: params.rootNote)
    _scaleType = State(initialValue: params.scaleType)
    _motion = State(initialValue: params.motion)
    _chordType = State(initialValue: params.chordType)
    _bpm = State(initialValue: params.bpm)
    _beatsPerChord = State(initialValue: params.beatsPerChord)
    _bassOctave = State(initialValue: params.bassOctave)
    _upperVoiceLowOctave = State(initialValue: params.upperVoiceLowOctave)
    _upperVoiceHighOctave = State(initialValue: params.upperVoiceHighOctave)
    let tSequence = params.tPowerSequence ?? []
    _tPowerSequenceText = State(initialValue: tSequence.map(String.init).joined(separator: ","))
    let ttSequence = params.ttPowerSequence ?? []
    _ttPowerSequenceText = State(initialValue: ttSequence.map(String.init).joined(separator: ","))
    _randomSeed = State(initialValue: params.randomSeed ?? Int.random(in: 0...Int.max))
    _seedLocked = State(initialValue: params.randomSeed != nil)
    _melody = State(initialValue: params.melody ?? .none)
  }

  var body: some View {
    Form {
      tonalitySection
      progressionSection
      melodySection
      rangeSection
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
    .onChange(of: bpm) { _, _ in applyIfLive() }
    .onChange(of: beatsPerChord) { _, _ in applyIfLive() }
    .onChange(of: bassOctave) { _, _ in applyIfLive() }
    .onChange(of: upperVoiceLowOctave) { _, _ in applyIfLive() }
    .onChange(of: upperVoiceHighOctave) { _, _ in applyIfLive() }
    .onChange(of: tPowerSequenceText) { _, _ in applyIfLive() }
    .onChange(of: ttPowerSequenceText) { _, _ in applyIfLive() }
    .onChange(of: melody) { _, _ in applyIfLive() }
  }

  // MARK: - Sections

  private var tonalitySection: some View {
    Section("Tonality") {
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

  private var progressionSection: some View {
    Section("Progression") {
      Picker("Chord Type", selection: $chordType) {
        ForEach(GeneratorChordType.allCases, id: \.self) { ct in
          Text(ct.displayName).tag(ct)
        }
      }
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
      if motion == .tPowers {
        TextField("T-power sequence (scale steps, comma-separated)", text: $tPowerSequenceText)
          .textFieldStyle(.roundedBorder)
      }
      if motion == .ttPowers {
        TextField("TT-power sequence (semitones, comma-separated)", text: $ttPowerSequenceText)
          .textFieldStyle(.roundedBorder)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text("Beats per Chord: \(Int(beatsPerChord))")
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(value: $beatsPerChord, in: 1...16, step: 1)
      }
    }
  }

  private var melodySection: some View {
    Section("Melody") {
      Picker("Melody", selection: $melody) {
        ForEach(GeneratorMelody.allCases, id: \.self) { choice in
          Text(choice.displayName).tag(choice)
        }
      }
    }
  }

  private var rangeSection: some View {
    Section("Voice Range") {
      Stepper("Bass octave: \(bassOctave)", value: $bassOctave, in: 0...4)
      Stepper("Upper range low: \(upperVoiceLowOctave)", value: $upperVoiceLowOctave, in: 2...5)
      Stepper("Upper range high: \(upperVoiceHighOctave)", value: $upperVoiceHighOctave, in: 3...7)
    }
  }

  private var timingSection: some View {
    Section("Timing") {
      VStack(alignment: .leading, spacing: 2) {
        Text("BPM: \(bpm)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(value: $bpm, in: 0.1...200, step: 0.1)
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

  private static func parsePowerSequence(_ text: String) -> [Int]? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let values = parts.compactMap { Int($0) }
    return values.isEmpty ? nil : values
  }

  private func currentParams() -> GeneratorSyntax {
    GeneratorSyntax(
      rootNote: rootNote,
      scaleType: scaleType,
      motion: motion,
      chordType: chordType,
      bpm: bpm,
      beatsPerChord: beatsPerChord,
      bassOctave: bassOctave,
      upperVoiceLowOctave: upperVoiceLowOctave,
      upperVoiceHighOctave: upperVoiceHighOctave,
      tPowerSequence: Self.parsePowerSequence(tPowerSequenceText),
      ttPowerSequence: Self.parsePowerSequence(ttPowerSequenceText),
      randomSeed: seedLocked ? randomSeed : nil,
      melody: melody == .none ? nil : melody
    )
  }

  private func apply() {
    playbackState.replaceGeneratorPattern(currentParams())
  }

  /// Called from onChange handlers. Always propagates the form state into
  /// SongDocument so the NEXT play() picks it up. If playback is live, also
  /// restart so the edit takes effect immediately.
  private func applyIfLive() {
    apply()
    if playbackState.isPlaying {
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
}

// MARK: - Preview

#Preview {
  let song = SongRef(patternFileName: "table/Aurora Arpeggio.json")
  let doc = SongDocument(song: song)
  NavigationStack {
    GeneratorFormView(params: GeneratorSyntax())
      .environment(doc)
  }
}
