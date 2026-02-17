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
  @State private var engine = SpatialAudioEngine()
  @State private var songLibrary = SongLibrary()
  init() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AppDelegate Debug - Error setting AVAudioSession category. Because of this, there may be no sound. \(error)")
    }
  }
  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(engine)
        .environment(songLibrary)
    }
  }
}
