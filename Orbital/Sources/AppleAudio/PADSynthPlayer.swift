//
//  PADSynthPlayer.swift
//  Orbital
//

import AVFAudio
import Foundation

/// Plays PADsynth wavetables for individual notes via noteOn/noteOff.
/// Each active note gets its own AVAudioPlayerNode with a looping wavetable
/// generated at the note's fundamental frequency.
@MainActor @Observable
final class PADSynthPlayer {
  private var audioEngine: AVAudioEngine?
  private var format: AVAudioFormat?
  // Maps MIDI note number to its player node
  private var activeNotes: [UInt8: AVAudioPlayerNode] = [:]
  private var synthEngine: PADSynthEngine?

  func configure(engine: PADSynthEngine) {
    synthEngine = engine
  }

  private func ensureAudioEngine() -> Bool {
    if audioEngine != nil { return true }

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      return false
    }

    let sampleRate = Double(PADSynthEngine.sampleRate)
    guard let fmt = AVAudioFormat(
      standardFormatWithSampleRate: sampleRate, channels: 2
    ) else { return false }

    audioEngine = AVAudioEngine()
    format = fmt
    return true
  }

  /// Starts the engine if not already running. Must be called after at least one
  /// node has been attached and connected.
  private func startEngineIfNeeded() {
    guard let audioEngine, !audioEngine.isRunning else { return }
    do {
      try audioEngine.start()
    } catch {
      // Engine failed to start
    }
  }

  func noteOn(note: UInt8, velocity: UInt8) {
    guard velocity > 0 else {
      noteOff(note: note)
      return
    }
    guard let synthEngine else { return }

    // Stop any existing note at this pitch
    noteOff(note: note)

    guard ensureAudioEngine(),
          let audioEngine,
          let format else { return }

    // Generate wavetable at this note's frequency
    let freq = 440.0 * pow(2.0, (CoreFloat(note) - 69.0) / 12.0)
    let wavetable = synthEngine.generateWavetable(fundamentalHz: freq)
    let n = PADSynthEngine.wavetableSize

    let player = AVAudioPlayerNode()
    audioEngine.attach(player)
    audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)

    // Engine can only start after nodes are connected
    startEngineIfNeeded()

    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: format, frameCapacity: UInt32(n)
    ) else { return }
    buffer.frameLength = UInt32(n)
    guard let leftChannel = buffer.floatChannelData?[0],
          let rightChannel = buffer.floatChannelData?[1] else { return }
    let randomStart = Int.random(in: 0..<n)

    let velScale = Float(velocity) / 127.0
    for i in 0..<n {
      leftChannel[i] = Float(wavetable[(randomStart + i) % n]) * velScale
      rightChannel[i] = Float(wavetable[(randomStart + n / 2 + i) % n]) * velScale
    }

    let capturedBuffer = buffer
    Task.detached { await player.scheduleBuffer(capturedBuffer, at: nil, options: .loops) }
    player.play()

    activeNotes[note] = player
  }

  func noteOff(note: UInt8) {
    guard let player = activeNotes.removeValue(forKey: note) else { return }
    player.stop()
    audioEngine?.detach(player)
  }

  func stopAll() {
    for (note, _) in activeNotes {
      noteOff(note: note)
    }
    audioEngine?.stop()
    audioEngine = nil
    format = nil
  }
}
