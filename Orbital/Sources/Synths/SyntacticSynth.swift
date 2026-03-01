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
      Task { await setup(presetSpec: presetSpec) }
    }
  }

  func loadPreset(_ presetSpec: PresetSyntax) {
    cleanup()
    self.presetSpec = presetSpec
    Task { await setup(presetSpec: presetSpec) }
    reloadCount += 1
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

  private func setup(presetSpec: PresetSyntax) async {
    spatialPreset = try? await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: numVoices)
    buildHandlerAndReadValues()
  }

  private func buildHandlerAndReadValues() {
    // Build ArrowHandler from the syntax tree + aggregated handles
    if let arrowSyntax = presetSpec.arrow {
      let handler = ArrowHandler(syntax: arrowSyntax)
      if let handles = spatialPreset?.handles {
        handler.attachHandles(handles)
      }
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

    reverbPreset = first.reverbPreset
    reverbMix = first.getReverbWetDryMix()

    delayTime = first.getDelayTime()
    delayFeedback = first.getDelayFeedback()
    delayWetDryMix = first.getDelayWetDryMix()
    delayLowPassCutoff = first.getDelayLowPassCutoff()

    distortionPreset = first.getDistortionPreset()
    distortionPreGain = first.getDistortionPreGain()
    distortionWetDryMix = first.getDistortionWetDryMix()
  }
}
