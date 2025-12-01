//
//  ProgressionPlayerApp.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 9/9/25.
//

import AVFoundation
import SwiftUI

@main
struct ProgressionPlayerApp: App {
  @State private var synth = KnobbySynth()
  init() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AppDelegate Debug - Error setting AVAudioSession category. Because of this, there may be no sound. \(error)")
    }
  }
  var body: some Scene {
    WindowGroup {
      TabView {
        Tab("Theory", systemImage: "atom") {
          TheoryView()
            .environment(synth)
        }
        Tab("Song", systemImage: "document") {
          SongView()
            .environment(synth)
        }
      }
    }
  }
}
