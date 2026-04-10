//
//  PadTemplateCompiler.swift
//  Orbital
//
//  Compiles a PadTemplateSyntax into an ArrowSyntax signal graph.
//  The caller is responsible for wrapping the result in a PresetSyntax with effects/rose.
//

import Foundation

// MARK: - Compiled intermediate parameters (private to this file)

private struct PadCompiledParams {
  let ampAttack: CoreFloat
  let ampDecay: CoreFloat
  let ampSustain: CoreFloat
  let ampRelease: CoreFloat
  let cutoffMultiplier: CoreFloat
  let resonance: CoreFloat
  let vibratoRate: CoreFloat
  let crossfadeRate: CoreFloat
  let filterLFORate: CoreFloat?
  let chorusCentRadius: Int
  let chorusNumVoices: Int
  let gritAmount: CoreFloat  // 0..1 → bit crusher amount (0 = bypass)
}

// MARK: - Compiler

enum PadTemplateCompiler {

  // MARK: - Public API

  static func compile(_ t: PadTemplateSyntax) -> ArrowSyntax {
    let sliders = resolvedSliders(for: t)
    let params  = deriveParams(from: t, sliders: sliders)
    let branches = t.oscillators.enumerated().map { idx, desc in
      buildOscBranch(index: idx, desc: desc, params: params, t: t)
    }
    let oscSection = buildOscSection(branches: branches, crossfade: t.crossfade, crossfadeRate: params.crossfadeRate)
    let ampEnv = ArrowSyntax.envelope(name: "ampEnv", attack: params.ampAttack, decay: params.ampDecay, sustain: params.ampSustain, release: params.ampRelease, scale: 1)
    var steps: [ArrowSyntax] = [
      .prod(of: [
        .const(name: "overallAmp", val: 1.0),
        .const(name: "overallAmp2", val: 1.0),
        oscSection,
        ampEnv
      ]),
      buildFilter(params: params, t: t)
    ]
    if params.gritAmount > 0.001 {
      steps.append(.bitCrusher(name: "bitCrusher", amount: .const(name: "gritAmount", val: params.gritAmount)))
    }
    return .compose(arrows: steps)
  }

  // MARK: - Slider resolution

  private static func resolvedSliders(for t: PadTemplateSyntax) -> PadSliders {
    if let explicit = t.sliders { return explicit }
    switch t.mood {
    case .cosmic:   return .cosmicDefaults
    case .dark:     return .darkDefaults
    case .warm:     return .warmDefaults
    case .ethereal: return .etherealDefaults
    case .gritty:   return .grittyDefaults
    case .custom:   return .warmDefaults
    }
  }

  // MARK: - Parameter derivation

  private static func lerp(_ lo: CoreFloat, _ hi: CoreFloat, _ x: CoreFloat) -> CoreFloat {
    lo + x * (hi - lo)
  }

  private static func deriveParams(from t: PadTemplateSyntax, sliders s: PadSliders) -> PadCompiledParams {
    // Slow modulation base (crossfade, filter LFO): 0.05–1.0 Hz.
    // Vibrato uses a separate range (1–6 Hz) so they occupy different timescales.
    let slowBase      = lerp(0.05, 1.0, s.motion)
    let vibratoRate   = t.vibratoRate    ?? lerp(1.0, 6.0, s.motion)
    let crossfadeRate = t.crossfadeRate  ?? slowBase
    let cutoffMult    = t.filterCutoffMultiplier ?? lerp(2.0, 4.0, s.bite)
    let resonance     = t.filterResonance        ?? lerp(0.3, 1.5, s.grit)
    let ampAttack     = t.ampAttack  ?? lerp(0.5, 8.0, s.smooth)
    let ampRelease    = t.ampRelease ?? lerp(0.5, 8.0, s.smooth)
    // Filter LFO rate at a prime-ratio offset from the slow base so it never locks with crossfade.
    let filterLFORate = t.filterLFORate.map { $0 > 0 ? $0 : slowBase * 1.37 }
    return PadCompiledParams(
      ampAttack: ampAttack,
      ampDecay: t.ampDecay,
      ampSustain: t.ampSustain,
      ampRelease: ampRelease,
      cutoffMultiplier: cutoffMult,
      resonance: resonance,
      vibratoRate: vibratoRate,
      crossfadeRate: crossfadeRate,
      filterLFORate: filterLFORate,
      chorusCentRadius: Int(lerp(0, 30, s.width)),
      chorusNumVoices: 2,
      gritAmount: s.grit
    )
  }

  // MARK: - Vibrato term

  // Matches the structure used in warm_analog_pad.json:
  // compose([ prod([freq, vibratoAmp, vibratoEnv, sum([shift, prod([scale, compose([prod([vibratoFreq, identity]), sineOsc])])])]), control ])
  private static func buildVibratoTerm(oscIndex: Int, rate: CoreFloat, depth: CoreFloat) -> ArrowSyntax {
    let n = oscIndex + 1
    return .compose(arrows: [
      .prod(of: [
        .const(name: "freq", val: 300),
        .const(name: "vibratoAmp", val: depth),
        .envelope(name: "vibratoEnv", attack: 5, decay: 0.1, sustain: 1, release: 0.1, scale: 1),
        .sum(of: [
          .const(name: "vibratoOscShift", val: 0.5),
          .prod(of: [
            .const(name: "vibratoOscScale", val: 0.5),
            .compose(arrows: [
              .prod(of: [.const(name: "vibratoFreq", val: rate), .identity]),
              .osc(name: "vibratoOsc", shape: .sine, width: .const(name: "osc\(n)VibWidth", val: 1))
            ])
          ])
        ])
      ]),
      .control
    ])
  }

  // MARK: - Frequency chain

  private static func buildFreqChain(oscIndex: Int, desc: PadOscDescriptor, params: PadCompiledParams, vibratoEnabled: Bool, vibratoDepth: CoreFloat) -> ArrowSyntax {
    let n      = oscIndex + 1
    let octave = desc.octave     ?? 0
    let cents  = desc.detuneCents ?? 0
    let directFreq = ArrowSyntax.prod(of: [
      .const(name: "freq", val: 300),
      .constOctave(name: "osc\(n)Octave", val: octave),
      .constCent(name: "osc\(n)CentDetune", val: cents),
      .identity
    ])
    guard vibratoEnabled else { return directFreq }
    return .sum(of: [directFreq, buildVibratoTerm(oscIndex: oscIndex, rate: params.vibratoRate, depth: vibratoDepth)])
  }

  // MARK: - Oscillator node

  private static func buildOscNode(oscIndex: Int, desc: PadOscDescriptor) -> ArrowSyntax {
    let n = oscIndex + 1
    switch desc.kind {
    case .standard:
      return .osc(name: "osc\(n)", shape: desc.shape ?? .sine, width: .const(name: "osc\(n)Width", val: 1))
    case .wavetable:
      return .wavetable(name: "osc\(n)", tableName: desc.file ?? "fm_bell", width: .const(name: "osc\(n)Width", val: 1))
    case .padSynth:
      let params = desc.padSynthParams ?? PADSynthSyntax(
        baseShape: .oneOverNSquared, tilt: 0, bandwidthCents: 50, bwScale: 1,
        profileShape: .gaussian, stretch: 1, selectedInstrument: nil, envelopeCoefficients: nil
      )
      return .padSynthWavetable(name: "osc\(n)", params: params, width: .const(name: "osc\(n)Width", val: 1))
    }
  }

  // MARK: - Full oscillator branch: prod([ oscNMix, compose([ freqChain, oscNode, choruser ]) ])

  private static func buildOscBranch(index i: Int, desc: PadOscDescriptor, params: PadCompiledParams, t: PadTemplateSyntax) -> ArrowSyntax {
    let n = i + 1
    return .prod(of: [
      .const(name: "osc\(n)Mix", val: 1.0),
      .compose(arrows: [
        buildFreqChain(oscIndex: i, desc: desc, params: params, vibratoEnabled: t.vibratoEnabled, vibratoDepth: t.vibratoDepth),
        buildOscNode(oscIndex: i, desc: desc),
        .choruser(name: "osc\(n)Choruser", valueToChorus: "freq", chorusCentRadius: params.chorusCentRadius, chorusNumVoices: params.chorusNumVoices)
      ])
    ])
  }

  // MARK: - Oscillator section (crossfade or static mix)

  private static func buildOscSection(branches: [ArrowSyntax], crossfade: PadCrossfadeKind, crossfadeRate: CoreFloat) -> ArrowSyntax {
    guard branches.count > 1 else { return branches[0] }
    let count = branches.count
    switch crossfade {
    case .noiseSmoothStep:
      let mixPoint = ArrowSyntax.compose(arrows: [
        .identity,
        .noiseSmoothStep(noiseFreq: crossfadeRate, min: 0, max: CoreFloat(count - 1))
      ])
      return .crossfadeEqPow(of: branches, name: "oscCrossfade", mixPoint: mixPoint)
    case .lfo:
      // Sine LFO in [-1,1] → scale to [0, count-1]
      let scale = CoreFloat(count - 1) / 2.0
      let mixPoint = ArrowSyntax.compose(arrows: [
        .prod(of: [.const(name: "crossfadeRate", val: crossfadeRate), .identity]),
        .osc(name: "crossfadeLFO", shape: .sine, width: .const(name: "crossfadeLFOWidth", val: 1)),
        .sum(of: [.identity, .const(name: "lfoShift", val: 1.0)]),
        .prod(of: [.identity, .const(name: "lfoScale", val: scale)])
      ])
      return .crossfadeEqPow(of: branches, name: "oscCrossfade", mixPoint: mixPoint)
    case .`static`:
      return .sum(of: branches)
    }
  }

  // MARK: - Filter

  private static func buildFilterCutoff(params: PadCompiledParams, t: PadTemplateSyntax) -> ArrowSyntax {
    let filterEnv = ArrowSyntax.envelope(name: "filterEnv", attack: t.filterEnvAttack, decay: t.filterEnvDecay, sustain: t.filterEnvSustain, release: t.filterEnvRelease, scale: 1)
    let innerProd: ArrowSyntax
    if let lfoRate = params.filterLFORate {
      // Filter cutoff oscillates with a slow LFO
      innerProd = .prod(of: [
        .const(name: "freq", val: 300),
        .const(name: "cutoffMultiplier", val: params.cutoffMultiplier),
        filterEnv,
        .sum(of: [
          .const(name: "filterLFOShift", val: 0.5),
          .prod(of: [
            .const(name: "filterLFOScale", val: 0.5),
            .compose(arrows: [
              .prod(of: [.const(name: "filterLFORate", val: lfoRate), .identity]),
              .osc(name: "filterLFO", shape: .sine, width: .const(name: "filterLFOWidth", val: 1))
            ])
          ])
        ])
      ])
    } else {
      innerProd = .prod(of: [
        .const(name: "freq", val: 300),
        .const(name: "cutoffMultiplier", val: params.cutoffMultiplier),
        filterEnv
      ])
    }
    return .sum(of: [.const(name: "cutoffLow", val: t.filterCutoffLow), innerProd])
  }

  private static func buildFilter(params: PadCompiledParams, t: PadTemplateSyntax) -> ArrowSyntax {
    .lowPassFilter(
      name: "filter",
      cutoff: buildFilterCutoff(params: params, t: t),
      resonance: .const(name: "resonance", val: params.resonance)
    )
  }
}
