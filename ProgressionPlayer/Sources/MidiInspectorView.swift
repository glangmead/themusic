//
//  MidiInspectorView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/6/26.
//

import SwiftUI
import AVFoundation

struct MidiInspectorView: View {
  let midiURL: URL
  @State private var parsedTracks: [MidiTrackData] = []
  @State private var globalMetadata: GlobalMidiMetadata = .init()
  @State private var sequencer: AVAudioSequencer?
  @State private var engine = AVAudioEngine()
  
  var body: some View {
    VStack(spacing: 0) {
      // Global Metadata Header
      VStack(alignment: .leading, spacing: 4) {
        Text(midiURL.lastPathComponent)
          .font(.largeTitle)
        HStack {
          if let timeSig = globalMetadata.timeSignature {
            Text("Time Sig: \(timeSig)")
          }
          if let tempo = globalMetadata.tempo {
            Text(String(format: "Tempo: %.1f BPM", tempo))
          }
          Text("Duration: \(String(format: "%.2f", globalMetadata.duration))s")
        }
        .font(.headline)
        .foregroundStyle(.secondary)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(UIColor.secondarySystemBackground))
      
      // Track List
      List {
        ForEach(parsedTracks) { track in
          VStack(alignment: .leading, spacing: 8) {
            // Track Metadata
            HStack {
              Text(track.name.isEmpty ? "Track \(track.id)" : track.name)
                .font(.subheadline)
                .bold()
              Spacer()
              Text("\(track.notes.count) notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            // Graphical Display
            MidiTrackVisualizer(notes: track.notes, totalDuration: globalMetadata.duration)
              .frame(height: 50)
              .background(.orange.opacity(0.3))
              .clipShape(RoundedRectangle(cornerRadius: 4))
          }
        }
      }
    }
    .task(id: midiURL) {
      loadAndParseMidi()
    }
  }
  
  private func loadAndParseMidi() {
    // 1. Load into AVAudioSequencer
    // Note: In a real app, you might want to share the engine/sequencer
    let seq = AVAudioSequencer(audioEngine: engine)
    do {
      try seq.load(from: midiURL, options: [])
      self.sequencer = seq
      // We don't start playback here, just loaded as requested.
    } catch {
      print("Failed to load into AVAudioSequencer: \(error)")
    }
    
    // 2. Parse for Display using AudioToolbox
    if let parser = MidiParser(url: midiURL) {
      self.parsedTracks = parser.tracks.filter { $0.notes.isNotEmpty }
      self.globalMetadata = parser.globalMetadata
    }
  }
}

// MARK: - Visualizer

struct MidiTrackVisualizer: View {
  let notes: [MidiNoteEvent]
  let totalDuration: Double // in beats
  
  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let height = geometry.size.height
      
      // Normalize pitch to fit height
      let minPitch = notes.map(\.pitch).min() ?? 0
      let maxPitch = notes.map(\.pitch).max() ?? 127
      let pitchRange = CGFloat(max(1, maxPitch - minPitch + 1))
      
      ForEach(notes) { note in
        let x = (note.startBeat / totalDuration) * width
        let w = max(1.0, (note.duration / totalDuration) * width)
        
        // Invert y so higher pitch is higher up
        let normalizedPitch = CGFloat(note.pitch - minPitch) / pitchRange
        let h = max(2.0, height / pitchRange)
        let y = height - (normalizedPitch * height) - h
        
        Rectangle()
          .fill(Theme.gradientLightScreen(100)) // Reusing existing theme
          .frame(width: w, height: h)
          .position(x: x + w/2, y: y + h/2)
      }
    }
  }
}

// Data models and MidiParser are in Sources/Generators/MidiParser.swift

#Preview {
  if let url = Bundle.main.url(forResource: "MSLFSanctus", withExtension: "mid") {
    MidiInspectorView(midiURL: url)
  } else {
    Text("MSLFSanctus.mid not found")
  }
}
