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
  @State private var resourceManager = ResourceManager()
  @State private var classicsCatalog = ClassicsCatalogLibrary()
  // Ledger starts with a placeholder; reassigned after ResourceManager resolves iCloud.
  @State private var midiLedger = MIDIDownloadLedger(
    baseDirectory: URL.documentsDirectory.appending(path: "midi_downloads")
  )
  @State private var midiDownloadManager: MIDIDownloadManager?
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
        .environment(resourceManager)
        .environment(classicsCatalog)
        .environment(midiLedger)
        .environment(midiDownloadManager ?? MIDIDownloadManager(ledger: midiLedger))
        .task {
          WavetableLibrary.loadAllCuratedTables()
          await resourceManager.setup()
          PatternStorage.resourceBaseURL = resourceManager.resourceBaseURL
          songLibrary.startMonitoring(
            baseURL: resourceManager.resourceBaseURL,
            isICloud: resourceManager.isUsingICloud
          )
          classicsCatalog.load()
          // Point the ledger at the same base directory ResourceManager resolved
          // (iCloud Documents or local fallback), not the app sandbox.
          if let baseURL = resourceManager.resourceBaseURL {
            let downloadsDir = baseURL.appending(path: "midi_downloads")
            midiLedger = MIDIDownloadLedger(baseDirectory: downloadsDir)
          }
          try? FileManager.default.createDirectory(
            at: midiLedger.baseDirectory, withIntermediateDirectories: true
          )
          midiLedger.load()
          midiDownloadManager = MIDIDownloadManager(ledger: midiLedger)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
          engine.fadeOutAndStop()
        }
    }
  }
}
