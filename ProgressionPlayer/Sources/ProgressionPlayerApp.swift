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
  @State private var songLibrary = SongLibrary()
  init() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AppDelegate Debug - Error setting AVAudioSession category. Because of this, there may be no sound. \(error)")
    }
    let engine = SpatialAudioEngine()
    let presetSpec = Bundle.main.decode(PresetSyntax.self, from: "auroraBorealis.json", subdirectory: "presets")
    self.synth = SyntacticSynth(engine: engine, presetSpec: presetSpec)
    self.engine = engine
  }
  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(synth)
        .environment(songLibrary)
    }

    WindowGroup(id: "synth-window") {
      SyntacticSynthView(synth: synth)
    }
  }
}
