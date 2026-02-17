//
//  AppView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

struct AppView: View {
  var body: some View {
    TabView {
      Tab("Orbital", systemImage: "circle.grid.3x3") {
        OrbitalView()
      }
      Tab("Theory", systemImage: "atom") {
        TheoryView()
      }
      Tab("Song", systemImage: "document") {
        SongView()
      }
    }
  }
}

#Preview {
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
}
