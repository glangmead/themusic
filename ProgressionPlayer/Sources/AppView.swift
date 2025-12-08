//
//  AppView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

struct AppView: View {
  @Environment(KnobbySynth.self) private var synth

  var body: some View {
    TabView {
      Tab("Theory", systemImage: "atom") {
        TheoryView()
      }
      Tab("Song", systemImage: "document") {
        SongView()
      }
      Tab("Syntax", systemImage: "gear") {
        SyntacticSynthView()
      }
    }

  }
}

#Preview {
  AppView()
    .environment(KnobbySynth())
}
