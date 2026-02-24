//
//  ArrowSyntax.swift
//  Orbital
//
//  Extracted from ToneGenerator.swift
//

import Foundation

enum ArrowSyntax: Equatable {
  case const(name: String, val: CoreFloat)
  case constOctave(name: String, val: CoreFloat)
  case constCent(name: String, val: CoreFloat)
  case identity
  case control
  indirect case lowPassFilter(name: String, cutoff: ArrowSyntax, resonance: ArrowSyntax)
  indirect case prod(of: [ArrowSyntax])
  indirect case compose(arrows: [ArrowSyntax])
  indirect case sum(of: [ArrowSyntax])
  indirect case crossfade(of: [ArrowSyntax], name: String, mixPoint: ArrowSyntax)
  indirect case crossfadeEqPow(of: [ArrowSyntax], name: String, mixPoint: ArrowSyntax)
  indirect case envelope(name: String, attack: CoreFloat, decay: CoreFloat, sustain: CoreFloat, release: CoreFloat, scale: CoreFloat)
  case choruser(name: String, valueToChorus: String, chorusCentRadius: Int, chorusNumVoices: Int)
  case noiseSmoothStep(noiseFreq: CoreFloat, min: CoreFloat, max: CoreFloat)
  case rand(min: CoreFloat, max: CoreFloat)
  case exponentialRand(min: CoreFloat, max: CoreFloat)
  case line(duration: CoreFloat, min: CoreFloat, max: CoreFloat)
  case reciprocalConst(name: String, val: CoreFloat)
  indirect case reciprocal(of: ArrowSyntax)
  case eventNote
  case eventVelocity
  case libraryArrow(name: String)
  case emitterValue(name: String)
  case quickExpression(String)
  
  indirect case osc(name: String, shape: BasicOscillator.OscShape, width: ArrowSyntax)
}

// MARK: - ArrowSyntax Codable

extension ArrowSyntax: Codable {

  private enum CaseKey: String, CodingKey {
    case const, constOctave, constCent, identity, control
    case lowPassFilter, prod, compose, sum
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
  private struct CrossfadePayload: Codable, Equatable { let of: [ArrowSyntax]; let name: String; let mixPoint: ArrowSyntax }
  private struct EnvelopePayload: Codable, Equatable { let name: String; let attack: CoreFloat; let decay: CoreFloat; let sustain: CoreFloat; let release: CoreFloat; let scale: CoreFloat }
  private struct ChoruserPayload: Codable, Equatable { let name: String; let valueToChorus: String; let chorusCentRadius: Int; let chorusNumVoices: Int }
  private struct NoiseSmoothStepPayload: Codable, Equatable { let noiseFreq: CoreFloat; let min: CoreFloat; let max: CoreFloat }
  private struct MinMaxPayload: Codable, Equatable { let min: CoreFloat; let max: CoreFloat }
  private struct LinePayload: Codable, Equatable { let duration: CoreFloat; let min: CoreFloat; let max: CoreFloat }
  private struct OscPayload: Codable, Equatable { let name: String; let shape: BasicOscillator.OscShape; let width: ArrowSyntax }
  private struct NameOnly: Codable, Equatable { let name: String }
  // Legacy wrapper for backward-compat decoding of {"prod": {"of": [...]}}
  private struct LegacyArrayOf: Codable { let of: [ArrowSyntax] }
  private struct LegacyArrayArrows: Codable { let arrows: [ArrowSyntax] }
  private struct LegacyReciprocalOf: Codable { let of: ArrowSyntax }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CaseKey.self)

    if container.contains(.prod) {
      // New: {"prod": [...]}  Old: {"prod": {"of": [...]}}
      if let arr = try? container.decode([ArrowSyntax].self, forKey: .prod) {
        self = .prod(of: arr)
      } else {
        let legacy = try container.decode(LegacyArrayOf.self, forKey: .prod)
        self = .prod(of: legacy.of)
      }
    } else if container.contains(.sum) {
      if let arr = try? container.decode([ArrowSyntax].self, forKey: .sum) {
        self = .sum(of: arr)
      } else {
        let legacy = try container.decode(LegacyArrayOf.self, forKey: .sum)
        self = .sum(of: legacy.of)
      }
    } else if container.contains(.compose) {
      if let arr = try? container.decode([ArrowSyntax].self, forKey: .compose) {
        self = .compose(arrows: arr)
      } else {
        let legacy = try container.decode(LegacyArrayArrows.self, forKey: .compose)
        self = .compose(arrows: legacy.arrows)
      }
    } else if container.contains(.reciprocal) {
      if let inner = try? container.decode(ArrowSyntax.self, forKey: .reciprocal) {
        self = .reciprocal(of: inner)
      } else {
        let legacy = try container.decode(LegacyReciprocalOf.self, forKey: .reciprocal)
        self = .reciprocal(of: legacy.of)
      }
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

// MARK: - ArrowSyntax Compilation & Tree Operations

extension ArrowSyntax {
  
  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  func compile(library: [String: ArrowSyntax] = [:]) -> ArrowWithHandles {
    if !library.isEmpty {
      return resolveLibrary(library).compile()
    }
    switch self {
    case .rand(let min, let max):
      let rand = ArrowRandom(min: min, max: max)
      return ArrowWithHandles(rand)
    case .exponentialRand(let min, let max):
      let expRand = ArrowExponentialRandom(min: min, max: max)
      return ArrowWithHandles(expRand)
    case .noiseSmoothStep(let noiseFreq, let min, let max):
      let noise = NoiseSmoothStep(noiseFreq: noiseFreq, min: min, max: max)
      return ArrowWithHandles(noise)
    case .line(let duration, let min, let max):
      let line = ArrowLine(start: min, end: max, duration: duration)
      return ArrowWithHandles(line)
    case .compose(let specs):
      // it seems natural to me for the chain to be listed from innermost to outermost (first-to-last)
      let arrows = specs.map({$0.compile()})
      var composition: ArrowWithHandles? = nil
      for arrow in arrows {
        arrow.wrappedArrow.innerArr = composition
        if composition != nil {
          let _ = arrow.withMergeDictsFromArrow(composition!) // provide each step of composition with all the handles
        }
        composition = arrow
      }
      return composition!
    case .osc(let oscName, let oscShape, let widthArr):
      let osc = BasicOscillator(shape: oscShape, widthArr: widthArr.compile())
      let arr = ArrowWithHandles(osc)
      arr.namedBasicOscs[oscName] = [osc]
      return arr
    case .control:
      return ArrowWithHandles(ControlArrow11())
    case .identity:
      return ArrowWithHandles(ArrowIdentity())
    case .prod(let arrows):
      let lowerArrs = arrows.map({$0.compile()})
      return ArrowWithHandles(
        ArrowProd(
          innerArrs: ContiguousArray<Arrow11>(lowerArrs)
        )).withMergeDictsFromArrows(lowerArrs)
    case .sum(let arrows):
      let lowerArrs = arrows.map({$0.compile()})
      return ArrowWithHandles(
        ArrowSum(
          innerArrs: lowerArrs
        )
      ).withMergeDictsFromArrows(lowerArrs)
    case .crossfade(let arrows, let name, let mixPointArr):
      let lowerArrs = arrows.map({$0.compile()})
      let arr = ArrowCrossfade(
        innerArrs: lowerArrs,
        mixPointArr: mixPointArr.compile()
      )
      let arrH = ArrowWithHandles(arr).withMergeDictsFromArrows(lowerArrs)
      if var crossfaders = arrH.namedCrossfaders[name] {
        crossfaders.append(arr)
      } else {
        arrH.namedCrossfaders[name] = [arr]
      }
      return arrH
    case .crossfadeEqPow(let arrows, let name, let mixPointArr):
      let lowerArrs = arrows.map({$0.compile()})
      let arr = ArrowEqualPowerCrossfade(
        innerArrs: lowerArrs,
        mixPointArr: mixPointArr.compile()
      )
      let arrH = ArrowWithHandles(arr).withMergeDictsFromArrows(lowerArrs)
      if var crossfaders = arrH.namedCrossfadersEqPow[name] {
        crossfaders.append(arr)
      } else {
        arrH.namedCrossfadersEqPow[name] = [arr]
      }
      return arrH
    case .const(let name, let val):
      let arr = ArrowConst(value: val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr
    case .constOctave(let name, let val):
      let arr = ArrowConstOctave(value: val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr
    case .constCent(let name, let val):
      let arr = ArrowConstCent(value: val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr
    case .lowPassFilter(let name, let cutoff, let resonance):
      let cutoffArrow = cutoff.compile()
      let resonanceArrow = resonance.compile()
      let arr = LowPassFilter2(
        cutoff: cutoffArrow,
        resonance: resonanceArrow
      )
      let handleArr = ArrowWithHandles(arr)
        .withMergeDictsFromArrow(cutoffArrow)
        .withMergeDictsFromArrow(resonanceArrow)
      if var filters = handleArr.namedLowPassFilter[name] {
        filters.append(arr)
      } else {
        handleArr.namedLowPassFilter[name] = [arr]
      }
      return handleArr
      
    case .choruser(let name, let valueToChorus, let chorusCentRadius, let chorusNumVoices):
      let choruser = Choruser(
        chorusCentRadius: chorusCentRadius,
        chorusNumVoices: chorusNumVoices,
        valueToChorus: valueToChorus
      )
      let handleArr = ArrowWithHandles(choruser)
      if var chorusers = handleArr.namedChorusers[name] {
        chorusers.append(choruser)
      } else {
        handleArr.namedChorusers[name] = [choruser]
      }
      return handleArr
    
    case .envelope(let name, let attack, let decay, let sustain, let release, let scale):
      let env = ADSR(envelope: EnvelopeData(
        attackTime: attack,
        decayTime: decay,
        sustainLevel: sustain,
        releaseTime: release,
        scale: scale
      ))
      let handleArr = ArrowWithHandles(env.asControl())
      if var envs = handleArr.namedADSREnvelopes[name] {
        envs.append(env)
      } else {
        handleArr.namedADSREnvelopes[name] = [env]
      }
      return handleArr

    case .reciprocalConst(let name, let val):
      let arr = ArrowConstReciprocal(value: val)
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[name] = [arr]
      return handleArr

    case .reciprocal(of: let inner):
      let innerCompiled = inner.compile()
      let arr = ArrowReciprocal()
      arr.innerArr = innerCompiled.wrappedArrow
      return ArrowWithHandles(arr).withMergeDictsFromArrow(innerCompiled)

    case .eventNote:
      let arr = EventUsingArrow(ofEvent: { event, _ in
        CoreFloat(event.notes[0].note)
      })
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedEventUsing[""] = [arr]
      return handleArr

    case .eventVelocity:
      let arr = EventUsingArrow(ofEvent: { event, _ in
        CoreFloat(event.notes[0].velocity) / 127.0
      })
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedEventUsing[""] = [arr]
      return handleArr

    case .libraryArrow(let name):
      fatalError("libraryArrow '\(name)' was not resolved — call resolveLibrary() before compile()")

    case .emitterValue(let name):
      let arr = ArrowConst(value: 0)
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedEmitterValues[name] = [arr]
      return handleArr

    case .quickExpression(let expr):
      // Parse the expression into an ArrowSyntax tree, then compile that tree.
      // If the expression is invalid, fall back to a zero constant so
      // playback doesn't crash — the UI validates before saving.
      guard let parsed = try? QuickParser.parse(expr) else {
        print("QuickParser: failed to parse '\(expr)', falling back to 0")
        return ArrowSyntax.const(name: "_error", val: 0).compile()
      }
      return parsed.compile()
    }
  }

  /// Replace every `.libraryArrow` reference with its definition from the
  /// library dictionary. The dictionary values should already be resolved
  /// (no remaining `.libraryArrow` nodes), which is guaranteed when the
  /// caller builds the dict in order and resolves each entry against the
  /// dict-so-far.
  /// Applies `transform` to every ArrowSyntax child, returning a structurally
  /// identical node with transformed children. Leaf cases return self unchanged.
  func mapChildren(_ transform: (ArrowSyntax) -> ArrowSyntax) -> ArrowSyntax {
    switch self {
    case .prod(let arrows):
      return .prod(of: arrows.map(transform))
    case .compose(let arrows):
      return .compose(arrows: arrows.map(transform))
    case .sum(let arrows):
      return .sum(of: arrows.map(transform))
    case .crossfade(let arrows, let name, let mixPoint):
      return .crossfade(of: arrows.map(transform), name: name, mixPoint: transform(mixPoint))
    case .crossfadeEqPow(let arrows, let name, let mixPoint):
      return .crossfadeEqPow(of: arrows.map(transform), name: name, mixPoint: transform(mixPoint))
    case .lowPassFilter(let name, let cutoff, let resonance):
      return .lowPassFilter(name: name, cutoff: transform(cutoff), resonance: transform(resonance))
    case .osc(let name, let shape, let width):
      return .osc(name: name, shape: shape, width: transform(width))
    case .reciprocal(let inner):
      return .reciprocal(of: transform(inner))
    case .const, .constOctave, .constCent, .reciprocalConst,
         .identity, .control, .envelope, .choruser,
         .noiseSmoothStep, .rand, .exponentialRand, .line,
         .eventNote, .eventVelocity, .libraryArrow, .emitterValue,
         .quickExpression:
      return self
    }
  }

  // This pattern is going to *copy* each referenced library arrow whenever it is asked for later
  // In future we may want to make the compiled arrow into a DAG.
  // But that will require more design around how to handle a node being called twice by other nodes.
  func resolveLibrary(_ library: [String: ArrowSyntax]) -> ArrowSyntax {
    switch self {
    case .libraryArrow(let name):
      guard let definition = library[name] else {
        fatalError("Unknown library arrow '\(name)'. Available: \(library.keys.sorted())")
      }
      return definition
    default:
      return mapChildren { $0.resolveLibrary(library) }
    }
  }
}

#if os(iOS)
import SwiftUI
#Preview {
  let osc = Triangle()
  osc.innerArr = ArrowIdentity()
  return ArrowChart(arrow: osc, ymin: -2, ymax: 2)
}
#endif
