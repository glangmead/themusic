//
//  SpatialAudioEngine.swift
//  Orbital
//
//  Created by Greg Langmead on 11/8/25.
//

import AVFAudio
import AudioToolbox
import Observation
import os

@Observable
// `@unchecked Sendable`: SpatialAudioEngine is a long-lived, shared audio
// graph wrapper. Its stored properties are either immutable after start()
// or synchronized via OSAllocatedUnfairLock / AVAudioEngine's own internal
// locking. Compile/playback code legitimately passes the engine reference
// across isolation domains (e.g. @MainActor compile to nonisolated async
// SpatialPreset init) without mutating shared state concurrently.
class SpatialAudioEngine: @unchecked Sendable {
  let audioEngine = AVAudioEngine()
  let envNode = AVAudioEnvironmentNode()
  let stereo: AVAudioFormat
  let mono: AVAudioFormat

  let spatialEnabled: Bool

  /// AVAudioUnitEffect wrapping a DynamicsProcessor, installed at start() as
  /// the last node before outputNode when AudioSafety.tailLimiterEnabled.
  /// nil when the limiter isn't installed. Detached on stop()/restart().
  private var tailLimiterNode: AVAudioUnitEffect?

  /// Weak-ref registry of SpatialPresets so the dynamic-gain tick can ask
  /// each one for its open-gate count. See register(_:)/unregister(_:).
  private struct SpatialPresetRef { weak var ref: SpatialPreset? }
  private let registryLock = OSAllocatedUnfairLock<[SpatialPresetRef]>(initialState: [])

  /// Detached task that reads the open-gate count and writes
  /// envNode.outputVolume. Runs only while the engine is started and
  /// AudioSafetyRuntime.dynamicGainEnabled is true.
  private var gainPumpTask: Task<Void, Never>?

  /// Absolute start time of the active duck, or nil when not ducking.
  /// Read/written from the gain pump; writes also come from duck().
  private let duckStart = OSAllocatedUnfairLock<CFAbsoluteTime?>(initialState: nil)
  /// How long to hold at zero before the fade begins, and total duck length.
  private let duckShape = OSAllocatedUnfairLock<(hold: Double, total: Double)>(
    initialState: (hold: 0.30, total: 1.0)
  )

  init(spatialEnabled: Bool = true) {
    self.spatialEnabled = spatialEnabled
    if spatialEnabled { audioEngine.attach(envNode) }
    stereo = AVAudioFormat(standardFormatWithSampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 2)!
    mono = AVAudioFormat(standardFormatWithSampleRate: audioEngine.outputNode.inputFormat(forBus: 0).sampleRate, channels: 1)!
  }

  // We grab the system's sample rate directly from the output node
  // to ensure our oscillator runs at the correct speed for the hardware.
  var sampleRate: Double {
    audioEngine.outputNode.inputFormat(forBus: 0).sampleRate
  }

  func attach(_ nodes: [AVAudioNode]) {
    for node in nodes {
      audioEngine.attach(node)
    }
  }

  func detach(_ nodes: [AVAudioNode]) {
    for node in nodes where node.engine === audioEngine {
      audioEngine.detach(node)
    }
  }

  func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {
    audioEngine.connect(node1, to: node2, format: format)
  }

  func connectToEnvNode(_ nodes: [AVAudioMixerNode]) {
    if spatialEnabled {
      for node in nodes {
        node.renderingAlgorithm = .auto
        node.pointSourceInHeadMode = .mono
        node.sourceMode = .spatializeIfMono
        audioEngine.connect(node, to: envNode, format: mono)
      }
      // Tail (envNode → [limiter?] → outputNode) is wired once in start().
    } else {
      // Non-spatial: connect directly to mainMixerNode for flat stereo.
      // mainMixerNode → outputNode is auto-wired by AVAudioEngine; tail
      // limiter is currently only inserted in the spatial path.
      for node in nodes {
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: stereo)
      }
    }
  }

  // MARK: - SpatialPreset registry (for dynamic-gain tick)

  func register(_ sp: SpatialPreset) {
    registryLock.withLock { refs in
      refs.removeAll { $0.ref == nil }
      refs.append(SpatialPresetRef(ref: sp))
    }
  }

  func unregister(_ sp: SpatialPreset) {
    registryLock.withLock { refs in
      refs.removeAll { $0.ref == nil || $0.ref === sp }
    }
  }

  private func openGateCount() -> Int {
    registryLock.withLock { refs in
      refs.reduce(into: 0) { count, wr in
        guard let sp = wr.ref else { return }
        count += sp.openGateCount
      }
    }
  }

  // MARK: - Tail safety chain

  /// Wire the tail chain envNode → [limiter?] → outputNode once per engine
  /// start. Non-spatial mode relies on AVAudioEngine's implicit
  /// mainMixerNode → outputNode connection and skips the limiter entirely.
  ///
  /// Detaching a live limiter requires first disconnecting both of its ends,
  /// otherwise AVFoundation raises `!nodeMixerConns.empty() &&
  /// !hasDirectConnToIONode`. Callers guarantee this runs only while the
  /// engine is stopped.
  private func wireTailIfNeeded() {
    guard spatialEnabled else { return }

    if let old = tailLimiterNode {
      audioEngine.disconnectNodeOutput(old)
      audioEngine.disconnectNodeInput(old)
      audioEngine.detach(old)
      tailLimiterNode = nil
    }
    audioEngine.disconnectNodeOutput(envNode)

    if AudioSafetyRuntime.tailLimiterEnabled {
      let limiter = Self.makeDynamicsProcessor(thresholdDB: AudioSafetyRuntime.tailLimiterThresholdDB)
      audioEngine.attach(limiter)
      audioEngine.connect(envNode, to: limiter, format: stereo)
      audioEngine.connect(limiter, to: audioEngine.outputNode, format: stereo)
      tailLimiterNode = limiter
    } else {
      audioEngine.connect(envNode, to: audioEngine.outputNode, format: stereo)
    }
  }

  private static func makeDynamicsProcessor(thresholdDB: Float) -> AVAudioUnitEffect {
    var desc = AudioComponentDescription()
    desc.componentType = kAudioUnitType_Effect
    desc.componentSubType = kAudioUnitSubType_DynamicsProcessor
    desc.componentManufacturer = kAudioUnitManufacturer_Apple
    desc.componentFlags = 0
    desc.componentFlagsMask = 0
    let unit = AVAudioUnitEffect(audioComponentDescription: desc)

    // Brick-wall configuration: threshold near 0 dBFS, no makeup gain, fast
    // attack, short release. headRoom defines the knee above threshold.
    if let tree = unit.auAudioUnit.parameterTree {
      for p in tree.allParameters {
        switch p.address {
        case AUParameterAddress(kDynamicsProcessorParam_Threshold):   p.value = thresholdDB
        case AUParameterAddress(kDynamicsProcessorParam_HeadRoom):    p.value = 5.0
        case AUParameterAddress(kDynamicsProcessorParam_OverallGain): p.value = 0.0
        case AUParameterAddress(kDynamicsProcessorParam_AttackTime):  p.value = 0.002
        case AUParameterAddress(kDynamicsProcessorParam_ReleaseTime): p.value = 0.050
        default: break
        }
      }
    }
    return unit
  }

  func start() throws {
    if spatialEnabled {
      envNode.outputType = .auto
      envNode.isListenerHeadTrackingEnabled = true
      envNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
      envNode.distanceAttenuationParameters.referenceDistance = 5.0
      envNode.distanceAttenuationParameters.maximumDistance = 50.0
      // envNode.distanceAttenuationParameters.rolloffFactor = 2.0
      envNode.reverbParameters.enable = false
      envNode.reverbParameters.level = 60
      envNode.reverbParameters.loadFactoryReverbPreset(.largeHall)

      // envNode.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: 0.0, y: -1.0, z: 1.0), up: AVAudio3DVector(x: 0.0, y: 0.0, z: 1.0))

      envNode.outputVolume = staticBaseGain()
    } else {
      audioEngine.mainMixerNode.outputVolume = staticBaseGain()
    }

    // Ensure the tail (envNode/mainMixer → [limiter?] → output) is wired with
    // the current AudioSafety.tailLimiterEnabled value. Limiter insertion
    // takes effect at this point only (next-start policy).
    wireTailIfNeeded()

    // Prevent the engine from auto-stopping when the app is backgrounded
    // or during brief silence. Required for background audio to continue.
    audioEngine.isAutoShutdownEnabled = false

    // Prepare the engine, getting all resources ready.
    audioEngine.prepare()

    // And then, start the engine! This is the moment the sound begins to play.
    try audioEngine.start()

#if os(iOS)
    // Restart the engine after audio session interruptions (phone calls, Siri, etc.)
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: nil
    ) { [weak self] notification in
      guard let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
      if type == .ended {
        try? AVAudioSession.sharedInstance().setActive(true)
        try? self?.audioEngine.start()
      }
    }

    // Track audio route changes (headphones, Bluetooth, speaker switch)
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: nil
    ) { _ in }

    // Track media services reset (rare but catastrophic)
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification,
      object: AVAudioSession.sharedInstance(),
      queue: nil
    ) { _ in }
#endif

    // The audio engine may silently stop pulling from source nodes after a
    // hardware configuration change (e.g. sample rate change, Bluetooth
    // route switch). engine.isRunning stays true but the render thread is
    // dead. Observing this notification and restarting is the documented fix.
    NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: audioEngine,
      queue: nil
    ) { [weak self] _ in
#if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(true)
#endif
      try? self?.audioEngine.start()
    }

    // Install the audio tap once up-front so that opening the visualizer
    // later doesn't cause a glitch by reconfiguring the live audio graph.
    if spatialEnabled { installTapOnce() }

    startGainPump()
  }

  /// Detached 25 ms tick that adjusts the master volume based on how many
  /// AudioGates are currently open across all registered SpatialPresets:
  ///   gain = (master? ? staticAttenuation : 1) * base / max(1, N)^exp
  /// Disabled: volume stays at whatever staticBaseGain() set at start().
  private func startGainPump() {
    stopGainPump()
    gainPumpTask = Task.detached(priority: .medium) { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(25))
        } catch {
          return
        }
        guard let self else { return }
        let duck = self.duckMultiplier()
        guard AudioSafetyRuntime.dynamicGainEnabled else {
          // Keep base gain fresh even when dynamic is off, so toggling
          // AudioSafety.staticAttenuation during playback is reflected.
          let base = self.staticBaseGain() * duck
          if self.spatialEnabled {
            self.envNode.outputVolume = base
          } else {
            self.audioEngine.mainMixerNode.outputVolume = base
          }
          continue
        }
        let n = max(1, self.openGateCount())
        let exp = AudioSafetyRuntime.dynamicGainExponent
        let dyn = AudioSafetyRuntime.dynamicGainBase / powf(Float(n), exp)
        let gain = self.staticBaseGain() * dyn * duck
        if self.spatialEnabled {
          self.envNode.outputVolume = gain
        } else {
          self.audioEngine.mainMixerNode.outputVolume = gain
        }
      }
    }
  }

  private func stopGainPump() {
    gainPumpTask?.cancel()
    gainPumpTask = nil
  }

  /// Static component of the master gain (before dynamic per-voice scaling).
  private func staticBaseGain() -> Float {
    AudioSafetyRuntime.staticAttenuationEnabled ? AudioSafetyRuntime.staticAttenuation : 1.0
  }

  /// Pop-defense: briefly ramp the master output down to zero, hold, then
  /// fade back in. Shape = hold at 0 for `hold` seconds, linear ramp to 1
  /// over `total - hold`. Intended for actions known to trigger pops
  /// (e.g. activating the visualizer). Intentionally short so the
  /// visualizer's tap still sees signal after startup.
  func duck(hold: TimeInterval = 0.70, total: TimeInterval = 1.0) {
    duckShape.withLock { $0 = (hold: hold, total: total) }
    duckStart.withLock { $0 = CFAbsoluteTimeGetCurrent() }
  }

  /// Current duck multiplier in [0, 1]. 1.0 when no duck is active.
  private func duckMultiplier() -> Float {
    guard let start = duckStart.withLock({ $0 }) else { return 1.0 }
    let shape = duckShape.withLock { $0 }
    let now = CFAbsoluteTimeGetCurrent()
    let elapsed = now - start
    if elapsed >= shape.total {
      duckStart.withLock { $0 = nil }
      return 1.0
    }
    if elapsed < shape.hold { return 0.0 }
    let fadeLen = max(0.001, shape.total - shape.hold)
    return Float((elapsed - shape.hold) / fadeLen)
  }

  /// Client-provided callback; set before calling `start()` or at any time.
  /// Called on the audio-render thread with interleaved samples.
  /// The tap is installed once at engine start to avoid audio glitches.
  private let tapCallback = OSAllocatedUnfairLock<(@Sendable ([Float]) -> Void)?>(initialState: nil)
  private var tapInstalled = false

  func setTapCallback(_ block: (@Sendable ([Float]) -> Void)?) {
    tapCallback.withLock { $0 = block }
  }

  /// Install the tap on the envNode. Called once during `start()`.
  private func installTapOnce() {
    guard !tapInstalled else { return }
    tapInstalled = true

    let node = envNode
    let format = node.outputFormat(forBus: 0)

    node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self else { return }
      guard let callback = self.tapCallback.withLock({ $0 }) else { return }
      guard let channelData = buffer.floatChannelData else { return }
      let frameLength = Int(buffer.frameLength)
      let channels = Int(format.channelCount)

      // Prepare interleaved buffer, to be re-interleaved by JavaScript
      let outputChannels = min(channels, 2)
      var samples = [Float](repeating: 0, count: frameLength * outputChannels)

      if outputChannels == 2 {
        let ptrL = channelData[0]
        let ptrR = channelData[1]
        for i in 0..<frameLength {
          samples[i*2] = ptrL[i]
          samples[i*2+1] = ptrR[i]
        }
      } else if outputChannels == 1 {
        let ptr = channelData[0]
        for i in 0..<frameLength {
          samples[i] = ptr[i]
        }
      }

      callback(samples)
    }
  }

  /// Rapidly fade output to silence to avoid a click/pop when the engine stops.
  func fadeOutAndStop(duration: TimeInterval = 0.05) {
    guard audioEngine.isRunning else { return }

    let startVolume = envNode.outputVolume
    let steps = 10
    let interval = duration / Double(steps)

    for i in 1...steps {
      let volume = startVolume * Float(1.0 - Double(i) / Double(steps))
      DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
        self?.envNode.outputVolume = volume
      }
    }

    // Stop the engine after the fade completes.
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) { [weak self] in
      self?.audioEngine.stop()
    }
  }

  /// Stop the engine, run a graph-mutating closure, then restart.
  /// Ensures the render thread isn't pulling audio while nodes are
  /// being attached or detached.
  ///
  /// `mutate` is `@MainActor` because every caller is main-actor-isolated
  /// and needs to touch its own main-isolated state (runtime, hasRandomness).
  /// Invoking an `@MainActor` closure from this nonisolated method hops
  /// onto main for the duration of the callback, which is the semantics we
  /// already rely on.
  func withQuiescedGraph(_ mutate: @MainActor () async throws -> Void) async throws {
    audioEngine.stop()
    do {
      try await mutate()
      try start()
    } catch {
      // Leave the engine running even if the mutation failed,
      // so previously-attached nodes aren't left dangling.
      try? start()
      throw error
    }
  }

  func stop() {
    stopGainPump()
    audioEngine.stop()
  }

  func pause() {
    audioEngine.pause()
  }
}
