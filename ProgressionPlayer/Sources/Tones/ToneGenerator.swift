//
//  Instrument.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation
import SwiftUI

final class Sine: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    sin(2 * .pi * fmod(t, 1.0))
  }
}

final class Triangle: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    2 * (abs((2 * fmod(t, 1.0)) - 1.0) - 0.5)
  }
}

final class Sawtooth: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    (2 * fmod(t, 1.0)) - 1.0
  }
}

final class Square: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    fmod(t, 1) <= 0.5 ? 1.0 : -1.0
  }
}

final class Noise: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    CoreFloat.random(in: 0.0...1.0)
  }
}

final class BasicOscillator: Arrow11 {
  enum OscShape: String, CaseIterable, Equatable, Hashable, Codable {
    case sine = "sineOsc"
    case triangle = "triangleOsc"
    case sawtooth = "sawtoothOsc"
    case square = "squareOsc"
    case noise = "noiseOsc"
  }
  var shape: OscShape
  var arrow: Arrow11 {
    switch shape {
    case .sine:
      Sine()
    case .triangle:
      Triangle()
    case .sawtooth:
      Sawtooth()
    case .square:
      Square()
    case .noise:
      Noise()
    }
  }
  init(shape: OscShape) {
    self.shape = shape
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    arrow.of(t)
  }
}

// see https://en.wikipedia.org/wiki/Rose_(mathematics)
final class Rose: Arrow13 {
  var amp: ArrowConst
  var leafFactor: ArrowConst
  var freq: ArrowConst
  var phase: CoreFloat
  init(amp: ArrowConst, leafFactor: ArrowConst, freq: ArrowConst, phase: CoreFloat) {
    self.amp = amp
    self.leafFactor = leafFactor
    self.freq = freq
    self.phase = phase
  }
  override func of(_ t: CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat) {
    let domain = (freq.of(t) * t) + phase
    return ( amp.of(t) * sin(leafFactor.of(t) * domain) * cos(domain), amp.of(t) * sin(leafFactor.of(t) * domain) * sin(domain), amp.of(t) * sin(domain) )
  }
}

protocol HasFactor: AnyObject {
  var factor: CoreFloat { get set }
  var arrow: Arrow11 { get set }
}

final class PreMult: Arrow11, HasFactor {
  var factor: CoreFloat
  var arrow: Arrow11
  init(factor: CoreFloat, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    arrow.of(factor * t)
  }
}

// also could be given by mult(ArrowConst(factor), Arrow11)
final class PostMult: Arrow11, HasFactor {
  var factor: CoreFloat
  var arrow: Arrow11
  init(factor: CoreFloat, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    factor * arrow.of(t)
  }
}

final class ModulatedPreMult: Arrow11, HasFactor {
  var factor: CoreFloat
  var arrow: Arrow11
  var modulation: Arrow11
  init(factor: CoreFloat, arrow: Arrow11, modulation: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    self.modulation = modulation
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    let result = arrow.of( (factor * t) + modulation.of(t))
    return result
  }
}

// TODO: use a circular buffer or finite stack to respect the lookback value
// TODO: consider removing LowPassFilter and writing it in ArrowSyntaxes w/ help of Delay
final class Delay: Arrow11 {
  var previousOutput: CoreFloat = 0.0
  var arrow: Arrow11
  init(_ arr: Arrow11, lookback: Int = 1) {
    self.arrow = arr
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    let prevVal = previousOutput
    previousOutput = arrow.of(t)
    return prevVal
  }
}

// from https://en.wikipedia.org/wiki/Low-pass_filter#Simple_infinite_impulse_response_filter
// TODO: resonance, see perhaps https://www.martin-finke.de/articles/audio-plugins-013-filter

final class LowPassFilter: Arrow11, HasFactor {
  var previousOutput: CoreFloat
  var previousTime: CoreFloat
  var factor: CoreFloat
  var resonance: CoreFloat
  var arrow: Arrow11
  init(of input: Arrow11, cutoff: CoreFloat, resonance: CoreFloat) {
    self.factor = cutoff
    self.arrow = input
    self.resonance = resonance
    self.previousTime = 0
    self.previousOutput = 0
  }

  override func of(_ t: CoreFloat) -> CoreFloat {
    let rc = 1.0 / (2 * .pi * factor)
    let dt = t - previousTime
    let alpha = dt / (rc + dt)
    let output = (alpha * arrow.of(t)) + (1 - alpha) * previousOutput
    previousOutput = output
    previousTime = t
    return output
  }
}

final class Choruser: Arrow11 {
  var chorusCentRadius: Int
  var chorusNumVoices: Int
  var arrow: ArrowWithHandles
  var valueToChorus: String
  
  init(chorusCentRadius: Int, chorusNumVoices: Int, arrow: ArrowWithHandles, valueToChorus: String) {
    self.chorusCentRadius = chorusCentRadius
    self.chorusNumVoices = chorusNumVoices
    self.arrow = arrow
    self.valueToChorus = valueToChorus
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    // set the freq and call arrow.of() repeatedly, and sum the results
    if chorusNumVoices > 1 {
      var chorusedResults: CoreFloat = 0
      if let freqArrows = arrow.namedConsts[valueToChorus] {
        let baseFreq = freqArrows.first!.val
        let spreadFreqs = chorusedFreqs(freq: baseFreq)
        for freqArrow in freqArrows {
          for freq in spreadFreqs {
            freqArrow.val = freq
            chorusedResults += arrow.of(t)
          }
          // restore
          freqArrow.val = baseFreq
        }
      }
      return chorusedResults
    } else {
      return arrow.of(t)
    }
  }
  
  // return chorusNumVoices frequencies, centered on the requested freq but spanning an interval
  // from freq - delta to freq + delta (where delta depends on freq and chorusCentRadius)
  func chorusedFreqs(freq: CoreFloat) -> [CoreFloat] {
    let cent: CoreFloat = 1.0005777895065548 // '2 ** (1/1200)' in python
    let freqRadius = freq * pow(cent, CoreFloat(chorusCentRadius)) - freq
    let freqSliver = 2 * freqRadius / CoreFloat(chorusNumVoices)
    if chorusNumVoices > 1 {
      return (0..<chorusNumVoices).map { i in
        freq - freqRadius + (CoreFloat(i) * freqSliver)
      }
    } else {
      return [freq]
    }
  }
}

final class LowPassFilter2: Arrow11 {
  private var previousOutput: CoreFloat
  private var previousTime: CoreFloat
  var cutoff: Arrow11
  var resonance: Arrow11
  var arrow: Arrow11
  init(of input: Arrow11, cutoff: Arrow11, resonance: Arrow11) {
    self.cutoff = cutoff
    self.arrow = input
    self.resonance = resonance
    self.previousTime = 0
    self.previousOutput = 0
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    let rc = 1.0 / (2 * .pi * cutoff.of(t))
    let dt = t - previousTime
    let alpha = dt / (rc + dt)
    let output = (alpha * arrow.of(t)) + (1 - alpha) * previousOutput
    previousOutput = output
    previousTime = t
    return output
  }
}

final class ArrowWithHandles: Arrow11 {
  var arrow: Arrow11
  // the handles are dictionaries with values that give access to arrows within the arrow
  var namedBasicOscs     = [String: BasicOscillator]()
  var namedLowPassFilter = [String: LowPassFilter2]()
  var namedConsts        = [String: [ArrowConst]]()
  var namedADSREnvelopes = [String: ADSR]()
  var namedChorusers     = [String: Choruser]()
  
  init(_ arrow: Arrow11) {
    self.arrow = arrow
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    arrow.of(t)
  }
  
  func withMergeDictsFromArrow(_ arr2: ArrowWithHandles) -> ArrowWithHandles {
    namedADSREnvelopes.merge(arr2.namedADSREnvelopes) { (a, b) in return a }
    namedConsts.merge(arr2.namedConsts) { (a, b) in
      return a + b
    }
    namedBasicOscs.merge(arr2.namedBasicOscs) { (a, b) in return a }
    namedLowPassFilter.merge(arr2.namedLowPassFilter) { (a, b) in return a }
    namedChorusers.merge(arr2.namedChorusers) { (a, b) in return a }
    return self
  }
  
  func withMergeDictsFromArrows(_ arrs: [ArrowWithHandles]) -> ArrowWithHandles {
    for arr in arrs {
      let _ = withMergeDictsFromArrow(arr)
    }
    return self
  }
}

enum ArrowSyntax: Codable {
  // NOTE: cases must each have a *different associated type*, as it's branched on in the Decoding logic
  case const(val: NamedFloat)
  case identity
  indirect case lowPassFilter(specs: LowPassArrowSyntax)
  indirect case unary(of: NamedArrowSyntax)
  indirect case nary(of: NamedArrowSyntaxList)
  indirect case envelope(specs: ADSRSyntax)
  indirect case choruser(specs: NamedChoruser)
  
  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  func compile() -> ArrowWithHandles {
    switch self {
    case .identity:
      return ArrowWithHandles(ArrowIdentity())
    
    case .const(let namedVal):
      let arr = ArrowConst(namedVal.val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[namedVal.name] = [arr]
      return handleArr
    
    case .lowPassFilter(let lpArrow):
      let lowerArrow = lpArrow.arrowToFilter.compile()
      let cutoffArrow = lpArrow.cutoff.compile()
      let resonanceArrow = lpArrow.resonance.compile()
      let arr = LowPassFilter2(
        of: lowerArrow,
        cutoff: cutoffArrow,
        resonance: resonanceArrow
      )
      let handleArr = ArrowWithHandles(arr)
        .withMergeDictsFromArrow(lowerArrow)
        .withMergeDictsFromArrow(cutoffArrow)
        .withMergeDictsFromArrow(resonanceArrow)
      handleArr.namedLowPassFilter[lpArrow.name] = arr
      return handleArr
      
    case .choruser(let choruserSpecs):
      let lowerArr = choruserSpecs.arrowToChorus.compile()
      let choruser = Choruser(
        chorusCentRadius: choruserSpecs.chorusCentRadius,
        chorusNumVoices: choruserSpecs.chorusNumVoices,
        arrow: lowerArr,
        valueToChorus: choruserSpecs.valueToChorus
      )
      let handleArr = ArrowWithHandles(choruser)
        .withMergeDictsFromArrow(lowerArr)
      handleArr.namedChorusers[choruserSpecs.name] = choruser
      return handleArr
    
    case .envelope(let adsr):
      let env = ADSR(envelope: EnvelopeData(
        attackTime: adsr.attack,
        decayTime: adsr.decay,
        sustainLevel: adsr.sustain,
        releaseTime: adsr.release,
        scale: adsr.scale
      ))
      let handleArr = ArrowWithHandles(env.asControl())
      handleArr.namedADSREnvelopes[adsr.name] = env
      return handleArr
    
    case .unary(let namedArrow):
      let lowerArr = namedArrow.arrow.compile()
      if namedArrow.kind == "delay" {
        let arr = Delay(lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if namedArrow.kind == "control" {
        let arr = ControlArrow11(lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if namedArrow.kind == "sin" {
        let arr = ArrowCompose(outer: ArrowSin(), inner: lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if namedArrow.kind == "cos" {
        let arr = ArrowCompose(outer: ArrowCos(), inner: lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if BasicOscillator.OscShape.allCases.map({$0.rawValue}).contains(namedArrow.kind) {
        let osc = BasicOscillator(shape: BasicOscillator.OscShape(rawValue: namedArrow.kind)!)
        let arr = ArrowCompose(outer: osc, inner: lowerArr)
        let handleArr = ArrowWithHandles(arr)
        handleArr.namedBasicOscs[namedArrow.name] = osc
        return handleArr.withMergeDictsFromArrow(lowerArr)
      } else {
        return namedArrow.arrow.compile()
      }
    
    case .nary(let namedArrows):
      let lowerArrs = namedArrows.arrows.map({$0.compile()})
      if namedArrows.name == "sum" {
        return ArrowWithHandles(ArrowSum(lowerArrs)).withMergeDictsFromArrows(lowerArrs)
      } else if namedArrows.name == "prod" {
        return ArrowWithHandles(ArrowProd(lowerArrs)).withMergeDictsFromArrows(lowerArrs)
      } else {
        return ArrowWithHandles(ArrowConst(0.0))
      }
    }
  }
}

struct LowPassArrowSyntax: Codable {
  let name: String
  let cutoff: ArrowSyntax
  let resonance: ArrowSyntax
  let arrowToFilter: ArrowSyntax
}

struct ADSRSyntax: Codable {
  let name: String
  let attack: CoreFloat
  let decay: CoreFloat
  let sustain: CoreFloat
  let release: CoreFloat
  let scale: CoreFloat
}

struct NamedArrowSyntax: Codable {
  let name: String
  let kind: String
  let arrow: ArrowSyntax
}

struct NamedArrowSyntaxList: Codable {
  let name: String
  let arrows: [ArrowSyntax]
}

struct NamedFloat: Codable {
  let name: String
  let val: CoreFloat
}

struct NamedBasicOscillatorShape: Codable {
  let name: String
  let osc: BasicOscillator.OscShape
}

struct NamedChoruser: Codable {
  let name: String
  let valueToChorus: String
  let chorusCentRadius: Int
  let chorusNumVoices: Int
  let arrowToChorus: ArrowSyntax
}
