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
    let modResult = fmod(innerResult, 1)
    return (modResult < width/2) ? (4 * modResult / width) - 1:
      (modResult < width) ? (-4 * modResult / width) + 3 : 0
  }
}

final class Sawtooth: Arrow11, WidthHaver {
  var width: CoreFloat = 1
  override func of(_ t: CoreFloat) -> CoreFloat {
    let innerResult = inner(t)
    let modResult = fmod(innerResult, 1)
    return (modResult < width) ? (2 * modResult / width) - 1 : 0
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
  private let sine = Sine()
  private let triangle = Triangle()
  private let sawtooth = Sawtooth()
  private let square = Square()
  private let noise = ArrowSmoothStep(sampleFreq: 5)
  private let sineUnmanaged: Unmanaged<Arrow11>?
  private let triangleUnmanaged: Unmanaged<Arrow11>?
  private let sawtoothUnmanaged: Unmanaged<Arrow11>?
  private let squareUnmanaged: Unmanaged<Arrow11>?
  private let noiseUnmanaged: Unmanaged<Arrow11>?

  var arrow: (Arrow11 & WidthHaver)? = nil
  private var arrUnmanaged: Unmanaged<Arrow11>? = nil

  var shape: OscShape {
    didSet {
      updateShape()
    }
  }
  var width: CoreFloat {
    didSet {
      arrow?.width = width
    }
  }

  init(shape: OscShape, width: CoreFloat = 1) {
    self.sineUnmanaged = Unmanaged.passUnretained(sine)
    self.triangleUnmanaged = Unmanaged.passUnretained(triangle)
    self.sawtoothUnmanaged = Unmanaged.passUnretained(sawtooth)
    self.squareUnmanaged = Unmanaged.passUnretained(square)
    self.noiseUnmanaged = Unmanaged.passUnretained(noise)
    self.width = width
    self.shape = shape
    super.init()
    self.updateShape()
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    arrUnmanaged?._withUnsafeGuaranteedRef { $0.of(unmanagedInner(t)) } ?? 0
  }
  
  func updateShape() {
    switch shape {
    case .sine:
      arrow = sine
      arrUnmanaged = sineUnmanaged
    case .triangle:
      arrow = triangle
      arrUnmanaged = triangleUnmanaged
    case .sawtooth:
      arrow = sawtooth
      arrUnmanaged = sawtoothUnmanaged
    case .square:
      arrow = square
      arrUnmanaged = squareUnmanaged
    case .noise:
      arrow = noise
      arrUnmanaged = noiseUnmanaged
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
  var centPowers = ContiguousArray<CoreFloat>()
  let cent: CoreFloat = 1.0005777895065548 // '2 ** (1/1200)' in python

  init(chorusCentRadius: Int, chorusNumVoices: Int, valueToChorus: String) {
    self.chorusCentRadius = chorusCentRadius
    self.chorusNumVoices = chorusNumVoices
    self.valueToChorus = valueToChorus
    for power in -500...500 {
      centPowers.append(pow(cent, CoreFloat(power)))
    }
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
            for i in spreadFreqs.indices {
              freqArrow.val = spreadFreqs[i]
              chorusedResults += unmanagedInner(t)
            }
            // restore
            freqArrow.val = baseFreq
          }
        }
        return chorusedResults
      } else {
        return unmanagedInner(t)
      }
    } else {
      return unmanagedInner(t)
    }
  }
  
  // return chorusNumVoices frequencies, centered on the requested freq but spanning an interval
  // from freq - delta to freq + delta (where delta depends on freq and chorusCentRadius)
  func chorusedFreqs(freq: CoreFloat) -> [CoreFloat] {
    let freqRadius = freq * centPowers[chorusCentRadius + 500] - freq
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

// from https://www.w3.org/TR/audio-eq-cookbook/
final class LowPassFilter2: Arrow11 {
  private var previousTime: CoreFloat
  private var previousInner1: CoreFloat
  private var previousInner2: CoreFloat
  private var previousOutput1: CoreFloat
  private var previousOutput2: CoreFloat

  var cutoff: Arrow11
  var resonance: Arrow11
  
  init(cutoff: Arrow11, resonance: Arrow11) {
    self.cutoff = cutoff
    self.resonance = resonance
    
    self.previousTime = 0
    self.previousInner1 = 0
    self.previousInner2 = 0
    self.previousOutput1 = 0
    self.previousOutput2 = 0
    super.init()
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    let inner = inner(t)

    let dt = t - previousTime
    if (dt <= 1.0e-9) {
      return self.previousOutput1; // Return last output
    }
    
    var w0 = 2 * .pi * cutoff.of(t) * dt // cutoff freq over sample freq
    if w0 > .pi - 0.01 { // if dt is very large relative to frequency
      w0 = .pi - 0.01
    }
    let cosw0 = cos(w0)
    let sinw0 = sin(w0)
    // resonance (Q factor). 0.707 is maximally flat (Butterworth). > 0.707 adds a peak.
    let alpha = sinw0 / (2.0 * max(0.001, resonance.of(t)))
    
    let a0 = 1.0 + alpha
    let a1 = (-2.0 * cosw0) / a0
    let a2 = (1 - alpha) / a0
    let b0 = ((1.0 - cosw0) / 2.0) / a0
    let b1 = (1.0 - cosw0) / a0
    let b2 = b0
    
    let output =
        (b0 * inner)
      + (b1 * previousInner1)
      + (b2 * previousInner2)
      - (a1 * previousOutput1)
      - (a2 * previousOutput2)

    // shift the data
    previousTime = t
    previousInner2 = previousInner1
    previousInner1 = inner
    previousOutput2 = previousOutput1
    previousOutput1 = output
    return output
  }
}

class ArrowWithHandles: Arrow11 {
  // the handles are dictionaries with values that give access to arrows within the arrow
  var namedBasicOscs     = [String: [BasicOscillator]]()
  var namedLowPassFilter = [String: [LowPassFilter2]]()
  var namedConsts        = [String: [ValHaver]]()
  var namedADSREnvelopes = [String: [ADSR]]()
  var namedChorusers     = [String: [Choruser]]()
  var wrappedArrow: Arrow11
  
  private var wrappedArrowUnsafe: Unmanaged<Arrow11>
  
  init(_ wrappedArrow: Arrow11) {
    // has an arrow
    self.wrappedArrow = wrappedArrow
    self.wrappedArrowUnsafe = Unmanaged.passUnretained(wrappedArrow)
    // does not participate in its superclass arrowness
    super.init()
  }
  
  // delegates to wrapped arrow
  override func of(_ t: CoreFloat) -> CoreFloat {
    wrappedArrowUnsafe._withUnsafeGuaranteedRef { $0.of(t) }
  }

  func withMergeDictsFromArrow(_ arr2: ArrowWithHandles) -> ArrowWithHandles {
    namedADSREnvelopes.merge(arr2.namedADSREnvelopes) { (a, b) in return a + b }
    namedConsts.merge(arr2.namedConsts) { (a, b) in
      return a + b
    }
    namedBasicOscs.merge(arr2.namedBasicOscs) { (a, b) in return a + b }
    namedLowPassFilter.merge(arr2.namedLowPassFilter) { (a, b) in return a + b }
    namedChorusers.merge(arr2.namedChorusers) { (a, b) in return a + b }
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
  case const(name: String, val: CoreFloat)
  case constOctave(name: String, val: CoreFloat)
  case constCent(name: String, val: CoreFloat)
  case identity
  case control
  indirect case lowPassFilter(specs: LowPassArrowSyntax)
  indirect case prod(of: [ArrowSyntax])
  indirect case compose(arrows: [ArrowSyntax])
  indirect case sum(of: [ArrowSyntax])
  indirect case envelope(specs: ADSRSyntax)
  case choruser(specs: NamedChoruser)
  case osc(name: String, shape: BasicOscillator.OscShape, width: CoreFloat)
  
  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  func compile() -> ArrowWithHandles {
    switch self {
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
      return composition!.withMergeDictsFromArrows(arrows)
    case .osc(let oscName, let oscShape, let width):
      let osc = BasicOscillator(shape: oscShape, width: width)
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
    case .lowPassFilter(let lpArrow):
      let cutoffArrow = lpArrow.cutoff.compile()
      let resonanceArrow = lpArrow.resonance.compile()
      let arr = LowPassFilter2(
        cutoff: cutoffArrow,
        resonance: resonanceArrow
      )
      let handleArr = ArrowWithHandles(arr)
        .withMergeDictsFromArrow(cutoffArrow)
        .withMergeDictsFromArrow(resonanceArrow)
      if var filters = handleArr.namedLowPassFilter[lpArrow.name] {
        filters.append(arr)
      } else {
        handleArr.namedLowPassFilter[lpArrow.name] = [arr]
      }
      return handleArr
      
    case .choruser(let choruserSpecs):
      let choruser = Choruser(
        chorusCentRadius: choruserSpecs.chorusCentRadius,
        chorusNumVoices: choruserSpecs.chorusNumVoices,
        valueToChorus: choruserSpecs.valueToChorus
      )
      let handleArr = ArrowWithHandles(choruser)
      if var chorusers = handleArr.namedChorusers[choruserSpecs.name] {
        chorusers.append(choruser)
      } else {
        handleArr.namedChorusers[choruserSpecs.name] = [choruser]
      }
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
      if var envs = handleArr.namedADSREnvelopes[adsr.name] {
        envs.append(env)
      } else {
        handleArr.namedADSREnvelopes[adsr.name] = [env]
      }
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

struct NamedChoruser: Codable {
  let name: String
  let valueToChorus: String
  let chorusCentRadius: Int
  let chorusNumVoices: Int
}
