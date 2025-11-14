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
        Tab("Theory", systemImage: "play.circle.fill") {
          TheoryView()
        }
        Tab("Tests", systemImage: "arrow.trianglehead.2.clockwise") {
          SpatialView()
        }
      }
    }
  }
}
