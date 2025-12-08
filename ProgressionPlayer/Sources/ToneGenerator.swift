//
//  Instrument.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation
import SwiftUI

let Sine = Arrow11(of: {
  sin(2 * .pi * fmod($0, 1.0))
})

let Triangle = Arrow11(of: { x in
  2 * (abs((2 * fmod(x, 1.0)) - 1.0) - 0.5)
})

let Sawtooth = Arrow11(of: { x in
  (2 * fmod(x, 1.0)) - 1.0
})

let Square = Arrow11(of: { x in
  fmod(x, 1) <= 0.5 ? 1.0 : -1.0
})

let Noise = Arrow11(of: { x in
  CoreFloat.random(in: 0.0...1.0)
})

class BasicOscillator: Arrow11 {
  enum OscShape: String, CaseIterable, Equatable, Hashable, Decodable {
    case sine = "sineOsc"
    case triangle = "triangleOsc"
    case sawtooth = "sawtoothOsc"
    case square = "squareOsc"
    case noise = "noiseOsc"
  }
  var shape: OscShape
  var oscShapeBindings = [String: Binding<OscShape>]()
  var arrow: Arrow11 {
    switch shape {
    case .sine:
      Sine
    case .triangle:
      Triangle
    case .sawtooth:
      Sawtooth
    case .square:
      Square
    case .noise:
      Noise
    }
  }
  init(shape: OscShape) {
    self.shape = shape
    var fself: BasicOscillator? = nil
    super.init(of: { t in
      fself!.arrow.of(t)
    })
    fself = self
  }
}

// see https://en.wikipedia.org/wiki/Rose_(mathematics)
class Rose: Arrow13 {
  var amp: Arrow11
  var leafFactor: Arrow11
  var freq: Arrow11
  var phase: CoreFloat
  init(amp: Arrow11, leafFactor: Arrow11, freq: Arrow11, phase: CoreFloat) {
    self.amp = amp
    self.leafFactor = leafFactor
    self.freq = freq
    self.phase = phase
    super.init(of: { x in
      let domain = (freq.of(x) * x) + phase
      return ( amp.of(x) * sin(leafFactor.of(x) * domain) * cos(domain), amp.of(x) * sin(leafFactor.of(x) * domain) * sin(domain), amp.of(x) * sin(domain) )
    })
  }
  
}

protocol HasFactor {
  var factor: CoreFloat { get set }
  var arrow: Arrow11 { get set }
}

class PreMult: Arrow11, HasFactor {
  var factor: CoreFloat
  var arrow: Arrow11
  init(factor: CoreFloat, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    weak var futureSelf: PreMult? = nil
    super.init(of: { x in
      return futureSelf!.arrow.of(futureSelf!.factor * x)
    })
    futureSelf = self
  }
}

// also could be given by mult(ArrowConst(factor), Arrow11)
class PostMult: Arrow11, HasFactor {
  var factor: CoreFloat
  var arrow: Arrow11
  init(factor: CoreFloat, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    weak var fself: PostMult? = nil
    super.init(of: { x in
      return fself!.factor * fself!.arrow.of(x)
    })
    fself = self
  }
}

class ModulatedPreMult: Arrow11, HasFactor {
  var factor: CoreFloat
  var arrow: Arrow11
  var modulation: Arrow11
  init(factor: CoreFloat, arrow: Arrow11, modulation: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    self.modulation = modulation
    weak var fself: ModulatedPreMult? = nil // future self
    super.init(of: { x in
      let result = fself!.arrow.of( (fself!.factor * x) + fself!.modulation.of(x))
      return result
    })
    fself = self
  }
}

// TODO: use a circular buffer or finite stack to respect the lookback value
// TODO: consider removing LowPassFilter and writing it in ArrowSyntaxes w/ help of Delay
class Delay: Arrow11 {
  var previousOutput: CoreFloat = 0.0
  var arrow: Arrow11
  init(_ arr: Arrow11, lookback: Int = 1) {
    self.arrow = arr
    weak var fself: Delay? = nil
    super.init(of: { t in
      let prevVal = fself!.previousOutput
      fself!.previousOutput = fself!.arrow.of(t)
      return prevVal
    })
    fself = self
  }
}

// from https://en.wikipedia.org/wiki/Low-pass_filter#Simple_infinite_impulse_response_filter
// TODO: resonance, see perhaps https://www.martin-finke.de/articles/audio-plugins-013-filter

class LowPassFilter: Arrow11, HasFactor {
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

    weak var fself: LowPassFilter? = nil
    super.init(of: { t in
      let rc = 1.0 / (2 * .pi * fself!.factor)
      let dt = t - fself!.previousTime
      let alpha = dt / (rc + dt)
      let output = (alpha * fself!.arrow.of(t)) + (1 - alpha) * fself!.previousOutput
      fself!.previousOutput = output
      fself!.previousTime = t
      return output
    })
    fself = self
  }
}

class LowPassFilter2: Arrow11 {
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
    
    weak var fself: LowPassFilter2? = nil
    super.init(of: { t in
      let rc = 1.0 / (2 * .pi * fself!.cutoff.of(t))
      let dt = t - fself!.previousTime
      let alpha = dt / (rc + dt)
      let output = (alpha * fself!.arrow.of(t)) + (1 - alpha) * fself!.previousOutput
      fself!.previousOutput = output
      fself!.previousTime = t
      return output
    })
    fself = self
  }
}

class ArrowWithHandles: Arrow11 {
  // the handles are dictionaries with values that give access to arrows within the arrow
  var namedBasicOscs     = [String: BasicOscillator]()
  var namedLowPassFilter = [String: LowPassFilter2]()
  var namedConsts        = [String: ArrowConst]()
  var namedADSREnvelopes = [String: ADSR]()
  var arrow: Arrow11
  
  init(_ arrow: Arrow11) {
    self.arrow = arrow
    weak var fself: ArrowWithHandles? = nil
    super.init(of: { t in fself!.arrow.of(t) })
    fself = self
  }
  
  func withMergeDictsFromArrow(_ arr2: ArrowWithHandles) -> ArrowWithHandles {
    namedADSREnvelopes.merge(arr2.namedADSREnvelopes) { (a, b) in return a }
    namedConsts.merge(arr2.namedConsts) { (a, b) in return a }
    namedBasicOscs.merge(arr2.namedBasicOscs) { (a, b) in return a }
    namedLowPassFilter.merge(arr2.namedLowPassFilter) { (a, b) in return a }
    return self
  }
  
  func withMergeDictsFromArrows(_ arrs: [ArrowWithHandles]) -> ArrowWithHandles {
    for arr in arrs {
      let _ = withMergeDictsFromArrow(arr)
    }
    return self
  }
}

enum ArrowSyntax: Decodable {
  case const(NamedFloat)
  case identity
  indirect case lowPassFilter(LowPassArrowSyntax)
  indirect case unary(NamedArrowSyntax)
  indirect case nary(NamedArrowSyntaxList)
  indirect case envelope(ADSRSyntax)
  // NOTE: cases need to each be tied to a different associated type, given the Decoding logic
  
  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  func compile() -> ArrowWithHandles {
    switch self {
    case .identity:
      return ArrowWithHandles(ArrowIdentity())
    
    case .const(let namedVal):
      let arr = ArrowConst(namedVal.val)
      let handleArr = ArrowWithHandles(arr)
      handleArr.namedConsts[namedVal.name] = arr
      return handleArr
    
    case .lowPassFilter(let lpArrow):
      let lowerArrow = lpArrow.arrow.compile()
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
    
    case .envelope(let adsr):
      let env = ADSR(envelope: EnvelopeData(
        attackTime: adsr.attack,
        decayTime: adsr.decay,
        sustainLevel: adsr.sustain,
        releaseTime: adsr.release,
        scale: adsr.scale
      ))
      let handleArr = ArrowWithHandles(env)
      handleArr.namedADSREnvelopes[adsr.name] = env
      return handleArr
    
    case .unary(let namedArrow):
      let lowerArr = namedArrow.arrow.compile()
      if namedArrow.name == "delay" {
        let arr = Delay(lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if namedArrow.name == "control" {
        let arr = ControlArrow11(of: lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if namedArrow.name == "sin" {
        let arr = ArrowCompose(outer: ArrowSin(), inner: lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if namedArrow.name == "cos" {
        let arr = ArrowCompose(outer: ArrowCos(), inner: lowerArr)
        return ArrowWithHandles(arr).withMergeDictsFromArrow(lowerArr)
      } else if BasicOscillator.OscShape.allCases.map({$0.rawValue}).contains(namedArrow.name) {
        let osc = BasicOscillator(shape: BasicOscillator.OscShape(rawValue: namedArrow.name)!)
        var arr = ArrowCompose(outer: osc, inner: lowerArr)
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
  
  // see https://github.com/rogerluan/JSEN/blob/main/Sources/JSEN%2BCodable.swift
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let float = try? container.decode(NamedFloat.self) {
      self = .const(float)
    } else if let adsrData = try? container.decode(ADSRSyntax.self) {
      self = .envelope(adsrData)
    } else if let innerArrow = try? container.decode(NamedArrowSyntax.self) {
      self = .unary(innerArrow)
    } else if let lowPassFilter = try? container.decode(LowPassArrowSyntax.self) {
      self = .lowPassFilter(lowPassFilter)
    } else if let innerArrows = try? container.decode(NamedArrowSyntaxList.self) {
      self = .nary(innerArrows)
    } else {
      self = .identity
    }
  }
}

struct LowPassArrowSyntax: Decodable {
  let name: String
  let cutoff: ArrowSyntax
  let resonance: ArrowSyntax
  let arrow: ArrowSyntax
}

struct ADSRSyntax: Decodable {
  let name: String
  let attack: CoreFloat
  let decay: CoreFloat
  let sustain: CoreFloat
  let release: CoreFloat
  let scale: CoreFloat
}

struct NamedArrowSyntax: Decodable {
  let name: String
  let arrow: ArrowSyntax
}

struct NamedArrowSyntaxList: Decodable {
  let name: String
  let arrows: [ArrowSyntax]
}

struct NamedFloat: Decodable {
  let name: String
  let val: CoreFloat
}

struct NamedBasicOscillatorShape: Decodable {
  let name: String
  let osc: BasicOscillator.OscShape
}
