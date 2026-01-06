//
//  MidiInspectorView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/6/26.
//

import SwiftUI
import AVFoundation
import AudioToolbox

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
          .font(.headline)
        HStack {
          if let timeSig = globalMetadata.timeSignature {
            Text("Time Sig: \(timeSig)")
          }
          if let tempo = globalMetadata.tempo {
            Text(String(format: "Tempo: %.1f BPM", tempo))
          }
          Text("Duration: \(String(format: "%.2f", globalMetadata.duration))s")
        }
        .font(.caption)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            // Graphical Display
            MidiTrackVisualizer(notes: track.notes, totalDuration: globalMetadata.duration)
              .frame(height: 40)
              .background(Color(UIColor.tertiarySystemBackground))
              .clipShape(RoundedRectangle(cornerRadius: 4))
          }
          .padding(.vertical, 4)
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
      self.parsedTracks = parser.tracks
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
      let pitchRange = CGFloat(max(1, maxPitch - minPitch))
      
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

// MARK: - Data Models

struct GlobalMidiMetadata {
  var timeSignature: String?
  var tempo: Double? // BPM
  var duration: Double = 1.0 // Beats
}

struct MidiTrackData: Identifiable {
  let id: Int
  var name: String = ""
  var notes: [MidiNoteEvent] = []
}

struct MidiNoteEvent: Identifiable {
  let id = UUID()
  let startBeat: Double
  let duration: Double
  let pitch: Int
  let velocity: Int
}

// MARK: - Parser (AudioToolbox)

class MidiParser {
  var tracks: [MidiTrackData] = []
  var globalMetadata = GlobalMidiMetadata()
  
  init?(url: URL) {
    var sequence: MusicSequence?
    var status = NewMusicSequence(&sequence)
    guard status == noErr, let seq = sequence else { return nil }
    
    status = MusicSequenceFileLoad(seq, url as CFURL, .midiType, .smf_ChannelsToTracks)
    guard status == noErr else { return nil }
    
    parseGlobalMetadata(from: seq)
    parseTracks(from: seq)
    
    DisposeMusicSequence(seq)
  }
  
  private func parseGlobalMetadata(from seq: MusicSequence) {
    var tempoTrack: MusicTrack?
    if MusicSequenceGetTempoTrack(seq, &tempoTrack) == noErr, let track = tempoTrack {
      // Get Tempo and Time Sig
      var iterator: MusicEventIterator?
      NewMusicEventIterator(track, &iterator)
      guard let iter = iterator else { return }
      
      var hasNext: DarwinBoolean = true
      while hasNext.boolValue {
        var timestamp: MusicTimeStamp = 0
        var type: MusicEventType = 0
        var data: UnsafeRawPointer?
        var size: UInt32 = 0
        
        MusicEventIteratorGetEventInfo(iter, &timestamp, &type, &data, &size)
        
        if type == kMusicEventType_Meta, let data = data {
          let metaEvent = data.bindMemory(to: MIDIMetaEvent.self, capacity: 1)
          if metaEvent.pointee.metaEventType == 0x58 { // Time Signature
            // 4 bytes: numer, denom (power of 2), clocks per tick, 32nd notes per qtr
            // Access payload by advancing past the 8-byte header (metaEventType, 3 unused, dataLength)
            // Actually, MIDIMetaEvent struct layout is:
            // metaEventType(1), unused1(1), unused2(1), unused3(1), dataLength(4), data(1)
            // So data starts at offset 8.
            let dataPtr = data.advanced(by: 8).bindMemory(to: UInt8.self, capacity: Int(metaEvent.pointee.dataLength))
            
            if metaEvent.pointee.dataLength >= 2 {
              let num = dataPtr[0]
              let den = pow(2.0, Double(dataPtr[1]))
              globalMetadata.timeSignature = "\(num)/\(Int(den))"
            }
          } else if metaEvent.pointee.metaEventType == 0x51 { // Tempo
            // Tempo is microseconds per quarter note
            // But MusicSequence handles tempo events differently usually (ExtendedTempoEvent).
            // However, kMusicEventType_Meta with 0x51 exists too.
          }
        }
        
        if type == kMusicEventType_ExtendedTempo, let data = data {
          let tempoEvent = data.bindMemory(to: ExtendedTempoEvent.self, capacity: 1)
          globalMetadata.tempo = tempoEvent.pointee.bpm
        }
        
        MusicEventIteratorHasNextEvent(iter, &hasNext)
        if hasNext.boolValue { MusicEventIteratorNextEvent(iter) }
      }
      DisposeMusicEventIterator(iter)
    }
    
    // Duration: find max end time of all tracks
    // MusicSequence doesn't give duration directly easily, need to iterate.
  }
  
  private func parseTracks(from seq: MusicSequence) {
    var trackCount: UInt32 = 0
    MusicSequenceGetTrackCount(seq, &trackCount)
    
    var maxTime: Double = 0
    
    for i in 0..<trackCount {
      var musicTrack: MusicTrack?
      MusicSequenceGetIndTrack(seq, i, &musicTrack)
      guard let track = musicTrack else { continue }
      
      var trackData = MidiTrackData(id: Int(i))
      var iterator: MusicEventIterator?
      NewMusicEventIterator(track, &iterator)
      guard let iter = iterator else { continue }
      
      var hasNext: DarwinBoolean = true
      while hasNext.boolValue {
        var timestamp: MusicTimeStamp = 0
        var type: MusicEventType = 0
        var data: UnsafeRawPointer?
        var size: UInt32 = 0
        
        MusicEventIteratorGetEventInfo(iter, &timestamp, &type, &data, &size)
        
        if type == kMusicEventType_MIDINoteMessage, let data = data {
          let noteMsg = data.bindMemory(to: MIDINoteMessage.self, capacity: 1).pointee
          let note = MidiNoteEvent(
            startBeat: Double(timestamp),
            duration: Double(noteMsg.duration),
            pitch: Int(noteMsg.note),
            velocity: Int(noteMsg.velocity)
          )
          trackData.notes.append(note)
          if (Double(timestamp) + Double(noteMsg.duration)) > maxTime {
            maxTime = Double(timestamp) + Double(noteMsg.duration)
          }
        } else if type == kMusicEventType_Meta, let data = data {
          let metaEvent = data.bindMemory(to: MIDIMetaEvent.self, capacity: 1)
          if metaEvent.pointee.metaEventType == 0x03 { // Track Name
            // Parse string
            // Access payload by advancing past the 8-byte header
            let dataPtr = data.advanced(by: 8).bindMemory(to: UInt8.self, capacity: Int(metaEvent.pointee.dataLength))
            
            // Create Data buffer to read
            let dataBuffer = Data(bytes: dataPtr, count: Int(metaEvent.pointee.dataLength))
            if let name = String(data: dataBuffer, encoding: .utf8) {
              trackData.name = name
            }
          }
        }
        
        MusicEventIteratorHasNextEvent(iter, &hasNext)
        if hasNext.boolValue { MusicEventIteratorNextEvent(iter) }
      }
      DisposeMusicEventIterator(iter)
      tracks.append(trackData)
    }
    globalMetadata.duration = max(1.0, maxTime)
  }
}
