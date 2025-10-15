//
//  TheoryView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/29/25.
//

import AudioKit
import AVFoundation
import CoreMIDI
import SoundpipeAudioKit
import SwiftUI
import Tonic

struct TheoryView: View {
  var engine = AudioEngine()
  var seq = AppleSequencer()
  var seqTrack: MusicTrackManager?
  let mixer = Mixer()
  @State var synth: PolyOscillator
  var instrument: MIDIInstrument?
  @State private var somethingPlaying = false
  @State private var key = Key.C
  private var taskQueue = DispatchQueue(label: "com.langmead.player")
  var chords: [Chord] {
    get {
      key.chords.filter { chord in
        chord.type == .major || chord.type == .minor || chord.type == .dim
      }
      .sorted {
        $0.pitches(octave: 4)[0] < $1.pitches(octave: 4)[0]
      }
    }
  }

  init() {
    let osc = PolyOscillator()
    osc.releaseDuration = 5
    osc.waveform = .square
    self.synth = osc
    self.seq.setTempo(60)
    initInstrument()
    seq.loadMIDIFile("D_Loop_01")
    self.seqTrack = seq.tracks[0]
    self.seq.setGlobalMIDIOutput(self.instrument!.midiIn)
    self.seqTrack?.setMIDIOutput(self.instrument!.midiIn)
    mixer.addInput(self.synth.outputNode)
    self.engine.output = mixer
    try! engine.start()
    self.instrument!.start()
  }
  
  private mutating func initInstrument() {
    let instrument = MIDICallbackInstrument(midiInputName: "Greg's Instrument", callback: { [self] status, note, velocity in
      guard let midiStatus = MIDIStatusType.from(byte: status) else {
        return
      }
      let pitch = Pitch(Int8(note))
      if midiStatus == .noteOn {
        print("noteOn called \(status), \(note), \(velocity)")
        //self.taskQueue.async {
          self.synth.noteOn(pitch)
        //}
      } else if midiStatus == .noteOff {
        //print("noteOff called \(status), \(note), \(velocity)")
        //self.taskQueue.async {
          self.synth.noteOff(pitch)
        //}
      }
    })
    self.instrument = instrument
  }
  
  var body: some View {
    NavigationStack {
      VStack {
        Picker("Key", selection: $key) {
          Text("C").tag(Key.C)
          Text("G").tag(Key.G)
          Text("D").tag(Key.D)
          Text("A").tag(Key.A)
          Text("E").tag(Key.E)
        }.pickerStyle(.segmented)
        Picker("Waveform", selection: $synth.waveform) {
          Text("Sine").tag(HSWaveform.sine)
          Text("Square").tag(HSWaveform.square)
          Text("Saw").tag(HSWaveform.saw)
          Text("Triangle").tag(HSWaveform.triangle)
        }.pickerStyle(.segmented)
        ScrollView {
          ForEach(chords, id: \.self) { chord in
            Button(chord.description) {
              seq.stop()
              seqTrack?.clear()
              seqTrack?.setLength(Duration(beats: 4))
              seq.setLength(Duration(beats: 4))
              chord.pitches(octave: 3).forEach {
                seqTrack?.add(midiNoteData:
                  MIDINoteData(
                    noteNumber: MIDINoteNumber($0.midiNoteNumber),
                    velocity: 128,
                    channel: 1,
                    duration: Duration(beats: 1),
                    position: Duration(beats: 3))
                )}
              seq.rewind()
              seq.play()
//              for pitch in chord.pitches(octave: 2) {
//                instrument!.start(noteNumber: MIDINoteNumber(pitch.midiNoteNumber), velocity: 128, channel: 1)
//                instrument!.stop(noteNumber: MIDINoteNumber(pitch.midiNoteNumber), channel: 1)
//              }
            }
            .frame(maxWidth: .infinity)
            .font(.largeTitle)
          }
        }
        .navigationTitle("Chordata")
      }
    }
  }
}

#Preview {
  TheoryView()
}
