//
//  Sequencer.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/27/25.
//

import AudioKit
import AVFoundation
import Tonic

struct Sequencer {
  var avSeq: AVAudioSequencer
  var avTracks = [AVMusicTrack]()
  var seqListener: MIDICallbackInstrument?
  
  init(engine: AVAudioEngine, numTracks: Int, sourceNode: NoteHandler) {
    avSeq = AVAudioSequencer(audioEngine: engine)
    avSeq.rate = 0.5
    for _ in 0..<numTracks {
      avTracks.append(avSeq.createAndAppendTrack())
    }
    // borrowing AudioKit's MIDICallbackInstrument, which has some pretty tough incantations to allocate a midi endpoint and its MIDIEndpointRef
    seqListener = MIDICallbackInstrument(midiInputName: "Scape Virtual MIDI Listener", callback: { /*[self]*/ status, note, velocity in
      //print("Callback instrument was pinged with \(status) \(note) \(velocity)")
      guard let midiStatus = MIDIStatusType.from(byte: status) else {
        return
      }
      if midiStatus == .noteOn {
        sourceNode.noteOn(MidiNote(note: note, velocity: velocity))
      } else if midiStatus == .noteOff {
        sourceNode.noteOff(MidiNote(note: note, velocity: velocity))
      }
      
    })
    for track in avSeq.tracks {
      track.destinationMIDIEndpoint = seqListener!.midiIn
    }
  }
  
  func play() {
    avSeq.prepareToPlay()
    // kAudioToolboxError_NoTrackDestination -66720
    try! avSeq.start()
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
  
  func sendTonicChord(chord: Chord, octave: Int) {
    sendChord(chord: chord.notes(octave: octave).map {MidiValue($0.pitch.midiNoteNumber)} )
  }
  
  func sendChord(chord: [MidiValue]) {
    let seqTrack = avTracks[0]
    // AVMusicTimeStamp: a fractional number of beats
    for note in chord {
      seqTrack.addEvent(AVMIDINoteEvent(channel: 0, key: UInt32(note), velocity: 100, duration: 24), at: avSeq.currentPositionInBeats + 1)
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
