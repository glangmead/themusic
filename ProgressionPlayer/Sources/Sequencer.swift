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
  var loadExternalMidi = false
  
  private var taskQueue = DispatchQueue(label: "scape.midi")
  
  init(engine: AVAudioEngine, numTracks: Int, sourceNode: NoteHandler) {
    avSeq = AVAudioSequencer(audioEngine: engine)
    if loadExternalMidi {
      try! avSeq.load(from: Bundle.main.url(forResource: "D_Loop_01", withExtension: "mid")!)
    } else {
      for _ in 0..<numTracks {
        avTracks.append(avSeq.createAndAppendTrack())
      }
    }
    // borrowing AudioKit's MIDICallbackInstrument, which has some pretty tough incantations to allocate a midi endpoint and its MIDIEndpointRef
    seqListener = MIDICallbackInstrument(midiInputName: "Scape Virtual MIDI Listener", callback: { [self] status, note, velocity in
      print("Callback instrument was pinged with \(status) \(note) \(velocity)")
      /// We are supposed to make this very performant, hence launching things on the main thread
      guard let midiStatus = MIDIStatusType.from(byte: status) else {
        return
      }
      if midiStatus == .noteOn {
        self.taskQueue.async {
          sourceNode.noteOn(MidiNote(note: note, velocity: velocity))
        }
      } else if midiStatus == .noteOff {
        self.taskQueue.async {
          sourceNode.noteOff(MidiNote(note: note, velocity: velocity))
        }
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
  
  func sendChord(chord: [MidiValue]) {
    avSeq.stop()
    avSeq.currentPositionInBeats = 0
    if !loadExternalMidi {
      let seqTrack = avTracks[0]
      seqTrack.lengthInBeats = 8
      // AVMusicTimeStamp: a fractional number of beats
      for note in chord {
        seqTrack.addEvent(AVMIDINoteEvent(channel: 0, key: UInt32(note), velocity: 100, duration: 8), at: 0)
      }
    }
    play()
  }
}
