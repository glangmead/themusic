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
  var program: Int?
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
        } else if type == kMusicEventType_MIDIChannelMessage, let data = data {
          let msg = data.bindMemory(to: MIDIChannelMessage.self, capacity: 1).pointee
          if (msg.status & 0xF0) == 0xC0 { // program change
            trackData.program = Int(msg.data1)
          }
        } else if type == kMusicEventType_Meta, let data = data {
          let metaEvent = data.bindMemory(to: MIDIMetaEvent.self, capacity: 1)
          if metaEvent.pointee.metaEventType == 0x03 { // Track Name
            let dataPtr = data.advanced(by: 8).bindMemory(to: UInt8.self, capacity: Int(metaEvent.pointee.dataLength))
            let dataBuffer = Data(bytes: dataPtr, count: Int(metaEvent.pointee.dataLength))
            // MIDI track names are ASCII; discard if bytes form non-ASCII UTF-8 (e.g. Chinese glyphs
            // from a misencoded file whose bytes happen to be valid UTF-8).
            if let name = String(data: dataBuffer, encoding: .utf8),
               name.unicodeScalars.allSatisfy({ $0.value < 128 }) {
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
  let program: Int?

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
  static func allTracks(url: URL, loop: Bool, bpmOverride: Double? = nil) -> [(trackIndex: Int, trackName: String, sequence: MidiEventSequence)] {
    guard let parser = MidiParser(url: url, preserveTracks: true) else { return [] }

    let bpm = bpmOverride ?? parser.globalMetadata.tempo ?? 120.0
    let secondsPerBeat = 60.0 / bpm

    let tracksWithNotes = parser.tracks.filter { !$0.notes.isEmpty }
    // Trim any global leading silence: find the earliest note across all tracks so that
    // each track's initial rest is relative to that point, not to absolute beat 0.
    let globalFirstBeat = tracksWithNotes.compactMap { $0.notes.map(\.startBeat).min() }.min() ?? 0

    var results: [(trackIndex: Int, trackName: String, sequence: MidiEventSequence)] = []
    for track in tracksWithNotes {
      let trackFirstBeat = (track.notes.map(\.startBeat).min() ?? 0) - globalFirstBeat
      guard let seq = buildSequence(from: track, secondsPerBeat: secondsPerBeat, initialRestBeats: trackFirstBeat) else { continue }
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

    return MidiEventSequence(chords: chords, sustains: sustains, gaps: gaps, program: track.program)
  }

  /// Compress quiet sections globally across all tracks so they stay synchronized.
  /// Two kinds of quiet section are recognized:
  ///   - "silence": no chord is sounding in any track (overlap count 0).
  ///   - "singleton": exactly one chord is sounding across all tracks (overlap 1).
  /// For each kind, pass a `CoreFloat` max-duration to clamp it, or nil to leave
  /// that kind of region untouched. When both are nil (or no region exceeds its
  /// clamp) the sequences are returned unchanged.
  ///
  /// Within a trimmed singleton region, the sole sustaining chord has its
  /// sustain truncated so the timeline stays consistent. Within a trimmed
  /// silence, nothing is sounding so nothing needs truncating.
  static func compressingQuietSectionsGlobally(
    _ sequences: [MidiEventSequence],
    maxSilence: CoreFloat?,
    maxSingleton: CoreFloat?
  ) -> [MidiEventSequence] {
    guard !sequences.isEmpty else { return sequences }
    guard maxSilence != nil || maxSingleton != nil else { return sequences }

    let intervals = soundingIntervals(in: sequences)
    guard !intervals.isEmpty else { return sequences }

    let trimPoints = quietSectionTrimPoints(
      intervals: intervals, maxSilence: maxSilence, maxSingleton: maxSingleton)
    guard trimPoints.last?.trimmed ?? 0 > 0 else { return sequences }

    return sequences.map { applyTimeWarp($0, trimPoints: trimPoints) }
  }

  /// Build sounding intervals [onset, onset+sustain) across all tracks,
  /// skipping empty chords and zero-sustain events.
  private static func soundingIntervals(
    in sequences: [MidiEventSequence]
  ) -> [(start: CoreFloat, end: CoreFloat)] {
    var intervals: [(start: CoreFloat, end: CoreFloat)] = []
    for seq in sequences {
      var onset: CoreFloat = 0
      for i in seq.gaps.indices {
        if !seq.chords[i].isEmpty && seq.sustains[i] > 0 {
          intervals.append((start: onset, end: onset + seq.sustains[i]))
        }
        onset += seq.gaps[i]
      }
    }
    return intervals
  }

  /// Sweep-line over onset/end events, clamping silence (overlap 0) and
  /// singleton (overlap 1) regions that exceed their max. Returns cumulative
  /// trim breakpoints; each entry says "by this time, `trimmed` seconds have
  /// been removed from the timeline." The first entry is always (0, 0).
  private static func quietSectionTrimPoints(
    intervals: [(start: CoreFloat, end: CoreFloat)],
    maxSilence: CoreFloat?,
    maxSingleton: CoreFloat?
  ) -> [(time: CoreFloat, trimmed: CoreFloat)] {
    // Tie-break +1 before -1 at the same instant so touching intervals don't
    // register a zero-length silence.
    var events: [(time: CoreFloat, delta: Int)] = []
    events.reserveCapacity(intervals.count * 2)
    for iv in intervals {
      events.append((iv.start, +1))
      events.append((iv.end, -1))
    }
    events.sort { left, right in
      if left.time != right.time { return left.time < right.time }
      return left.delta > right.delta
    }

    var overlap = 0
    var cumulativeTrim: CoreFloat = 0
    var trimPoints: [(time: CoreFloat, trimmed: CoreFloat)] = [(time: 0, trimmed: 0)]

    var idx = 0
    while idx < events.count {
      let regionStart = events[idx].time
      while idx < events.count && events[idx].time == regionStart {
        overlap += events[idx].delta
        idx += 1
      }
      guard idx < events.count else { break }
      let regionEnd = events[idx].time
      let duration = regionEnd - regionStart
      guard duration > 0 else { continue }

      let clamp: CoreFloat? = overlap == 0 ? maxSilence : (overlap == 1 ? maxSingleton : nil)
      if let clamp, duration > clamp {
        cumulativeTrim += duration - clamp
        trimPoints.append((time: regionEnd, trimmed: cumulativeTrim))
      }
    }

    return trimPoints
  }

  /// Apply a cumulative-trim time warp to one sequence: warp onsets and
  /// end-times, recompute gaps, adjust each sustain to match its warped end.
  private static func applyTimeWarp(
    _ seq: MidiEventSequence,
    trimPoints: [(time: CoreFloat, trimmed: CoreFloat)]
  ) -> MidiEventSequence {
    func warp(_ t: CoreFloat) -> CoreFloat {
      var trimAtT: CoreFloat = 0
      for point in trimPoints {
        if point.time <= t {
          trimAtT = point.trimmed
        } else {
          break
        }
      }
      return t - trimAtT
    }

    var onsets: [CoreFloat] = []
    var onset: CoreFloat = 0
    for gap in seq.gaps {
      onsets.append(onset)
      onset += gap
    }
    let warpedOnsets = onsets.map { warp($0) }

    var newSustains = seq.sustains
    for i in seq.sustains.indices {
      guard !seq.chords[i].isEmpty && seq.sustains[i] > 0 else { continue }
      let warpedEnd = warp(onsets[i] + seq.sustains[i])
      newSustains[i] = max(0, warpedEnd - warpedOnsets[i])
    }

    var newGaps = seq.gaps
    for i in 0..<(newGaps.count - 1) {
      newGaps[i] = warpedOnsets[i + 1] - warpedOnsets[i]
    }
    // Last gap is the tail-off after the final chord; match its (possibly
    // shortened) sustain so the total timeline stays consistent.
    if !newGaps.isEmpty {
      newGaps[newGaps.count - 1] = newSustains[newSustains.count - 1]
    }

    return MidiEventSequence(
      chords: seq.chords, sustains: newSustains, gaps: newGaps, program: seq.program
    )
  }

  /// Returns the median sustain duration in seconds across all non-silent events.
  /// Silence events (initial rest padding) have sustain == 0 and are excluded.
  func medianSustain() -> CoreFloat? {
    let nonZero = sustains.filter { $0 > 0 }
    guard !nonZero.isEmpty else { return nil }
    let sorted = nonZero.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
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
