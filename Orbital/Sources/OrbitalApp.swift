//
//  OrbitalApp.swift
//  Orbital
//
//  Created by Greg Langmead on 9/9/25.
//

import AVFoundation
import SwiftUI
import UIKit

@main
struct OrbitalApp: App {
  @State private var engine = SpatialAudioEngine()
  @State private var songLibrary = SongLibrary()
  @Environment(\.scenePhase) private var scenePhase
  
  init() {
    // Opt-in to Swift Observation for AVPlayer and related types.
    AVPlayer.isObservationEnabled = true

    do {
      // NOTE, any of these options seems to cause audio to stop on device lock:
      // options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay]
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      // Request a larger I/O buffer to reduce the chance of audio glitches.
      // Default is ~5ms; 20ms gives the render thread more headroom at the
      // cost of slightly higher latency (inaudible for non-interactive playback).
      try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.02)
      try AVAudioSession.sharedInstance().setActive(true)
      // Tell iOS this app is the "now playing" app and should receive remote
      // control events (lock screen, Control Center, headphone buttons).
      // Without this call, iOS may not keep the audio render thread alive
      // when the app is in the background.
      UIApplication.shared.beginReceivingRemoteControlEvents()
    } catch {
      print("AppDelegate Debug - Error setting AVAudioSession category. Because of this, there may be no sound. \(error)")
    }
  }
  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(engine)
        .environment(songLibrary)
        .tint(.primary)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
          engine.fadeOutAndStop()
        }
    }
  }
}
