//
//  AudioSafety.swift
//  Orbital
//
//  Central toggle + tuning knobs for the output-side safety chain:
//    1. Dynamic per-voice attenuation driven by the live open-gate count
//       (replaces the old static envNode.outputVolume = 0.25).
//    2. Optional brick-wall tail limiter (DynamicsProcessor) between the
//       environment node and the hardware output.
//    3. NaN/Inf scrub inside the render callback as a last line of defense
//       against DSP bugs producing non-finite samples.
//
//  Integration points each test a single Bool, so any measure can be disabled
//  to audition its contribution. Limiter insertion and master attenuation take
//  effect at the next engine start; dynamic gain and the render scrub read
//  live via AudioSafetyRuntime mirrors.
//

import Foundation
import Observation

@MainActor
@Observable
final class AudioSafety {
  static let shared = AudioSafety()

  /// When true, envNode.outputVolume is ticked at ~25 ms to track the live
  /// number of open AudioGates across every registered SpatialPreset:
  ///   gain = dynamicGainBase / max(1, openCount)^dynamicGainExponent
  /// Exponent 0.5 assumes incoherent summation (RMS), 1.0 assumes coherent.
  var dynamicGainEnabled: Bool = true { didSet { AudioSafetyRuntime.dynamicGainEnabled = dynamicGainEnabled } }
  var dynamicGainBase: Float = 1.0 { didSet { AudioSafetyRuntime.dynamicGainBase = dynamicGainBase } }
  var dynamicGainExponent: Float = 0.5 { didSet { AudioSafetyRuntime.dynamicGainExponent = dynamicGainExponent } }

  /// Static master cut applied on top of dynamic gain (multiplied). The old
  /// 0.25 volume-match behavior lives here; defaults off in favor of dynamic.
  var staticAttenuationEnabled: Bool = false { didSet { AudioSafetyRuntime.staticAttenuationEnabled = staticAttenuationEnabled } }
  var staticAttenuation: Float = 1.0 { didSet { AudioSafetyRuntime.staticAttenuation = staticAttenuation } }

  /// Brick-wall limiter inserted between envNode (or mainMixerNode) and the
  /// output node. Changes take effect at the next engine start.
  var tailLimiterEnabled: Bool = true { didSet { AudioSafetyRuntime.tailLimiterEnabled = tailLimiterEnabled } }
  var tailLimiterThresholdDB: Float = -1.0 { didSet { AudioSafetyRuntime.tailLimiterThresholdDB = tailLimiterThresholdDB } }

  /// Clip samples to [-1, 1] and replace NaN/Inf with 0 inside the render
  /// callback. Cheap insurance against DSP bugs; read live from the render
  /// thread via AudioSafetyRuntime.
  var renderScrubEnabled: Bool = true { didSet { AudioSafetyRuntime.renderScrubEnabled = renderScrubEnabled } }

  private init() {
    AudioSafetyRuntime.renderScrubEnabled = renderScrubEnabled
    AudioSafetyRuntime.dynamicGainEnabled = dynamicGainEnabled
    AudioSafetyRuntime.dynamicGainBase = dynamicGainBase
    AudioSafetyRuntime.dynamicGainExponent = dynamicGainExponent
    AudioSafetyRuntime.staticAttenuationEnabled = staticAttenuationEnabled
    AudioSafetyRuntime.staticAttenuation = staticAttenuation
    AudioSafetyRuntime.tailLimiterEnabled = tailLimiterEnabled
    AudioSafetyRuntime.tailLimiterThresholdDB = tailLimiterThresholdDB
  }
}

/// Nonisolated mirror of AudioSafety fields that are read from non-MainActor
/// contexts (render thread, detached gain-tick task). Writes happen only from
/// MainActor via AudioSafety's didSet hooks. Bool/Float word writes are atomic
/// on the target CPUs; the worst-case stale read is one buffer or one tick.
enum AudioSafetyRuntime {
  nonisolated(unsafe) static var renderScrubEnabled: Bool = true
  nonisolated(unsafe) static var dynamicGainEnabled: Bool = true
  nonisolated(unsafe) static var dynamicGainBase: Float = 1.0
  nonisolated(unsafe) static var dynamicGainExponent: Float = 0.5
  nonisolated(unsafe) static var staticAttenuationEnabled: Bool = false
  nonisolated(unsafe) static var staticAttenuation: Float = 1.0
  nonisolated(unsafe) static var tailLimiterEnabled: Bool = true
  nonisolated(unsafe) static var tailLimiterThresholdDB: Float = -1.0
}
