//
//  Sequencer.swift
//  Orbital
//
//  Created by Greg Langmead on 10/27/25.
//

import AudioKit
import AVFoundation
import Tonic
import SwiftUI

@MainActor @Observable
class Sequencer {
  var avSeq: AVAudioSequencer!
  var avEngine: AVAudioEngine!
  var avTracks: [AVMusicTrack] {
    avSeq.tracks
  }
  var sequencerTime: TimeInterval {
    avSeq.currentPositionInSeconds
  }

  // Per-track MIDI listeners for routing tracks to different NoteHandlers
  private var trackListeners: [Int: MIDICallbackInstrument] = [:]
  private var defaultListener: MIDICallbackInstrument?

  init(engine: AVAudioEngine, numTracks: Int, defaultHandler: NoteHandler) {
    avEngine = engine
    avSeq = AVAudioSequencer(audioEngine: engine)

    avSeq.rate = 0.5
    for _ in 0..<numTracks {
      avSeq?.createAndAppendTrack()
    }
    defaultListener = createListener(for: defaultHandler)
  }

  convenience init(synth: SyntacticSynth, numTracks: Int) {
    self.init(engine: synth.engine.audioEngine, numTracks: numTracks, defaultHandler: synth.noteHandler!)
  }

  /// Assign a specific NoteHandler to a track. Events on this track will be
  /// routed to the given handler instead of the default.
  func setHandler(_ handler: NoteHandler, forTrack trackIndex: Int) {
    trackListeners[trackIndex] = createListener(for: handler)
  }

  /// Create a MIDICallbackInstrument that forwards MIDI events to a NoteHandler.
  private func createListener(for handler: NoteHandler) -> MIDICallbackInstrument {
    // borrowing AudioKit's MIDICallbackInstrument, which has some pretty tough
    // incantations to allocate a midi endpoint and its MIDIEndpointRef
    MIDICallbackInstrument(midiInputName: "Scape Virtual MIDI Listener", callback: { status, note, velocity in
      guard let midiStatus = MIDIStatusType.from(byte: status) else {
        return
      }
      if midiStatus == .noteOn {
        if velocity == 0 {
          handler.noteOff(MidiNote(note: note, velocity: velocity))
        } else {
          handler.noteOn(MidiNote(note: note, velocity: velocity))
        }
      } else if midiStatus == .noteOff {
        handler.noteOff(MidiNote(note: note, velocity: velocity))
      }
    })
  }

  // e.g. Bundle.main.path(forResource: "MSLFSanctus", ofType: "mid")!
  func playURL(url: URL) {
    do {
      stop()
      rewind()
      try avSeq?.load(from: url, options: [])
      play()
    } catch {
      print("\(error.localizedDescription)")
    }
  }

  func play() {
    if !avSeq.isPlaying {
      for (i, track) in avSeq.tracks.enumerated() {
        let listener = trackListeners[i] ?? defaultListener
        // kAudioToolboxErr_InvalidPlayerState -10852
        track.destinationMIDIEndpoint = listener!.midiIn
      }
      // kAudioToolboxError_NoTrackDestination -66720
      avSeq.prepareToPlay()
      try! avSeq.start()
    }
  }

  func stop() {
    avSeq.stop()
  }

  func rewind() {
    avSeq.currentPositionInBeats = 0
  }

  func clear() {
    for track in avTracks {
      track.clear()
    }
  }

  func lengthinSeconds() -> Double {
    avTracks.map({$0.lengthInSeconds}).max() ?? 0
  }

  func sendTonicChord(chord: Chord, octave: Int) {
    sendChord(chord: chord.notes(octave: octave).map {MidiValue($0.pitch.midiNoteNumber)})
  }

  func sendChord(chord: [MidiValue]) {
    let seqTrack = avTracks[0]
    // AVMusicTimeStamp: a fractional number of beats
    for note in chord {
      seqTrack.addEvent(
        AVMIDINoteEvent(
          channel: 0,
          key: UInt32(note),
          velocity: 100,
          duration: 8
        ),
        at: avSeq.currentPositionInBeats + 1
      )
      //      seqTrack.addEvent(
      //        AVMIDINoteEvent(
      //          channel: 0,
      //          key: UInt32(note),
      //          velocity: 100,
      //          duration: 4
      //        ),
      //        at: avSeq.currentPositionInBeats + 1 + Double(i)
      //      )
      //      seqTrack.addEvent(
      //        AVMIDINoteEvent(
      //          channel: 0,
      //          key: UInt32(note),
      //          velocity: 100,
      //          duration: 4
      //        ),
      //        at: avSeq.currentPositionInBeats + 1 + Double(i + chord.count)
      //      )
    }
  }
}

extension AVMusicTrack {
  func clear() {
    if lengthInBeats > 0 {
      // AVAudioSessionErrorCodeBadParam -50
      clearEvents(in: AVBeatRange(start: 0, length: lengthInBeats))
    }
  }
}
