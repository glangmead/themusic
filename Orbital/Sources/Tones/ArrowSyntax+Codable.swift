//
//  ArrowSyntax+Codable.swift
//  Orbital
//
//  JSON serialization for ArrowSyntax, including legacy format migration.
//  Extracted from ArrowSyntax.swift.
//

import Foundation

// MARK: - ArrowSyntax Codable

extension ArrowSyntax: Codable {

  private enum CaseKey: String, CodingKey {
    case const, constOctave, constCent, identity, control
    case lowPassFilter, combFilter, prod, compose, sum
    case crossfade, crossfadeEqPow
    case envelope, choruser, noiseSmoothStep
    case rand, exponentialRand, line
    case reciprocalConst, reciprocal
    case eventNote, eventVelocity
    case libraryArrow, emitterValue, quickExpression, osc
  }

  // Payloads for multi-field cases
  private struct NameVal: Codable, Equatable { let name: String; let val: CoreFloat }
  private struct LowPassPayload: Codable, Equatable { let name: String; let cutoff: ArrowSyntax; let resonance: ArrowSyntax }
  private struct CombFilterPayload: Codable, Equatable { let name: String; let frequency: ArrowSyntax; let feedback: ArrowSyntax }
  private struct CrossfadePayload: Codable, Equatable { let of: [ArrowSyntax]; let name: String; let mixPoint: ArrowSyntax }
  private struct EnvelopePayload: Codable, Equatable { let name: String; let attack: CoreFloat; let decay: CoreFloat; let sustain: CoreFloat; let release: CoreFloat; let scale: CoreFloat }
  private struct ChoruserPayload: Codable, Equatable { let name: String; let valueToChorus: String; let chorusCentRadius: Int; let chorusNumVoices: Int }
  private struct NoiseSmoothStepPayload: Codable, Equatable { let noiseFreq: CoreFloat; let min: CoreFloat; let max: CoreFloat }
  private struct MinMaxPayload: Codable, Equatable { let min: CoreFloat; let max: CoreFloat }
  private struct LinePayload: Codable, Equatable { let duration: CoreFloat; let min: CoreFloat; let max: CoreFloat }
  private struct OscPayload: Codable, Equatable { let name: String; let shape: BasicOscillator.OscShape; let width: ArrowSyntax }
  private struct NameOnly: Codable, Equatable { let name: String }

  // swiftlint:disable:next cyclomatic_complexity
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CaseKey.self)

    if container.contains(.prod) {
      self = .prod(of: try container.decode([ArrowSyntax].self, forKey: .prod))
    } else if container.contains(.sum) {
      self = .sum(of: try container.decode([ArrowSyntax].self, forKey: .sum))
    } else if container.contains(.compose) {
      self = .compose(arrows: try container.decode([ArrowSyntax].self, forKey: .compose))
    } else if container.contains(.reciprocal) {
      self = .reciprocal(of: try container.decode(ArrowSyntax.self, forKey: .reciprocal))
    } else if container.contains(.const) {
      let p = try container.decode(NameVal.self, forKey: .const)
      self = .const(name: p.name, val: p.val)
    } else if container.contains(.constOctave) {
      let p = try container.decode(NameVal.self, forKey: .constOctave)
      self = .constOctave(name: p.name, val: p.val)
    } else if container.contains(.constCent) {
      let p = try container.decode(NameVal.self, forKey: .constCent)
      self = .constCent(name: p.name, val: p.val)
    } else if container.contains(.identity) {
      self = .identity
    } else if container.contains(.control) {
      self = .control
    } else if container.contains(.lowPassFilter) {
      let p = try container.decode(LowPassPayload.self, forKey: .lowPassFilter)
      self = .lowPassFilter(name: p.name, cutoff: p.cutoff, resonance: p.resonance)
    } else if container.contains(.combFilter) {
      let p = try container.decode(CombFilterPayload.self, forKey: .combFilter)
      self = .combFilter(name: p.name, frequency: p.frequency, feedback: p.feedback)
    } else if container.contains(.crossfade) {
      let p = try container.decode(CrossfadePayload.self, forKey: .crossfade)
      self = .crossfade(of: p.of, name: p.name, mixPoint: p.mixPoint)
    } else if container.contains(.crossfadeEqPow) {
      let p = try container.decode(CrossfadePayload.self, forKey: .crossfadeEqPow)
      self = .crossfadeEqPow(of: p.of, name: p.name, mixPoint: p.mixPoint)
    } else if container.contains(.envelope) {
      let p = try container.decode(EnvelopePayload.self, forKey: .envelope)
      self = .envelope(name: p.name, attack: p.attack, decay: p.decay, sustain: p.sustain, release: p.release, scale: p.scale)
    } else if container.contains(.choruser) {
      let p = try container.decode(ChoruserPayload.self, forKey: .choruser)
      self = .choruser(name: p.name, valueToChorus: p.valueToChorus, chorusCentRadius: p.chorusCentRadius, chorusNumVoices: p.chorusNumVoices)
    } else if container.contains(.noiseSmoothStep) {
      let p = try container.decode(NoiseSmoothStepPayload.self, forKey: .noiseSmoothStep)
      self = .noiseSmoothStep(noiseFreq: p.noiseFreq, min: p.min, max: p.max)
    } else if container.contains(.rand) {
      let p = try container.decode(MinMaxPayload.self, forKey: .rand)
      self = .rand(min: p.min, max: p.max)
    } else if container.contains(.exponentialRand) {
      let p = try container.decode(MinMaxPayload.self, forKey: .exponentialRand)
      self = .exponentialRand(min: p.min, max: p.max)
    } else if container.contains(.line) {
      let p = try container.decode(LinePayload.self, forKey: .line)
      self = .line(duration: p.duration, min: p.min, max: p.max)
    } else if container.contains(.reciprocalConst) {
      let p = try container.decode(NameVal.self, forKey: .reciprocalConst)
      self = .reciprocalConst(name: p.name, val: p.val)
    } else if container.contains(.eventNote) {
      self = .eventNote
    } else if container.contains(.eventVelocity) {
      self = .eventVelocity
    } else if container.contains(.libraryArrow) {
      let p = try container.decode(NameOnly.self, forKey: .libraryArrow)
      self = .libraryArrow(name: p.name)
    } else if container.contains(.emitterValue) {
      let p = try container.decode(NameOnly.self, forKey: .emitterValue)
      self = .emitterValue(name: p.name)
    } else if container.contains(.quickExpression) {
      let expr = try container.decode(String.self, forKey: .quickExpression)
      self = .quickExpression(expr)
    } else if container.contains(.osc) {
      let p = try container.decode(OscPayload.self, forKey: .osc)
      self = .osc(name: p.name, shape: p.shape, width: p.width)
    } else {
      throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Unknown ArrowSyntax case. Keys: \(container.allKeys)"))
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CaseKey.self)
    switch self {
    case .prod(let arr):
      try container.encode(arr, forKey: .prod)
    case .sum(let arr):
      try container.encode(arr, forKey: .sum)
    case .compose(let arr):
      try container.encode(arr, forKey: .compose)
    case .reciprocal(let inner):
      try container.encode(inner, forKey: .reciprocal)
    case .const(let name, let val):
      try container.encode(NameVal(name: name, val: val), forKey: .const)
    case .constOctave(let name, let val):
      try container.encode(NameVal(name: name, val: val), forKey: .constOctave)
    case .constCent(let name, let val):
      try container.encode(NameVal(name: name, val: val), forKey: .constCent)
    case .identity:
      try container.encode([String: String](), forKey: .identity)
    case .control:
      try container.encode([String: String](), forKey: .control)
    case .lowPassFilter(let name, let cutoff, let resonance):
      try container.encode(LowPassPayload(name: name, cutoff: cutoff, resonance: resonance), forKey: .lowPassFilter)
    case .combFilter(let name, let frequency, let feedback):
      try container.encode(CombFilterPayload(name: name, frequency: frequency, feedback: feedback), forKey: .combFilter)
    case .crossfade(let of, let name, let mixPoint):
      try container.encode(CrossfadePayload(of: of, name: name, mixPoint: mixPoint), forKey: .crossfade)
    case .crossfadeEqPow(let of, let name, let mixPoint):
      try container.encode(CrossfadePayload(of: of, name: name, mixPoint: mixPoint), forKey: .crossfadeEqPow)
    case .envelope(let name, let attack, let decay, let sustain, let release, let scale):
      try container.encode(EnvelopePayload(name: name, attack: attack, decay: decay, sustain: sustain, release: release, scale: scale), forKey: .envelope)
    case .choruser(let name, let valueToChorus, let chorusCentRadius, let chorusNumVoices):
      try container.encode(ChoruserPayload(name: name, valueToChorus: valueToChorus, chorusCentRadius: chorusCentRadius, chorusNumVoices: chorusNumVoices), forKey: .choruser)
    case .noiseSmoothStep(let noiseFreq, let min, let max):
      try container.encode(NoiseSmoothStepPayload(noiseFreq: noiseFreq, min: min, max: max), forKey: .noiseSmoothStep)
    case .rand(let min, let max):
      try container.encode(MinMaxPayload(min: min, max: max), forKey: .rand)
    case .exponentialRand(let min, let max):
      try container.encode(MinMaxPayload(min: min, max: max), forKey: .exponentialRand)
    case .line(let duration, let min, let max):
      try container.encode(LinePayload(duration: duration, min: min, max: max), forKey: .line)
    case .reciprocalConst(let name, let val):
      try container.encode(NameVal(name: name, val: val), forKey: .reciprocalConst)
    case .eventNote:
      try container.encode([String: String](), forKey: .eventNote)
    case .eventVelocity:
      try container.encode([String: String](), forKey: .eventVelocity)
    case .libraryArrow(let name):
      try container.encode(NameOnly(name: name), forKey: .libraryArrow)
    case .emitterValue(let name):
      try container.encode(NameOnly(name: name), forKey: .emitterValue)
    case .quickExpression(let expr):
      try container.encode(expr, forKey: .quickExpression)
    case .osc(let name, let shape, let width):
      try container.encode(OscPayload(name: name, shape: shape, width: width), forKey: .osc)
    }
  }
}
