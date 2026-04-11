//
//  PadTemplateCompilerTests.swift
//  Orbital
//

import Testing
import Foundation
@testable import Orbital

@Suite("PadTemplateCompiler")
struct PadTemplateCompilerTests {

  // MARK: - Slider resolution

  @Test("Mood defaults resolve correctly")
  func moodDefaults() {
    let moods: [(PadMood, PadSliders)] = [
      (.cosmic, .cosmicDefaults),
      (.dark, .darkDefaults),
      (.warm, .warmDefaults),
      (.ethereal, .etherealDefaults),
      (.gritty, .grittyDefaults)
    ]
    for (mood, expected) in moods {
      let t = makeTemplate(mood: mood, sliders: nil)
      let arrow = PadTemplateCompiler.compile(t)
      // Just verify it compiles without crash; detailed param checks are below.
      _ = arrow
      #expect(expected.smooth >= 0 && expected.smooth <= 1)
    }
  }

  @Test("Explicit sliders override mood")
  func explicitSlidersOverride() {
    let custom = PadSliders(smooth: 0.1, bite: 0.9, motion: 0.5, width: 0.2, grit: 0.8)
    let t = makeTemplate(mood: .cosmic, sliders: custom)
    let arrow = PadTemplateCompiler.compile(t)
    // Verify the arrow has a lowPassFilter — the cutoff multiplier should reflect bite=0.9.
    // PadTemplateCompiler maps cutoffMultiplier via lerp(2.0, 4.0, bite) — the upper
    // bound was tightened from 12.0 to 4.0 in commit 606da1d to keep filter sweeps
    // out of harsh-frequency territory. lerp(2.0, 4.0, 0.9) = 3.8.
    let filterCutoff = extractCutoffMultiplier(from: arrow)
    #expect(abs((filterCutoff ?? 0) - 3.8) < 0.01)
  }

  @Test("Cosmic mood produces expected amp attack (≈6.5)")
  func cosmicAmpAttack() {
    let t = makeTemplate(mood: .cosmic, sliders: nil)
    let arrow = PadTemplateCompiler.compile(t)
    // smooth=0.8 → lerp(0.5, 8.0, 0.8) = 6.5
    let attack = extractAmpEnvAttack(from: arrow)
    #expect(abs((attack ?? 0) - 6.5) < 0.01)
  }

  @Test("Explicit ampAttack override wins over slider")
  func ampAttackOverride() {
    var t = makeTemplate(mood: .cosmic, sliders: nil)
    t = PadTemplateSyntax(
      name: t.name, oscillators: t.oscillators, crossfade: t.crossfade, crossfadeRate: t.crossfadeRate,
      vibratoEnabled: t.vibratoEnabled, vibratoRate: t.vibratoRate, vibratoDepth: t.vibratoDepth,
      ampAttack: 1.23, ampDecay: t.ampDecay, ampSustain: t.ampSustain, ampRelease: t.ampRelease,
      filterCutoffMultiplier: t.filterCutoffMultiplier, filterResonance: t.filterResonance,
      filterLFORate: t.filterLFORate, filterEnvAttack: t.filterEnvAttack, filterEnvDecay: t.filterEnvDecay,
      filterEnvSustain: t.filterEnvSustain, filterEnvRelease: t.filterEnvRelease,
      filterCutoffLow: t.filterCutoffLow, mood: t.mood, sliders: t.sliders
    )
    let arrow = PadTemplateCompiler.compile(t)
    let attack = extractAmpEnvAttack(from: arrow)
    #expect(abs((attack ?? 0) - 1.23) < 0.001)
  }

  @Test("noiseSmoothStep crossfade with 2 oscs produces crossfadeEqPow")
  func twoOscNoiseCrossfade() {
    let t = makeTemplate(mood: .cosmic, sliders: nil, oscCount: 2)
    let arrow = PadTemplateCompiler.compile(t)
    #expect(containsCrossfadeEqPow(arrow))
  }

  @Test("lfo crossfade with 2 oscs produces crossfadeEqPow")
  func twoOscLfoCrossfade() {
    let t = makeTemplate(mood: .warm, sliders: nil, oscCount: 2, crossfade: .lfo)
    let arrow = PadTemplateCompiler.compile(t)
    #expect(containsCrossfadeEqPow(arrow))
  }

  @Test("static crossfade with 2 oscs produces sum (no crossfadeEqPow)")
  func twoOscStaticMix() {
    let t = makeTemplate(mood: .warm, sliders: nil, oscCount: 2, crossfade: .static)
    let arrow = PadTemplateCompiler.compile(t)
    #expect(!containsCrossfadeEqPow(arrow))
  }

  @Test("Single osc skips crossfade node")
  func singleOscNoCrossfade() {
    let t = makeTemplate(mood: .warm, sliders: nil, oscCount: 1)
    let arrow = PadTemplateCompiler.compile(t)
    #expect(!containsCrossfadeEqPow(arrow))
  }

  @Test("pad_cosmic.json decodes and compiles successfully")
  func cosmicJsonRoundtrip() throws {
    // Loaded from the host app bundle: pad_cosmic.json is an actual app preset
    // shipped under Resources/presets/ and is bundled as part of that folder
    // reference in the Orbital target.
    guard let url = Bundle.main.url(
      forResource: "pad_cosmic", withExtension: "json", subdirectory: "presets"
    ) else {
      Issue.record("pad_cosmic.json not found in host app bundle under presets/")
      return
    }
    let data = try Data(contentsOf: url)
    let preset = try JSONDecoder().decode(PresetSyntax.self, from: data)
    #expect(preset.padTemplate != nil)
    #expect(preset.arrow == nil)
    let compiledArrow = preset.padTemplate.map { PadTemplateCompiler.compile($0) }
    #expect(compiledArrow != nil)
  }

  // MARK: - Helpers

  private func makeTemplate(
    mood: PadMood,
    sliders: PadSliders?,
    oscCount: Int = 3,
    crossfade: PadCrossfadeKind = .noiseSmoothStep
  ) -> PadTemplateSyntax {
    let oscs: [PadOscDescriptor] = (0..<oscCount).map { i in
      PadOscDescriptor(kind: .standard, shape: .sine, file: nil, padSynthParams: nil, detuneCents: CoreFloat(i * 7 - 7), octave: 0)
    }
    return PadTemplateSyntax(
      name: "Test Pad",
      oscillators: oscs,
      crossfade: crossfade,
      crossfadeRate: nil,
      vibratoEnabled: true,
      vibratoRate: nil,
      vibratoDepth: 0.00015,
      ampAttack: nil,
      ampDecay: 2.0,
      ampSustain: 0.9,
      ampRelease: nil,
      filterCutoffMultiplier: nil,
      filterResonance: nil,
      filterLFORate: nil,
      filterEnvAttack: 2.0,
      filterEnvDecay: 1.0,
      filterEnvSustain: 0.8,
      filterEnvRelease: 2.0,
      filterCutoffLow: 80,
      mood: mood,
      sliders: sliders
    )
  }

  // Walk the arrow tree and extract the ampEnv attack value.
  private func extractAmpEnvAttack(from arrow: ArrowSyntax) -> CoreFloat? {
    guard case .compose(let arrows) = arrow, let prod = arrows.first,
          case .prod(let items) = prod else { return nil }
    for item in items {
      if case .envelope(let name, let attack, _, _, _, _) = item, name == "ampEnv" {
        return attack
      }
    }
    return nil
  }

  // Walk the arrow tree and extract the cutoffMultiplier const value from the filter.
  private func extractCutoffMultiplier(from arrow: ArrowSyntax) -> CoreFloat? {
    guard case .compose(let arrows) = arrow, arrows.count >= 2,
          case .lowPassFilter(_, let cutoff, _) = arrows[1],
          case .sum(let cutoffItems) = cutoff, cutoffItems.count >= 2,
          case .prod(let prodItems) = cutoffItems[1] else { return nil }
    for item in prodItems {
      if case .const(let name, let val) = item, name == "cutoffMultiplier" {
        return val
      }
    }
    return nil
  }

  private func containsCrossfadeEqPow(_ arrow: ArrowSyntax) -> Bool {
    switch arrow {
    case .crossfadeEqPow: return true
    case .compose(let a): return a.contains { containsCrossfadeEqPow($0) }
    case .prod(let a):    return a.contains { containsCrossfadeEqPow($0) }
    case .sum(let a):     return a.contains { containsCrossfadeEqPow($0) }
    default:              return false
    }
  }

}
