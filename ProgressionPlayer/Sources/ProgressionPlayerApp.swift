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
  @State private var engine: SpatialAudioEngine
  @State private var synth: SyntacticSynth
  init() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AppDelegate Debug - Error setting AVAudioSession category. Because of this, there may be no sound. \(error)")
    }
    let engine = SpatialAudioEngine()
    self.synth = SyntacticSynth(engine: engine)
    self.engine = engine
  }
  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(synth)
    }
  }
}
