//
//  PatternFormView.swift
//  Orbital
//

import SwiftUI
import Tonic

struct PatternFormView: View {
  @Environment(SongPlaybackState.self) private var playbackState
  let track: TrackInfo

  var body: some View {
    Form {
      noteGeneratorSection
      timingSection
      modulatorsSection
      presetSection
    }
    .navigationTitle(track.patternName)
  }

  // MARK: - Note Generator Section

  @ViewBuilder
  private var noteGeneratorSection: some View {
    Section("Note Generator — \(track.patternSpec.noteGenerator.displayTypeName)") {
      switch track.patternSpec.noteGenerator {
      case .melodic(let scales, let roots, let octaves, let degrees, let ordering):
        melodicContent(scales: scales, roots: roots, octaves: octaves, degrees: degrees, ordering: ordering)
      case .scaleSampler(let scale, let root, let octaves):
        scaleSamplerContent(scale: scale, root: root, octaves: octaves)
      case .chordProgression(let scale, let root, let style):
        chordProgressionContent(scale: scale, root: root, style: style)
      case .fixed(let events):
        fixedContent(events: events)
      case .midiFile(let filename, let trackNum, let loop):
        midiFileContent(filename: filename, track: trackNum, loop: loop)
      }
    }
  }

  // MARK: - Melodic

  @ViewBuilder
  private func melodicContent(
    scales: IteratedListSyntax<String>,
    roots: IteratedListSyntax<String>,
    octaves: IteratedListSyntax<Int>,
    degrees: IteratedListSyntax<Int>,
    ordering: IteratorSyntax?
  ) -> some View {
    DisclosureGroup("Scales") {
      ForEach(Array(scales.candidates.enumerated()), id: \.offset) { _, scaleName in
        HStack {
          Text(NoteGeneratorSyntax.resolveScale(scaleName).description)
          Spacer()
          Text(scaleName)
            .foregroundStyle(.secondary)
        }
      }
      if let emission = scales.emission {
        emissionRow(emission)
      }
    }

    DisclosureGroup("Roots") {
      ForEach(Array(roots.candidates.enumerated()), id: \.offset) { _, rootName in
        Text(rootName)
      }
      if let emission = roots.emission {
        emissionRow(emission)
      }
    }

    DisclosureGroup("Octaves") {
      Text(octaves.candidates.map(String.init).joined(separator: ", "))
        .foregroundStyle(.secondary)
      if let emission = octaves.emission {
        emissionRow(emission)
      }
    }

    DisclosureGroup("Degrees") {
      Text(degrees.candidates.map(String.init).joined(separator: ", "))
        .foregroundStyle(.secondary)
      if let emission = degrees.emission {
        emissionRow(emission)
      }
    }

    if let ordering {
      emissionRow(ordering, label: "Default Ordering")
    }
  }

  // MARK: - Scale Sampler

  @ViewBuilder
  private func scaleSamplerContent(scale: String, root: String, octaves: [Int]?) -> some View {
    LabeledContent("Scale", value: NoteGeneratorSyntax.resolveScale(scale).description)
    LabeledContent("Root", value: root)
    if let octaves {
      LabeledContent("Octaves", value: octaves.map(String.init).joined(separator: ", "))
    }
  }

  // MARK: - Chord Progression

  @ViewBuilder
  private func chordProgressionContent(scale: String, root: String, style: String?) -> some View {
    LabeledContent("Scale", value: NoteGeneratorSyntax.resolveScale(scale).description)
    LabeledContent("Root", value: root)
    if let style {
      LabeledContent("Style", value: style.capitalized)
    }
  }

  // MARK: - Fixed

  @ViewBuilder
  private func fixedContent(events: [ChordSyntax]) -> some View {
    ForEach(Array(events.enumerated()), id: \.offset) { i, chord in
      LabeledContent("Chord \(i + 1)") {
        Text(chord.notes.map { "M\($0.midi)" }.joined(separator: " "))
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - MIDI File

  @ViewBuilder
  private func midiFileContent(filename: String, track: Int?, loop: Bool?) -> some View {
    LabeledContent("File", value: (filename as NSString).lastPathComponent)
    if let track {
      LabeledContent("Track", value: "\(track)")
    }
    LabeledContent("Loop", value: (loop ?? true) ? "Yes" : "No")
  }

  // MARK: - Timing Section

  @ViewBuilder
  private var timingSection: some View {
    Section("Timing") {
      timingRow(label: "Sustain", timing: track.patternSpec.sustain)
      timingRow(label: "Gap", timing: track.patternSpec.gap)
    }
  }

  @ViewBuilder
  private func timingRow(label: String, timing: TimingSyntax?) -> some View {
    switch timing {
    case .fixed(let value):
      LabeledContent(label, value: String(format: "%.2fs fixed", value))
    case .random(let min, let max):
      LabeledContent(label, value: String(format: "%.2f–%.2fs random", min, max))
    case .list(let values):
      LabeledContent(label, value: values.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "s")
    case nil:
      LabeledContent(label, value: "1.00s fixed (default)")
    }
  }

  // MARK: - Modulators Section

  @ViewBuilder
  private var modulatorsSection: some View {
    if let modulators = track.patternSpec.modulators, !modulators.isEmpty {
      Section("Modulators") {
        ForEach(Array(modulators.enumerated()), id: \.offset) { _, mod in
          LabeledContent(mod.target) {
            Text(arrowSummary(mod.arrow))
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func arrowSummary(_ arrow: ArrowSyntax) -> String {
    switch arrow {
    case .rand(let min, let max):
      return String(format: "rand(%.3f–%.3f)", min, max)
    case .exponentialRand(let min, let max):
      return String(format: "expRand(%.3f–%.3f)", min, max)
    case .const(_, let val):
      return String(format: "%.3f", val)
    case .noiseSmoothStep(_, let min, let max):
      return String(format: "noise(%.3f–%.3f)", min, max)
    case .line(_, let min, let max):
      return String(format: "line(%.3f–%.3f)", min, max)
    default:
      return "arrow"
    }
  }

  // MARK: - Preset Section

  @ViewBuilder
  private var presetSection: some View {
    Section("Preset") {
      LabeledContent("Preset File", value: track.patternSpec.presetFilename)
      if let voices = track.patternSpec.numVoices {
        LabeledContent("Voices", value: "\(voices)")
      }
    }
  }

  // MARK: - Helpers

  @ViewBuilder
  private func emissionRow(_ emission: IteratorSyntax, label: String = "Emission") -> some View {
    LabeledContent(label, value: emissionName(emission))
  }

  private func emissionName(_ emission: IteratorSyntax) -> String {
    switch emission {
    case .cyclic: return "Cyclic"
    case .shuffled: return "Shuffled"
    case .random: return "Random"
    case .waiting(let inner, _): return "Waiting (\(emissionName(inner)))"
    }
  }
}
