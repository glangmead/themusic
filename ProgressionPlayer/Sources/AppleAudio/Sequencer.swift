//
//  Sequencer.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/27/25.
//

import AudioKit
import AVFoundation
import Tonic
import SwiftUI

@Observable
class Sequencer {
  var avSeq: AVAudioSequencer!
  var avEngine: AVAudioEngine!
  var avTracks: [AVMusicTrack] {
    avSeq.tracks
  }
  var seqListener: MIDICallbackInstrument?
  var sequencerTime: TimeInterval {
    avSeq.currentPositionInSeconds
  }
  
  init(engine: AVAudioEngine, numTracks: Int, sourceNode: NoteHandler) {
    avEngine = engine
    avSeq = AVAudioSequencer(audioEngine: engine)
    
    avSeq.rate = 0.5
    for _ in 0..<numTracks {
      avSeq?.createAndAppendTrack()
    }
    // borrowing AudioKit's MIDICallbackInstrument, which has some pretty tough incantations to allocate a midi endpoint and its MIDIEndpointRef
    seqListener = MIDICallbackInstrument(midiInputName: "Scape Virtual MIDI Listener", callback: { /*[self]*/ status, note, velocity in
      //print("Callback instrument was pinged with \(status) \(note) \(velocity)")
      guard let midiStatus = MIDIStatusType.from(byte: status) else {
        return
      }
      if midiStatus == .noteOn {
        if velocity == 0 {
          sourceNode.noteOff(MidiNote(note: note, velocity: velocity))
        } else {
          sourceNode.noteOn(MidiNote(note: note, velocity: velocity))
        }
      } else if midiStatus == .noteOff {
        sourceNode.noteOff(MidiNote(note: note, velocity: velocity))
      }
      
    })
  }
  
  convenience init(synth: EngineAndVoicePool, numTracks: Int) {
    self.init(engine: synth.engine.audioEngine, numTracks: numTracks, sourceNode: synth.voicePool!)
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
    // avSeq.rate = 2.0 // The default playback rate is 1.0, and must be greater than 0.0.
    if !avSeq.isPlaying {
      for track in avSeq.tracks {
        // kAudioToolboxErr_InvalidPlayerState -10852
        track.destinationMIDIEndpoint = seqListener!.midiIn
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
    sendChord(chord: chord.notes(octave: octave).map {MidiValue($0.pitch.midiNoteNumber)} )
  }
  
  func sendChord(chord: [MidiValue]) {
    let seqTrack = avTracks[0]
    // AVMusicTimeStamp: a fractional number of beats
    for note in chord {
      seqTrack.addEvent(AVMIDINoteEvent(channel: 0, key: UInt32(note), velocity: 100, duration: 8), at: avSeq.currentPositionInBeats + 1)
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
