//
//  PADSynthPlayer.swift
//  Orbital
//

import AVFAudio
import Foundation

/// Plays PADsynth wavetables for individual notes via noteOn/noteOff.
/// Wavetables for the visible keyboard range are pre-generated and cached.
/// Call `invalidateCache()` when engine parameters change.
@MainActor @Observable
final class PADSynthPlayer {
  private var audioEngine: AVAudioEngine?
  private var format: AVAudioFormat?
  private var activeNotes: [UInt8: AVAudioPlayerNode] = [:]
  private var synthEngine: PADSynthEngine?

  // Wavetable cache: MIDI note number -> pre-generated stereo buffer
  private var cachedBuffers: [UInt8: AVAudioPCMBuffer] = [:]
  private var cacheTask: Task<Void, Never>?
  var isCaching = false

  // Keyboard range (C3=48 to C6=84)
  static let keyboardLow: UInt8 = 48
  static let keyboardHigh: UInt8 = 84

  func configure(engine: PADSynthEngine) {
    synthEngine = engine
    invalidateCache()
  }

  /// Invalidate all cached wavetables and regenerate on a background thread.
  func invalidateCache() {
    cacheTask?.cancel()
    cachedBuffers.removeAll()
    guard let synthEngine else { return }

    isCaching = true
    let baseParams = synthEngine.currentParams()
    let selectedInstrument = synthEngine.selectedInstrument

    cacheTask = Task {
      // Generate all wavetables off the main thread
      let tables = await Task.detached(priority: .userInitiated) {
        var result: [UInt8: [CoreFloat]] = [:]
        for note in Self.keyboardLow...Self.keyboardHigh {
          if Task.isCancelled { return result }
          let freq = 440.0 * pow(2.0, (CoreFloat(note) - 69.0) / 12.0)
          let sharcHarmonics = PADSynthEngine.resolveSharcHarmonics(
            instrumentId: selectedInstrument, midiNote: note
          )
          let noteParams = PADSynthEngine.ParamSnapshot(
            baseShape: baseParams.baseShape, tilt: baseParams.tilt,
            bandwidthCents: baseParams.bandwidthCents, bwScale: baseParams.bwScale,
            profileShape: baseParams.profileShape, stretch: baseParams.stretch,
            envelopeCoefficients: baseParams.envelopeCoefficients,
            sharcHarmonics: sharcHarmonics
          )
          let wavetable = PADSynthEngine.generateWavetableStatic(
            fundamentalHz: freq, params: noteParams
          )
          result[note] = wavetable
        }
        return result
      }.value

      guard !Task.isCancelled else { return }

      // Build AVAudioPCMBuffers on MainActor
      guard ensureAudioEngine(), let format else {
        isCaching = false
        return
      }
      let n = PADSynthEngine.wavetableSize

      for (note, wavetable) in tables {
        guard !Task.isCancelled else { break }
        guard let buffer = AVAudioPCMBuffer(
          pcmFormat: format, frameCapacity: UInt32(n)
        ) else { continue }
        buffer.frameLength = UInt32(n)
        guard let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else { continue }
        let randomStart = Int.random(in: 0..<n)

        for i in 0..<n {
          left[i] = Float(wavetable[(randomStart + i) % n])
          right[i] = Float(wavetable[(randomStart + n / 2 + i) % n])
        }
        cachedBuffers[note] = buffer
      }

      isCaching = false
    }
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

    noteOff(note: note)

    guard ensureAudioEngine(),
          let audioEngine,
          let format else { return }

    // Use cached buffer if available, otherwise generate on the fly
    let buffer: AVAudioPCMBuffer
    if let cached = cachedBuffers[note] {
      buffer = cached
    } else {
      guard let synthEngine else { return }
      let freq = 440.0 * pow(2.0, (CoreFloat(note) - 69.0) / 12.0)
      let noteParams = synthEngine.paramsForNote(midiNote: note)
      let wavetable = PADSynthEngine.generateWavetableStatic(
        fundamentalHz: freq, params: noteParams
      )
      let n = PADSynthEngine.wavetableSize

      guard let buf = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: UInt32(n)
      ) else { return }
      buf.frameLength = UInt32(n)
      guard let left = buf.floatChannelData?[0],
            let right = buf.floatChannelData?[1] else { return }
      let randomStart = Int.random(in: 0..<n)

      for i in 0..<n {
        left[i] = Float(wavetable[(randomStart + i) % n])
        right[i] = Float(wavetable[(randomStart + n / 2 + i) % n])
      }
      buffer = buf
    }

    let player = AVAudioPlayerNode()
    audioEngine.attach(player)
    audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
    startEngineIfNeeded()

    let velScale = Float(velocity) / 127.0
    player.volume = velScale

    Task.detached { await player.scheduleBuffer(buffer, at: nil, options: .loops) }
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
