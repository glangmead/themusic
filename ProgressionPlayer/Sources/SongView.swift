//
//  SongView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/28/25.
//

import SwiftUI

struct SongView: View {
  @Environment(SyntacticSynth.self) private var synth
  @State private var seq: Sequencer?
  @State private var error: Error? = nil
  @State private var isImporting = false
  @State private var songURL: URL?
  @State private var playbackRate: Float = 1.0
  @State private var isShowingSynth = false

  var body: some View {
    NavigationStack {
      Text("Song: \(songURL?.lastPathComponent ?? "none")")
      Text("Playback speed: \(seq?.avSeq.rate ?? 0)")
      Slider(value: $playbackRate, in: 0...20)
        .onChange(of: playbackRate, initial: true) {
          seq?.avSeq.rate = playbackRate
        }
      Text("\(seq?.sequencerTime ?? 0.0) (\(seq?.lengthinSeconds() ?? 0.0))")
        .navigationTitle("⌘Scape")
        .toolbar {
          ToolbarItem() {
            Button("Synth") {
              isShowingSynth = true
            }
          }
          ToolbarItem() {
            Button {
              isImporting = true
            } label: {
              Label("Import file",
                    systemImage: "square.and.arrow.down")
            }
          }
        }
        .fileImporter(
          isPresented: $isImporting,
          allowedContentTypes: [.midi],
          allowsMultipleSelection: false
        ) { result in
          switch result {
          case .success(let urls):
            seq?.playURL(url: urls[0])
            songURL = urls[0]
          case .failure(let error):
            print("\(error.localizedDescription)")
          }
        }
      ForEach(["D_Loop_01", "MSLFSanctus", "All-My-Loving"], id: \.self) { song in
        Button("Play \(song)") {
          songURL = Bundle.main.url(forResource: song, withExtension: "mid")
          seq?.playURL(url: songURL!)
        }
      }
      Button("Stop") {
        seq?.stop()
      }
      Button("Rewind") {
        seq?.stop()
        seq?.rewind()
      }
    }
    .onAppear {
      if seq == nil {
        seq = Sequencer(synth: synth, numTracks: 2)
        try! synth.engine.start()
      }
    }
    .sheet(isPresented: $isShowingSynth) {
      SyntacticSynthView(synth: synth)
    }
  }
}

#Preview {
  SongView()
    .environment(SyntacticSynth())
}
