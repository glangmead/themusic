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
  @Environment(\.scenePhase) private var scenePhase
  
  init() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay])
      // Request a larger I/O buffer to reduce the chance of audio glitches.
      // Default is ~5ms; 20ms gives the render thread more headroom at the
      // cost of slightly higher latency (inaudible for non-interactive playback).
      try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.02)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
          engine.fadeOutAndStop()
        }
    }
  }
}
