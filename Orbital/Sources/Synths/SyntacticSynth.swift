//
//  SyntacticSynth.swift
//  Orbital
//
//  Created by Greg Langmead on 12/5/25.
//

import AVFAudio
import SwiftUI


/// TODO
/// A button to save the current synth as a preset
/// Move on to assigning different presets to different seq tracks
/// Pulse oscillator? Or a param for the square?notehandler
/// Build a library of presets
///   - Minifreak V presets that use basic oscillators
///     - 5th Clue
// A Synth is an object that wraps a single PresetSyntax and offers mutators for all its settings, and offers a
// pool of voices for playing the Preset via a SpatialPreset.
@MainActor @Observable
class SyntacticSynth {
  var presetSpec: PresetSyntax
  let engine: SpatialAudioEngine
  private(set) var spatialPreset: SpatialPreset? = nil
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
    presets[0].distortionAvailable
  }
  
  var delayAvailable: Bool {
    presets[0].delayAvailable
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
  
  init(engine: SpatialAudioEngine, presetSpec: PresetSyntax, numVoices: Int = 12) {
    self.engine = engine
    self.presetSpec = presetSpec
    Task { await setup(presetSpec: presetSpec) }
  }
  
  func loadPreset(_ presetSpec: PresetSyntax) {
    cleanup()
    self.presetSpec = presetSpec
    Task { await setup(presetSpec: presetSpec) }
    reloadCount += 1
  }
  
  private func cleanup() {
    spatialPreset?.cleanup()
    spatialPreset = nil
    arrowHandler = nil
  }
  
  private func setup(presetSpec: PresetSyntax) async {
    spatialPreset = try? await SpatialPreset(presetSpec: presetSpec, engine: engine, numVoices: numVoices)
    
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
    if let posLFO = presets[0].positionLFO {
      roseAmp = posLFO.amp.val
      roseFreq = posLFO.freq.val
      roseLeaves = posLFO.leafFactor.val
    }
    
    reverbPreset = presets[0].reverbPreset
    reverbMix = presets[0].getReverbWetDryMix()
    
    delayTime = presets[0].getDelayTime()
    delayFeedback = presets[0].getDelayFeedback()
    delayWetDryMix = presets[0].getDelayWetDryMix()
    delayLowPassCutoff = presets[0].getDelayLowPassCutoff()
    
    distortionPreset = presets[0].getDistortionPreset()
    distortionPreGain = presets[0].getDistortionPreGain()
    distortionWetDryMix = presets[0].getDistortionWetDryMix()
  }
}
