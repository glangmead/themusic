//
//  SongView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/28/25.
//

import SwiftUI

struct SongView: View {
  @State private var error: Error? = nil
  @State private var isImporting = false
  @State private var seq: Sequencer

  init() {
    seq = Sequencer(synth: KnobbySynth(), numTracks: 2)
  }
  
  var body: some View {
    NavigationStack {
      Text("Playback speed: \(seq.avSeq.rate)")
      Slider(value: $seq.avSeq.rate, in: 0...20)
      Text("\(seq.sequencerTime) (\(seq.lengthinSeconds()))")
        .navigationTitle("⌘Scape")
        .toolbar {
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
            seq.playURL(url: urls[0])
          case .failure(let error):
            print("\(error.localizedDescription)")
          }
        }
    }
  }
}

#Preview {
  SongView()
}
