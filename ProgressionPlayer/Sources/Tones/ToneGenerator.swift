//
//  Instrument.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation
import SwiftUI

protocol WidthHaver {
  var width: CoreFloat { get set }
}

final class Sine: Arrow11, WidthHaver {
  var width: CoreFloat = 1.0
  override func of(_ t: CoreFloat) -> CoreFloat {
    let innerResult = inner(t)
    return (fmod(innerResult, 1) < width) ? sin(2 * .pi * innerResult / width) : 0
  }
}

final class Triangle: Arrow11, WidthHaver {
  var width: CoreFloat = 1
  override func of(_ t: CoreFloat) -> CoreFloat {
    let innerResult = inner(t)
    return (fmod(innerResult, 1) < width/2) ? (2 * fmod(innerResult, 1) / width) :
      (fmod(innerResult, 1) < width) ? (-2 * fmod(innerResult, 1) / width) + 2 : 0
  }
}

final class Sawtooth: Arrow11, WidthHaver {
  var width: CoreFloat = 1
  override func of(_ t: CoreFloat) -> CoreFloat {
    let innerResult = inner(t)
    return (fmod(innerResult, 1) < width) ? (fmod(innerResult, 1) / width) : 0
  }
}

final class Square: Arrow11, WidthHaver {
  var width: CoreFloat = 1 // for square, a width of 1 means half the time it's 1 and half is 0
  override func of(_ t: CoreFloat) -> CoreFloat {
    fmod(inner(t), 1) <= width/2 ? 1.0 : -1.0
  }
}

final class Noise: Arrow11, WidthHaver {
  var width: CoreFloat = 1
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
  var shape: OscShape {
    didSet {
      arrow = Self.arrForShape(shape: shape)
    }
  }
  var width: CoreFloat {
    didSet {
      arrow.width = width
    }
  }
  var arrow: Arrow11 & WidthHaver
  
  init(shape: OscShape, width: CoreFloat = 1) {
    self.shape = shape
    self.arrow = Self.arrForShape(shape: shape)
    self.width = width
    super.init()
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    arrow.of(inner(t))
  }
  
  static func arrForShape(shape: OscShape) -> Arrow11 & WidthHaver {
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

final class Choruser: Arrow11 {
  var chorusCentRadius: Int
  var chorusNumVoices: Int
  var valueToChorus: String
  
  init(chorusCentRadius: Int, chorusNumVoices: Int, valueToChorus: String) {
    self.chorusCentRadius = chorusCentRadius
    self.chorusNumVoices = chorusNumVoices
    self.valueToChorus = valueToChorus
    super.init()
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    // set the freq and call arrow.of() repeatedly, and sum the results
    if chorusNumVoices > 1 {
      var chorusedResults: CoreFloat = 0
      // get the constants of the given name (it is an array, as we have some duplication in the json)
      if let innerArrowWithHandles = innerArr as? ArrowWithHandles {
        if let freqArrows = innerArrowWithHandles.namedConsts[valueToChorus] {
          let baseFreq = freqArrows.first!.val
          let spreadFreqs = chorusedFreqs(freq: baseFreq)
          for freqArrow in freqArrows {
            for freq in spreadFreqs {
              freqArrow.val = freq
              chorusedResults += inner(t)
            }
            // restore
            freqArrow.val = baseFreq
          }
        }
        return chorusedResults
      } else {
        return inner(t)
      }
    } else {
      return inner(t)
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

// from https://en.wikipedia.org/wiki/Low-pass_filter#Simple_infinite_impulse_response_filter
// TODO: resonance, see perhaps https://www.martin-finke.de/articles/audio-plugins-013-filter
final class LowPassFilter2: Arrow11 {
  private var previousOutput: CoreFloat
  private var previousTime: CoreFloat
  var cutoff: Arrow11
  var resonance: Arrow11
  init(cutoff: Arrow11, resonance: Arrow11) {
    self.cutoff = cutoff
    self.resonance = resonance
    self.previousTime = 0
    self.previousOutput = 0
    super.init()
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    let rc = 1.0 / (2 * .pi * cutoff.of(t))
    let dt = t - previousTime
    let alpha = dt / (rc + dt)
    let output = (alpha * (inner(t))) + (1 - alpha) * previousOutput
    previousOutput = output
    previousTime = t
    return output
  }
}

final class ArrowWithHandles: Arrow11 {
  // the handles are dictionaries with values that give access to arrows within the arrow
  var namedBasicOscs     = [String: BasicOscillator]()
  var namedLowPassFilter = [String: LowPassFilter2]()
  var namedConsts        = [String: [ArrowConst]]()
  var namedADSREnvelopes = [String: ADSR]()
  var namedChorusers     = [String: Choruser]()

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
  indirect case control(of: ArrowSyntax)
  indirect case prod(of: [ArrowSyntax])
  indirect case compose(arrows: [ArrowSyntax])
  indirect case sum(of: [ArrowSyntax])
  indirect case envelope(specs: ADSRSyntax)
  indirect case choruser(specs: NamedChoruser)
  indirect case osc(name: String, shape: BasicOscillator.OscShape)
  
  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  func compile() -> ArrowWithHandles {
    switch self {
    case .compose(let arrows):
      // it seems natural to me for the chain to be listed from innermost to outermost (first-to-last)
      let lowerArrs = arrows.map({$0.compile()})
      var composition: ArrowWithHandles? = nil
      for lowerArr in lowerArrs {
        lowerArr.innerArr = composition
        // do something more with the innerArr, which is a whole-ass ArrowWithHandles
        composition = lowerArr
      }
      return composition!.withMergeDictsFromArrows(lowerArrs)
    case .osc(let oscName, let oscShape):
      let osc = BasicOscillator(shape: oscShape)
      let arr = ArrowWithHandles(innerArr: osc)
      arr.namedBasicOscs[oscName] = osc
      return arr
    case .control(let arrow):
      let lowerArr = arrow.compile()
      let arr = ControlArrow11(innerArr: lowerArr)
      return ArrowWithHandles(innerArr: arr).withMergeDictsFromArrow(lowerArr)
    case .identity:
      return ArrowWithHandles(innerArr: ArrowIdentity())
    case .prod(let arrows):
      let lowerArrs = arrows.map({$0.compile()})
      return ArrowWithHandles(
        innerArr: ArrowProd(
          innerArrs: ContiguousArray<Arrow11>(lowerArrs)
        )).withMergeDictsFromArrows(lowerArrs)
    case .sum(let arrows):
      let lowerArrs = arrows.map({$0.compile()})
      return ArrowWithHandles(
        innerArr: ArrowSum(
          innerArrs: lowerArrs
        )
      ).withMergeDictsFromArrows(lowerArrs)

    case .const(let namedVal):
      let arr = ArrowConst(value: namedVal.val) // separate copy, even if same name as a node elsewhere
      let handleArr = ArrowWithHandles(innerArr: arr)
      handleArr.namedConsts[namedVal.name] = [arr]
      return handleArr
    
    case .lowPassFilter(let lpArrow):
      let cutoffArrow = lpArrow.cutoff.compile()
      let resonanceArrow = lpArrow.resonance.compile()
      let arr = LowPassFilter2(
        cutoff: cutoffArrow,
        resonance: resonanceArrow
      )
      let handleArr = ArrowWithHandles(innerArr: arr)
        .withMergeDictsFromArrow(cutoffArrow)
        .withMergeDictsFromArrow(resonanceArrow)
      handleArr.namedLowPassFilter[lpArrow.name] = arr
      return handleArr
      
    case .choruser(let choruserSpecs):
      let choruser = Choruser(
        chorusCentRadius: choruserSpecs.chorusCentRadius,
        chorusNumVoices: choruserSpecs.chorusNumVoices,
        valueToChorus: choruserSpecs.valueToChorus
      )
      let handleArr = ArrowWithHandles(innerArr: choruser)
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
      let handleArr = ArrowWithHandles(innerArr: env.asControl())
      handleArr.namedADSREnvelopes[adsr.name] = env
      return handleArr
    
    }
  }
}

struct LowPassArrowSyntax: Codable {
  let name: String
  let cutoff: ArrowSyntax
  let resonance: ArrowSyntax
}

struct ADSRSyntax: Codable {
  let name: String
  let attack: CoreFloat
  let decay: CoreFloat
  let sustain: CoreFloat
  let release: CoreFloat
  let scale: CoreFloat
}

struct NamedFloat: Codable {
  let name: String
  let val: CoreFloat
}

struct NamedChoruser: Codable {
  let name: String
  let valueToChorus: String
  let chorusCentRadius: Int
  let chorusNumVoices: Int
}
