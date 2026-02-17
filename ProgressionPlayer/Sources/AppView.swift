//
//  AppView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

struct AppView: View {
  @Environment(SyntacticSynth.self) private var synth

  var body: some View {
    TabView {
      Tab("Theory", systemImage: "atom") {
        TheoryView()
      }
      Tab("Song", systemImage: "document") {
        SongView()
      }
      Tab("Orbital", systemImage: "circle.grid.3x3") {
        OrbitalView()
      }
    }
    

  }
}

#Preview {
  let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")
  AppView()
    .environment(SyntacticSynth(engine: SpatialAudioEngine(), presetSpec: presetSpec))
    .environment(SongLibrary())
}
