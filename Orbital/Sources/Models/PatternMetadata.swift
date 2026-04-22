//
//  PatternMetadata.swift
//  Orbital
//

import Foundation

struct PatternMetadata: Sendable, Equatable {
  let kindName: String
  let bpm: Int?
  let duration: TimeInterval?
  let loops: Bool

  var subtitle: String {
    var parts: [String] = [kindName]
    if let bpm { parts.append("\(bpm) BPM") }
    if let duration { parts.append(Self.formatDuration(duration)) }
    if loops { parts.append("Loops") }
    return parts.joined(separator: " • ")
  }

  private static func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let secs = total % 60
    return "\(minutes):\(secs < 10 ? "0" : "")\(secs)"
  }
}

extension PatternMetadata {
  /// Extract metadata from a decoded PatternSyntax. For MIDI patterns, the `.mid`
  /// file is also parsed to recover BPM/duration when not in the JSON.
  static func extract(from spec: PatternSyntax, resourceBaseURL: URL?) -> PatternMetadata {
    if let midi = spec.midiTracks {
      return extractMidi(midi, resourceBaseURL: resourceBaseURL)
    }
    if let score = spec.scoreTracks {
      let durationSeconds = score.totalBeats / score.bpm * 60
      return PatternMetadata(
        kindName: "Procedural harmony",
        bpm: Int(score.bpm.rounded()),
        duration: durationSeconds,
        loops: score.loop ?? true
      )
    }
    if spec.tableTracks != nil {
      return PatternMetadata(kindName: "Advanced procedural", bpm: nil, duration: nil, loops: false)
    }
    if spec.generatorTracks != nil {
      return PatternMetadata(kindName: "Procedural harmony", bpm: nil, duration: nil, loops: true)
    }
    return PatternMetadata(kindName: "Unknown", bpm: nil, duration: nil, loops: false)
  }

  private static func extractMidi(_ midi: MidiTracksSyntax, resourceBaseURL: URL?) -> PatternMetadata {
    var bpm: Double? = midi.bpm
    var durationSeconds: TimeInterval?

    if let url = NoteGeneratorSyntax.midiFileURL(filename: midi.filename, resourceBaseURL: resourceBaseURL),
       let parser = MidiParser(url: url) {
      if bpm == nil { bpm = parser.globalMetadata.tempo }
      let resolvedBpm = bpm ?? parser.globalMetadata.tempo ?? 120.0
      durationSeconds = parser.globalMetadata.duration * 60.0 / resolvedBpm
    }

    return PatternMetadata(
      kindName: "MIDI File",
      bpm: bpm.map { Int($0.rounded()) },
      duration: durationSeconds,
      loops: midi.loop ?? true
    )
  }
}
