//
//  MidiParser.swift
//  Orbital
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

  let loadFlags: MusicSequenceLoadFlags

  init?(url: URL, preserveTracks: Bool = false) {
    self.loadFlags = preserveTracks ? .smf_PreserveTracks : .smf_ChannelsToTracks
    var sequence: MusicSequence?
    var status = NewMusicSequence(&sequence)
    guard status == noErr, let seq = sequence else { return nil }

    status = MusicSequenceFileLoad(seq, url as CFURL, .midiType, loadFlags)
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
  /// Parse a MIDI file and extract a single track as a sequence of chord events.
  /// - Parameters:
  ///   - url: URL to the .mid file
  ///   - trackIndex: Which track to extract (nil = first track with notes)
  ///   - loop: If true, the iterators cycle; if false, they terminate after one pass
  static func from(url: URL, trackIndex: Int?, loop: Bool) -> MidiEventSequence? {
    guard let parser = MidiParser(url: url) else { return nil }

    let tracksWithNotes = parser.tracks.filter { !$0.notes.isEmpty }
    guard !tracksWithNotes.isEmpty else { return nil }

    let track: MidiTrackData
    if let idx = trackIndex {
      guard idx < tracksWithNotes.count else { return nil }
      track = tracksWithNotes[idx]
    } else {
      track = tracksWithNotes[0]
    }

    let bpm = parser.globalMetadata.tempo ?? 120.0
    let secondsPerBeat = 60.0 / bpm
    return buildSequence(from: track, secondsPerBeat: secondsPerBeat)
  }

  /// Parse all nonempty tracks from a MIDI file, returning one MidiEventSequence per track.
  /// Each element includes the track index (among all tracks), the track name, and the sequence.
  static func allTracks(url: URL, loop: Bool) -> [(trackIndex: Int, trackName: String, sequence: MidiEventSequence)] {
    guard let parser = MidiParser(url: url, preserveTracks: true) else { return [] }

    let bpm = parser.globalMetadata.tempo ?? 120.0
    let secondsPerBeat = 60.0 / bpm

    var results: [(trackIndex: Int, trackName: String, sequence: MidiEventSequence)] = []
    for track in parser.tracks {
      guard !track.notes.isEmpty else { continue }
      // Preserve the initial rest so multi-track playback stays aligned
      let firstBeat = track.notes.map(\.startBeat).min() ?? 0
      guard let seq = buildSequence(from: track, secondsPerBeat: secondsPerBeat, initialRestBeats: firstBeat) else { continue }
      results.append((trackIndex: track.id, trackName: track.name, sequence: seq))
    }
    return results
  }

  /// Shared logic: convert a MidiTrackData into a MidiEventSequence.
  /// - Parameters:
  ///   - track: The parsed MIDI track data
  ///   - secondsPerBeat: Tempo conversion factor
  ///   - initialRestBeats: Beats of silence before the first note (used for multi-track
  ///     alignment so each track preserves its original start time relative to beat 0)
  private static func buildSequence(from track: MidiTrackData, secondsPerBeat: Double, initialRestBeats: Double = 0) -> MidiEventSequence? {
    guard !track.notes.isEmpty else { return nil }

    let sorted = track.notes.sorted { $0.startBeat < $1.startBeat }
    let epsilon = 0.01
    var chordGroups: [(beat: Double, notes: [MidiNoteEvent])] = []

    for note in sorted {
      if let last = chordGroups.last, abs(note.startBeat - last.beat) < epsilon {
        chordGroups[chordGroups.count - 1].notes.append(note)
      } else {
        chordGroups.append((beat: note.startBeat, notes: [note]))
      }
    }

    var chords: [[MidiNote]] = []
    var sustains: [CoreFloat] = []
    var gaps: [CoreFloat] = []

    // If there's an initial rest, prepend a silent event so multi-track
    // patterns preserve their original timing offset from beat 0
    if initialRestBeats > epsilon {
      chords.append([])          // empty chord = silence
      sustains.append(0)         // no sound to sustain
      gaps.append(CoreFloat(initialRestBeats * secondsPerBeat))
    }

    for (i, group) in chordGroups.enumerated() {
      let chord = group.notes.map {
        MidiNote(note: MidiValue($0.pitch), velocity: MidiValue($0.velocity))
      }
      chords.append(chord)

      let maxDuration = group.notes.map(\.duration).max() ?? 1.0
      sustains.append(CoreFloat(maxDuration * secondsPerBeat))

      if i + 1 < chordGroups.count {
        let beatDelta = chordGroups[i + 1].beat - group.beat
        gaps.append(CoreFloat(beatDelta * secondsPerBeat))
      } else {
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
