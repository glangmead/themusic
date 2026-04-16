//
//  SyntacticSynth.swift
//  Orbital
//
//  Created by Greg Langmead on 12/5/25.
//

import AVFAudio
import SwiftUI

// A Synth is an object that wraps a single PresetSyntax and offers mutators for all its settings, and offers a
// pool of voices for playing the Preset via a SpatialPreset.
@MainActor @Observable
class SyntacticSynth {
  var presetSpec: PresetSyntax
  let engine: SpatialAudioEngine
  private(set) var spatialPreset: SpatialPreset?
  var arrowHandler: ArrowHandler?
  var reloadCount = 0
  let numVoices = 12
  private var setupGeneration: Int = 0

  var noteHandler: NoteHandler? { spatialPreset }
  private var presets: [Preset] { spatialPreset?.presets ?? [] }
  var name: String {
    presets.first?.name ?? "Noname"
  }
  let cent: CoreFloat = 1.0005777895065548 // '2 ** (1/1200)' in python

  // Rose params
  var roseFreq: CoreFloat = 0 { didSet {
    presets.forEach { $0.positionLFO?.freq.val = roseFreq } }
  }
  var roseAmp: CoreFloat = 0 { didSet {
    presets.forEach { $0.positionLFO?.amp.val = roseAmp } }
  }
  var roseLeaves: CoreFloat = 0 { didSet {
    presets.forEach { $0.positionLFO?.leafFactor.val = roseLeaves } }
  }

  // After the first successful setup, preserve current effect values across subsequent reloads
  // (so that neither rebuildSynth nor the Randomize button need special timing infrastructure).
  private var hasSetupEffectsOnce = false

  // PADsynth parameters (only active when presetSpec.padSynth != nil)
  var padSynthBaseShape: PADBaseShape = .oneOverNSquared
  var padSynthTilt: CoreFloat = 0.0
  var padSynthBandwidthCents: CoreFloat = 50.0
  var padSynthBwScale: CoreFloat = 1.0
  var padSynthProfileShape: PADProfileShape = .gaussian
  var padSynthStretch: CoreFloat = 1.0
  var padSynthSelectedInstrument: String?

  var hasPadSynth: Bool { presetSpec.effectivePadSynth != nil }

  /// Saved arrow parameter values across rebuilds (set in loadPreset, consumed in buildHandlerAndReadValues).
  private var savedArrowFloats: [String: CoreFloat]?
  private var savedArrowShapes: [String: BasicOscillator.OscShape]?

  // FX params
  var distortionAvailable: Bool {
    presets.first?.distortionAvailable ?? false
  }

  var delayAvailable: Bool {
    presets.first?.delayAvailable ?? false
  }

  var reverbMix: CoreFloat = 50 {
    didSet {
      for preset in self.presets { preset.setReverbWetDryMix(reverbMix) }
      // not effective: engine.envNode.reverbBlend = reverbMix / 100 // (env node uses 0-1 instead of 0-100)
    }
  }
  var reverbPreset: AVAudioUnitReverbPreset = .largeRoom {
    didSet {
      for preset in self.presets { preset.reverbPreset = reverbPreset }
      // not effective: engine.envNode.reverbParameters.loadFactoryReverbPreset(reverbPreset)
    }
  }
  var delayTime: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDelayTime(TimeInterval(delayTime)) }
    }
  }
  var delayFeedback: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDelayFeedback(delayFeedback) }
    }
  }
  var delayLowPassCutoff: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDelayLowPassCutoff(delayLowPassCutoff) }
    }
  }
  var delayWetDryMix: CoreFloat = 50 {
    didSet {
      for preset in self.presets { preset.setDelayWetDryMix(delayWetDryMix) }
    }
  }
  var distortionPreGain: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDistortionPreGain(distortionPreGain) }
    }
  }
  var distortionWetDryMix: CoreFloat = 0 {
    didSet {
      for preset in self.presets { preset.setDistortionWetDryMix(distortionWetDryMix) }
    }
  }
  var distortionPreset: AVAudioUnitDistortionPreset = .multiDecimated1 {
    didSet {
      for preset in self.presets { preset.setDistortionPreset(distortionPreset) }
    }
  }

  init(engine: SpatialAudioEngine, presetSpec: PresetSyntax, numVoices: Int = 12, deferSetup: Bool = false) {
    self.engine = engine
    self.presetSpec = presetSpec
    if !deferSetup {
      setupGeneration += 1
      Task { await setup(presetSpec: presetSpec, generation: setupGeneration) }
    }
  }

  /// Swap in a new PresetSyntax. When `preserveUserValues` is true (the
  /// padSynth-rebuild case), the current arrow-param and effects values are
  /// re-applied to the new preset so user tweaks survive. When false (the
  /// preset-picker case), the new preset's own values are used verbatim —
  /// otherwise descriptor-ID collisions (e.g. "ampEnv.attack") smuggle the
  /// previous preset's envelope into the new one.
  func loadPreset(_ presetSpec: PresetSyntax, preserveUserValues: Bool = false) {
    if preserveUserValues {
      savedArrowFloats = arrowHandler?.floatValues
      savedArrowShapes = arrowHandler?.shapeValues
    } else {
      savedArrowFloats = nil
      savedArrowShapes = nil
      hasSetupEffectsOnce = false
    }
    // Don't call cleanup() here — keep old spatialPreset/arrowHandler alive
    // so the view doesn't flicker. setup() swaps atomically when the new
    // preset is ready.
    self.presetSpec = presetSpec
    setupGeneration += 1
    Task { await setup(presetSpec: presetSpec, generation: setupGeneration) }
  }

  /// Attach to an existing SpatialPreset (e.g. from a song track) so that
  /// parameter changes affect the live audio graph instead of a disconnected copy.
  func attachToLivePreset(_ live: SpatialPreset) {
    // Detach without destroying — we don't own the live preset's audio nodes.
    spatialPreset = nil
    arrowHandler = nil
    isAttachedToLivePreset = true
    self.presetSpec = live.presetSpec
    spatialPreset = live
    buildHandlerAndReadValues()
    reloadCount += 1
  }

  /// Whether this synth is borrowing an external SpatialPreset it doesn't own.
  private var isAttachedToLivePreset = false

  private func cleanup() {
    if !isAttachedToLivePreset {
      spatialPreset?.cleanup()
    }
    spatialPreset = nil
    arrowHandler = nil
    isAttachedToLivePreset = false
  }

  private func setup(presetSpec: PresetSyntax, generation: Int) async {
    let newPreset = try? await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: numVoices)
    // If a newer loadPreset() was called while we were awaiting, discard this result.
    // The newer task will own spatialPreset; our nodes must be detached to avoid a stuck-note leak.
    guard generation == setupGeneration else {
      newPreset?.cleanup()
      return
    }
    spatialPreset?.cleanup()
    spatialPreset = newPreset
    // Live preview: drive spatial motion for as long as this synth's preset is loaded.
    // (MusicPattern.play() handles the same job for pattern playback.)
    newPreset?.startPositionPump()
    buildHandlerAndReadValues()
  }

  /// Snapshot the current synth state back into a serializable PresetSyntax.
  func currentPresetSyntax(name: String) -> PresetSyntax {
    let effects = EffectsSyntax(
      reverbPreset: CoreFloat(reverbPreset.rawValue),
      reverbWetDryMix: reverbMix,
      delayTime: delayTime,
      delayFeedback: delayFeedback,
      delayLowPassCutoff: delayLowPassCutoff,
      delayWetDryMix: delayWetDryMix
    )
    let rose = RoseSyntax(
      amp: roseAmp,
      leafFactor: roseLeaves,
      freq: roseFreq,
      phase: presetSpec.rose.phase
    )
    let padSynth: PADSynthSyntax? = if hasPadSynth {
      PADSynthSyntax(
        baseShape: padSynthBaseShape,
        tilt: padSynthTilt,
        bandwidthCents: padSynthBandwidthCents,
        bwScale: padSynthBwScale,
        profileShape: padSynthProfileShape,
        stretch: padSynthStretch,
        selectedInstrument: padSynthSelectedInstrument,
        envelopeCoefficients: presetSpec.effectivePadSynth?.envelopeCoefficients
      )
    } else {
      nil
    }
    // Write current parameter values back into the arrow tree so saved
    // JSON reflects slider changes (filter cutoff, envelope times, etc.).
    // effectiveArrow resolves padTemplate → arrow when arrow is nil.
    var savedArrow = presetSpec.effectiveArrow
    if let arrow = savedArrow, let handler = arrowHandler {
      savedArrow = arrow.applyingParameterValues(
        floats: handler.floatValues,
        shapes: handler.shapeValues
      )
    }
    // Sync padSynthWavetable params so the JSON is self-consistent.
    if let arrow = savedArrow, let ps = padSynth {
      savedArrow = arrow.replacingPadSynthParams(ps)
    }
    return PresetSyntax(
      name: name,
      arrow: savedArrow,
      samplerFilenames: presetSpec.samplerFilenames,
      samplerProgram: presetSpec.samplerProgram,
      samplerBank: presetSpec.samplerBank,
      library: presetSpec.library,
      rose: rose,
      effects: effects,
      padTemplate: presetSpec.padTemplate,
      padSynth: padSynth
    )
  }

  private func buildHandlerAndReadValues() {
    // Build ArrowHandler from the syntax tree + aggregated handles.
    // effectiveArrow resolves padTemplate → arrow when arrow is nil,
    // so pad-template presets (e.g. random pads) get editable parameters.
    if let arrowSyntax = presetSpec.effectiveArrow {
      let handler = ArrowHandler(syntax: arrowSyntax)
      if let handles = spatialPreset?.handles {
        handler.attachHandles(handles)
      }
      // Restore user-tweaked values saved before the rebuild (see loadPreset).
      if let floats = savedArrowFloats {
        for (id, value) in floats {
          handler.setFloat(id, to: value)
        }
      }
      if let shapes = savedArrowShapes {
        for (id, shape) in shapes {
          handler.setShape(id, to: shape)
        }
      }
      savedArrowFloats = nil
      savedArrowShapes = nil
      arrowHandler = handler
    } else {
      arrowHandler = nil
    }

    // Read rose, effects, and delay values from the first preset
    guard let first = presets.first else { return }

    if let posLFO = first.positionLFO {
      roseAmp = posLFO.amp.val
      roseFreq = posLFO.freq.val
      roseLeaves = posLFO.leafFactor.val
    }

    // On first load read from the preset; on subsequent reloads keep current values so that
    // user-set effects (or Randomize) survive pad-template rebuilds. Either way, assigning
    // re-triggers didSet, which propagates the values to the newly created audio nodes.
    reverbPreset    = hasSetupEffectsOnce ? reverbPreset    : first.reverbPreset
    reverbMix       = hasSetupEffectsOnce ? reverbMix       : first.getReverbWetDryMix()
    delayTime       = hasSetupEffectsOnce ? delayTime       : first.getDelayTime()
    delayFeedback   = hasSetupEffectsOnce ? delayFeedback   : first.getDelayFeedback()
    delayWetDryMix  = hasSetupEffectsOnce ? delayWetDryMix  : first.getDelayWetDryMix()
    delayLowPassCutoff = hasSetupEffectsOnce ? delayLowPassCutoff : first.getDelayLowPassCutoff()
    hasSetupEffectsOnce = true

    distortionPreset = first.getDistortionPreset()
    distortionPreGain = first.getDistortionPreGain()
    distortionWetDryMix = first.getDistortionWetDryMix()

    if let ps = presetSpec.effectivePadSynth {
      padSynthBaseShape = ps.baseShape
      padSynthTilt = ps.tilt
      padSynthBandwidthCents = ps.bandwidthCents
      padSynthBwScale = ps.bwScale
      padSynthProfileShape = ps.profileShape
      padSynthStretch = ps.stretch
      padSynthSelectedInstrument = ps.selectedInstrument
    }
  }
}
