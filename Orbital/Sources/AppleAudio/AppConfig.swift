//
//  AppConfig.swift
//  Orbital
//
//  Global app-wide configuration. Groups two concerns:
//    1. Output-side audio safety (dynamic per-voice attenuation, tail limiter,
//       render-thread NaN/Inf scrub). These generalize the older AudioSafety
//       class this file replaces.
//    2. Playback shaping for MIDI sequences (compressing long stretches of
//       silence or a single sustaining note during MIDI playback). Handled
//       by MidiEventSequence.compressingQuietSectionsGlobally().
//
//  Storage model: the real values live in AppConfigRuntime — nonisolated
//  atomic-word-size statics that any thread can read without hopping to
//  MainActor. The render callback and the gain-pump task depend on this.
//  `AppConfig` is an @Observable MainActor wrapper whose properties are
//  computed — reads/writes consult the statics through access(keyPath:) and
//  withMutation(keyPath:) so SwiftUI views that bind to AppConfig.shared
//  re-render on change. Writes should go through AppConfig.shared; direct
//  writes to AppConfigRuntime work correctly but bypass SwiftUI's immediate
//  invalidation (views see the new value on their next unrelated refresh).
//
//  Integration points each test a single Bool, so any measure can be disabled
//  to audition its contribution. Limiter insertion and master attenuation
//  take effect at the next engine start; dynamic gain, render scrub, and the
//  MIDI-playback knobs are read live.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppConfig {
  static let shared = AppConfig()

  private init() {}

  // MARK: - Audio safety: dynamic gain

  /// When true, envNode.outputVolume is ticked at ~25 ms to track the live
  /// number of open AudioGates across every registered SpatialPreset:
  ///   gain = dynamicGainBase / max(1, openCount)^dynamicGainExponent
  /// Exponent 0.5 assumes incoherent summation (RMS), 1.0 assumes coherent.
  var dynamicGainEnabled: Bool {
    get { access(keyPath: \.dynamicGainEnabled); return AppConfigRuntime.dynamicGainEnabled }
    set { withMutation(keyPath: \.dynamicGainEnabled) { AppConfigRuntime.dynamicGainEnabled = newValue } }
  }

  var dynamicGainBase: Float {
    get { access(keyPath: \.dynamicGainBase); return AppConfigRuntime.dynamicGainBase }
    set { withMutation(keyPath: \.dynamicGainBase) { AppConfigRuntime.dynamicGainBase = newValue } }
  }

  var dynamicGainExponent: Float {
    get { access(keyPath: \.dynamicGainExponent); return AppConfigRuntime.dynamicGainExponent }
    set { withMutation(keyPath: \.dynamicGainExponent) { AppConfigRuntime.dynamicGainExponent = newValue } }
  }

  /// Static master cut applied on top of dynamic gain (multiplied). The old
  /// 0.25 volume-match behavior lives here; defaults off in favor of dynamic.
  var staticAttenuationEnabled: Bool {
    get { access(keyPath: \.staticAttenuationEnabled); return AppConfigRuntime.staticAttenuationEnabled }
    set { withMutation(keyPath: \.staticAttenuationEnabled) { AppConfigRuntime.staticAttenuationEnabled = newValue } }
  }

  var staticAttenuation: Float {
    get { access(keyPath: \.staticAttenuation); return AppConfigRuntime.staticAttenuation }
    set { withMutation(keyPath: \.staticAttenuation) { AppConfigRuntime.staticAttenuation = newValue } }
  }

  // MARK: - Audio safety: tail limiter & render scrub

  /// Brick-wall limiter inserted between envNode (or mainMixerNode) and the
  /// output node. Changes take effect at the next engine start.
  var tailLimiterEnabled: Bool {
    get { access(keyPath: \.tailLimiterEnabled); return AppConfigRuntime.tailLimiterEnabled }
    set { withMutation(keyPath: \.tailLimiterEnabled) { AppConfigRuntime.tailLimiterEnabled = newValue } }
  }

  var tailLimiterThresholdDB: Float {
    get { access(keyPath: \.tailLimiterThresholdDB); return AppConfigRuntime.tailLimiterThresholdDB }
    set { withMutation(keyPath: \.tailLimiterThresholdDB) { AppConfigRuntime.tailLimiterThresholdDB = newValue } }
  }

  /// Clip samples to [-1, 1] and replace NaN/Inf with 0 inside the render
  /// callback. Cheap insurance against DSP bugs; read live from the render
  /// thread via AppConfigRuntime.
  var renderScrubEnabled: Bool {
    get { access(keyPath: \.renderScrubEnabled); return AppConfigRuntime.renderScrubEnabled }
    set { withMutation(keyPath: \.renderScrubEnabled) { AppConfigRuntime.renderScrubEnabled = newValue } }
  }

  // MARK: - MIDI playback shaping

  /// When true, stretches where no note is sounding are compressed to at most
  /// `maxSilenceSeconds`. Applied at pattern-compile time via
  /// `MidiEventSequence.compressingQuietSectionsGlobally`.
  var shortenSilencesEnabled: Bool {
    get { access(keyPath: \.shortenSilencesEnabled); return AppConfigRuntime.shortenSilencesEnabled }
    set { withMutation(keyPath: \.shortenSilencesEnabled) { AppConfigRuntime.shortenSilencesEnabled = newValue } }
  }

  var maxSilenceSeconds: Double {
    get { access(keyPath: \.maxSilenceSeconds); return AppConfigRuntime.maxSilenceSeconds }
    set { withMutation(keyPath: \.maxSilenceSeconds) { AppConfigRuntime.maxSilenceSeconds = newValue } }
  }

  /// When true, stretches where exactly one note is sounding are compressed
  /// to at most `maxSingletonSeconds`. The lone note's sustain is truncated
  /// and subsequent onsets are pulled earlier by the excess amount.
  var shortenSingletonsEnabled: Bool {
    get { access(keyPath: \.shortenSingletonsEnabled); return AppConfigRuntime.shortenSingletonsEnabled }
    set { withMutation(keyPath: \.shortenSingletonsEnabled) { AppConfigRuntime.shortenSingletonsEnabled = newValue } }
  }

  var maxSingletonSeconds: Double {
    get { access(keyPath: \.maxSingletonSeconds); return AppConfigRuntime.maxSingletonSeconds }
    set { withMutation(keyPath: \.maxSingletonSeconds) { AppConfigRuntime.maxSingletonSeconds = newValue } }
  }
}

/// Authoritative storage for AppConfig. All fields are nonisolated so the
/// render thread, the detached gain-pump task, and the async pattern-compile
/// path can read them without an actor hop. Bool/Float/Double word writes are
/// atomic on the target CPUs; the worst-case stale read is one buffer or one
/// tick. Defaults match the `AppConfig` documentation above.
enum AppConfigRuntime {
  nonisolated(unsafe) static var dynamicGainEnabled: Bool = true
  nonisolated(unsafe) static var dynamicGainBase: Float = 1.0
  nonisolated(unsafe) static var dynamicGainExponent: Float = 0.5
  nonisolated(unsafe) static var staticAttenuationEnabled: Bool = false
  nonisolated(unsafe) static var staticAttenuation: Float = 1.0
  nonisolated(unsafe) static var tailLimiterEnabled: Bool = true
  nonisolated(unsafe) static var tailLimiterThresholdDB: Float = -1.0
  nonisolated(unsafe) static var renderScrubEnabled: Bool = true
  nonisolated(unsafe) static var shortenSilencesEnabled: Bool = true
  nonisolated(unsafe) static var maxSilenceSeconds: Double = 2.0
  nonisolated(unsafe) static var shortenSingletonsEnabled: Bool = true
  nonisolated(unsafe) static var maxSingletonSeconds: Double = 5.0
}
