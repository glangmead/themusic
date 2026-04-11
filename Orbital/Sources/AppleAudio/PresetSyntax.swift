//
//  PresetSyntax.swift
//  Orbital
//
//  JSON-serializable preset templates: RoseSyntax, EffectsSyntax, PresetSyntax.
//  Extracted from Preset.swift.
//

import AVFAudio

struct RoseSyntax: Codable {
  let amp: CoreFloat
  let leafFactor: CoreFloat
  let freq: CoreFloat
  let phase: CoreFloat
}

struct EffectsSyntax: Codable {
  let reverbPreset: CoreFloat
  let reverbWetDryMix: CoreFloat
  let delayTime: TimeInterval
  let delayFeedback: CoreFloat
  let delayLowPassCutoff: CoreFloat
  let delayWetDryMix: CoreFloat
}

struct PresetSyntax: Codable, Sendable {
  let name: String
  let arrow: ArrowSyntax? // a sound synthesized in code, to be attached to an AVAudioSourceNode; mutually exclusive with a sample
  let samplerFilenames: [String]? // a sound from an audio file(s) in our bundle; mutually exclusive with an arrow
  let samplerProgram: UInt8? // a soundfont idiom: the instrument/preset index
  let samplerBank: UInt8? // a soundfont idiom: the grouping of instruments, e.g. usually 121 for sounds and 120 for percussion
  let library: [[String: ArrowSyntax]]? // named reusable arrow definitions, referenced via .libraryArrow
  let rose: RoseSyntax
  let effects: EffectsSyntax
  let padTemplate: PadTemplateSyntax? // high-level template; compiled to arrow on first use when arrow is absent
  let padSynth: PADSynthSyntax? // PADsynth algorithm params; compiled to per-note wavetables

  /// The effective PADsynth parameters: prefers the explicit `padSynth` field,
  /// falls back to extracting from the first `padSynthWavetable` node in the arrow tree.
  var effectivePadSynth: PADSynthSyntax? {
    padSynth ?? arrow?.extractPadSynthParams()
  }

  /// Build the resolved [String: ArrowSyntax] dictionary from the library
  /// array, resolving forward references in order.
  func resolvedLibrary() -> [String: ArrowSyntax] {
    guard let library else { return [:] }
    var dict = [String: ArrowSyntax]()
    for entry in library {
      for (name, arrow) in entry {
        dict[name] = arrow.resolveLibrary(dict)
      }
    }
    return dict
  }

  func compile(numVoices: Int = 12, initEffects: Bool = true, resourceBaseURL: URL? = nil) -> Preset {
    let resolvedArrow: ArrowSyntax?
    if let arrow {
      // When padSynth params are present, inject them into any
      // padSynthWavetable nodes so the top-level padSynth field
      // stays the single source of truth for PADsynth parameters.
      if let padSynth {
        resolvedArrow = arrow.replacingPadSynthParams(padSynth)
      } else {
        resolvedArrow = arrow
      }
    } else if let padTemplate {
      resolvedArrow = PadTemplateCompiler.compile(padTemplate)
    } else {
      resolvedArrow = nil
    }
    let preset: Preset
    if let arrowSyntax = resolvedArrow {
      preset = Preset(arrowSyntax: arrowSyntax, library: resolvedLibrary(), numVoices: numVoices, initEffects: initEffects)
    } else if let samplerFilenames = samplerFilenames, let samplerBank = samplerBank, let samplerProgram = samplerProgram {
      preset = Preset(sampler: Sampler(fileNames: samplerFilenames, bank: samplerBank, program: samplerProgram, resourceBaseURL: resourceBaseURL), initEffects: initEffects)
    } else {
      fatalError("PresetSyntax must have arrow, padTemplate, or sampler")
    }

    preset.name = name
    preset.reverbPreset = AVAudioUnitReverbPreset(rawValue: Int(effects.reverbPreset)) ?? .mediumRoom
    preset.setReverbWetDryMix(effects.reverbWetDryMix)
    preset.setDelayTime(effects.delayTime)
    preset.setDelayFeedback(effects.delayFeedback)
    preset.setDelayLowPassCutoff(effects.delayLowPassCutoff)
    preset.setDelayWetDryMix(effects.delayWetDryMix)
    preset.positionLFO = Rose(
      amp: ArrowConst(value: rose.amp),
      leafFactor: ArrowConst(value: rose.leafFactor),
      freq: ArrowConst(value: rose.freq),
      phase: rose.phase
    )
    return preset
  }

}
