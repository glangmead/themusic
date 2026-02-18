//
//  MidiParser.swift
//  ProgressionPlayer
//
//  MIDI file parsing: loads a .mid file into structured note data
//  using AudioToolbox's MusicSequence API.
//

import Foundation
import AudioToolbox

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
            let dataPtr = data.advanced(by: 8).bindMemory(to: UInt8.self, capacity: Int(metaEvent.pointee.dataLength))
            if metaEvent.pointee.dataLength >= 2 {
              let num = dataPtr[0]
              let den = pow(2.0, Double(dataPtr[1]))
              globalMetadata.timeSignature = "\(num)/\(Int(den))"
            }
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
            let dataPtr = data.advanced(by: 8).bindMemory(to: UInt8.self, capacity: Int(metaEvent.pointee.dataLength))
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

// MARK: - MidiEventSequence

/// A pre-parsed MIDI track converted into parallel iterators for notes, sustains, and gaps,
/// ready to feed into MusicPattern.
struct MidiEventSequence {
  let chords: [[MidiNote]]
  let sustains: [CoreFloat]
  let gaps: [CoreFloat]
  
  /// Parse a MIDI file and extract a single track as a sequence of chord events.
  /// Groups simultaneous notes (within a small beat epsilon) into chords.
  /// Converts beat-based timing to seconds using the file's tempo.
  /// - Parameters:
  ///   - url: URL to the .mid file
  ///   - trackIndex: Which track to extract (nil = first track with notes)
  ///   - loop: If true, the iterators cycle; if false, they terminate after one pass
  static func from(url: URL, trackIndex: Int?, loop: Bool) -> MidiEventSequence? {
    guard let parser = MidiParser(url: url) else { return nil }
    
    // Find the requested track
    let tracksWithNotes = parser.tracks.filter { !$0.notes.isEmpty }
    guard !tracksWithNotes.isEmpty else { return nil }
    
    let track: MidiTrackData
    if let idx = trackIndex {
      // trackIndex refers to index among tracks-with-notes
      guard idx < tracksWithNotes.count else { return nil }
      track = tracksWithNotes[idx]
    } else {
      track = tracksWithNotes[0]
    }
    
    guard !track.notes.isEmpty else { return nil }
    
    // Tempo: beats per minute -> seconds per beat
    let bpm = parser.globalMetadata.tempo ?? 120.0
    let secondsPerBeat = 60.0 / bpm
    
    // Sort notes by start time
    let sorted = track.notes.sorted { $0.startBeat < $1.startBeat }
    
    // Group into chords: notes within a small epsilon of each other are simultaneous
    let epsilon = 0.01 // beats
    var chordGroups: [(beat: Double, notes: [MidiNoteEvent])] = []
    
    for note in sorted {
      if let last = chordGroups.last, abs(note.startBeat - last.beat) < epsilon {
        chordGroups[chordGroups.count - 1].notes.append(note)
      } else {
        chordGroups.append((beat: note.startBeat, notes: [note]))
      }
    }
    
    // Convert to MidiNote chords, sustains (max duration in chord), and gaps (time to next chord)
    var chords: [[MidiNote]] = []
    var sustains: [CoreFloat] = []
    var gaps: [CoreFloat] = []
    
    for (i, group) in chordGroups.enumerated() {
      let chord = group.notes.map {
        MidiNote(note: MidiValue($0.pitch), velocity: MidiValue($0.velocity))
      }
      chords.append(chord)
      
      // Sustain: max duration among notes in this chord (in seconds)
      let maxDuration = group.notes.map(\.duration).max() ?? 1.0
      sustains.append(CoreFloat(maxDuration * secondsPerBeat))
      
      // Gap: time from this chord's onset to the next chord's onset (in seconds)
      if i + 1 < chordGroups.count {
        let beatDelta = chordGroups[i + 1].beat - group.beat
        gaps.append(CoreFloat(beatDelta * secondsPerBeat))
      } else {
        // Last chord: gap is the sustain (so play() finishes after the last note rings out)
        gaps.append(CoreFloat(maxDuration * secondsPerBeat))
      }
    }
    
    return MidiEventSequence(chords: chords, sustains: sustains, gaps: gaps)
  }
  
  /// Create iterators suitable for MusicPattern.
  func makeIterators(loop: Bool) -> (
    notes: any IteratorProtocol<[MidiNote]>,
    sustains: any IteratorProtocol<CoreFloat>,
    gaps: any IteratorProtocol<CoreFloat>
  ) {
    if loop {
      return (chords.cyclicIterator(), sustains.cyclicIterator(), gaps.cyclicIterator())
    } else {
      return (chords.makeIterator(), sustains.makeIterator(), gaps.makeIterator())
    }
  }
}
