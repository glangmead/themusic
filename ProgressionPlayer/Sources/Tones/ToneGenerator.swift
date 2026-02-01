//
//  Instrument.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Accelerate
import Foundation
import SwiftUI

protocol WidthHaver {
  var widthArr: Arrow11 { get set }
}

final class Sine: Arrow11, WidthHaver {
  private var scratch = [CoreFloat](repeating: 0, count: 512)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)
//  func of(_ t: CoreFloat) -> CoreFloat {
//    let width = widthArr.of(t)
//    let innerResult = inner(t)
//    return (fmod(innerResult, 1) < width) ? sin(2 * .pi * innerResult / width) : 0
//  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    //widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &scratch)
    vDSP.multiply(2 * .pi, scratch, result: &scratch)
    //vDSP.divide(outputs, widthOutputs, result: &outputs)
    // zero out some of the inners, to the right of the width cutoff
    //for i in 0..<inputs.count {
    //  if fmod(outputs[i], 1) > widthOutputs[i] {
    //    outputs[i] = 0
    //  }
    //}
    vForce.sin(scratch, result: &outputs)
  }
}

final class Triangle: Arrow11, WidthHaver {
  private var widthOutputs = [CoreFloat](repeating: 0, count: 512)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)
//  func of(_ t: CoreFloat) -> CoreFloat {
//    let width = widthArr.of(t)
//    let innerResult = inner(t)
//    let modResult = fmod(innerResult, 1)
//    return (modResult < width/2) ? (4 * modResult / width) - 1:
//      (modResult < width) ? (-4 * modResult / width) + 3 : 0
//  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)
    for i in 0..<inputs.count {
      let modResult = fmod(outputs[i], 1)
      let width = widthOutputs[i]
      outputs[i] = (modResult < width/2) ? (4 * modResult / width) - 1:
      (modResult < width) ? (-4 * modResult / width) + 3 : 0
    }
  }
}

final class Sawtooth: Arrow11, WidthHaver {
  private var widthOutputs = [CoreFloat](repeating: 0, count: 512)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)
//  func of(_ t: CoreFloat) -> CoreFloat {
//    let width = widthArr.of(t)
//    let innerResult = inner(t)
//    let modResult = fmod(innerResult, 1)
//    return (modResult < width) ? (2 * modResult / width) - 1 : 0
//  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)
    for i in 0..<inputs.count {
      let modResult = fmod(outputs[i], 1)
      let width = widthOutputs[i]
      outputs[i] = (modResult < width) ? (2 * modResult / width) - 1 : 0
    }
  }
}

final class Square: Arrow11, WidthHaver {
  private var widthOutputs = [CoreFloat](repeating: 0, count: 512)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)
//  func of(_ t: CoreFloat) -> CoreFloat {
//    let width = widthArr.of(t)
//    return fmod(inner(t), 1) <= width/2 ? 1.0 : -1.0
//  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)
    for i in 0..<inputs.count {
      let modResult = fmod(outputs[i], 1)
      let width = widthOutputs[i]
      outputs[i] = modResult <= width/2 ? 1.0 : -1.0
    }
  }
}

final class Noise: Arrow11, WidthHaver {
  var widthArr: Arrow11 = ArrowConst(value: 1.0)
  
  private var randomInts = [UInt32](repeating: 0, count: 512)
  private let scale: CoreFloat = 1.0 / CoreFloat(UInt32.max)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    let count = inputs.count
    if randomInts.count < count {
      randomInts = [UInt32](repeating: 0, count: count)
    }
    
    randomInts.withUnsafeMutableBytes { buffer in
      if let base = buffer.baseAddress {
        arc4random_buf(base, count * MemoryLayout<UInt32>.size)
      }
    }
    
    outputs.withUnsafeMutableBufferPointer { outputPtr in
      randomInts.withUnsafeBufferPointer { randomPtr in
        guard let inputBase = randomPtr.baseAddress,
              let outputBase = outputPtr.baseAddress else { return }

        // Convert UInt32 to Float
        //vDSP_vfltu32(inputBase, 1, outputBase, 1, vDSP_Length(count))
        // Convert UInt32 to Double
        vDSP_vfltu32D(inputBase, 1, outputBase, 1, vDSP_Length(count))
        
        // Normalize to 0.0...1.0
        var s = scale
        //vDSP_vsmul(outputBase, 1, &s, outputBase, 1, vDSP_Length(count))
        vDSP_vsmulD(outputBase, 1, &s, outputBase, 1, vDSP_Length(count))
      }
    }
    // let avg = vDSP.mean(outputs)
    // print("avg noise: \(avg)")
  }
}

// Takes on random values every 1/noiseFreq seconds, and smoothly interpolates between
final class NoiseSmoothStep: Arrow11 {
  var noiseFreq: CoreFloat
  var min: CoreFloat
  var max: CoreFloat

  // TODO: we need to know the sample rate here, and that should not be hardcoded
  private var audioDeltaTime: CoreFloat = 1.0 / 44100.0
  // for emitting new noise samples
  private var lastNoiseTime: CoreFloat
  private var nextNoiseTime: CoreFloat
  // the noise samples we're interpolating at any given moment
  private var lastSample: CoreFloat
  private var nextSample: CoreFloat
  // for detecting when we're nearing a sample and need a new one
  private var noiseDeltaTime: CoreFloat
  private var numAudioSamplesPerNoise: Int = 0
  private var numAudioSamplesThisSegment = 0
  
  init(noiseFreq: CoreFloat, min: CoreFloat = -1, max: CoreFloat = 1) {
    self.noiseFreq = noiseFreq
    self.min = min
    self.max = max
    self.lastSample = CoreFloat.random(in: min...max)
    self.nextSample = CoreFloat.random(in: min...max)
    lastNoiseTime = 0
    noiseDeltaTime = 1.0 / noiseFreq
    nextNoiseTime = noiseDeltaTime
    noiseDeltaTime -= fmod(noiseDeltaTime, audioDeltaTime)
    numAudioSamplesPerNoise = Int(noiseDeltaTime/audioDeltaTime)
    super.init()
  }
  
  func noise(_ t: CoreFloat) -> CoreFloat {
    // catch up if there has been a time gap
    if t > nextNoiseTime + audioDeltaTime {
      lastNoiseTime = t
      nextNoiseTime = lastNoiseTime + noiseDeltaTime
      lastSample = CoreFloat.random(in: min...max)
      nextSample = CoreFloat.random(in: min...max)
      numAudioSamplesThisSegment = 0
    }
    
    // we roll to the next sample by counting audio samples
    // we chose an integer that's close to achieving the requested noiseFreq
    if numAudioSamplesThisSegment >= numAudioSamplesPerNoise - 1 {
      numAudioSamplesThisSegment = 0
      lastSample = nextSample
      nextSample = CoreFloat.random(in: min...max)
      lastNoiseTime = nextNoiseTime
      nextNoiseTime += noiseDeltaTime
    }

    // generate smoothstep for x between 0 and 1, y between 0 and 1
    let betweenTime = 1.0 - ((nextNoiseTime - t) / noiseDeltaTime)
    let zeroOneSmooth = betweenTime * betweenTime * (3 - 2 * betweenTime)
    let result = lastSample + (zeroOneSmooth * (nextSample - lastSample))
    
    numAudioSamplesThisSegment += 1
    return result
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Default implementation: loop
    for i in 0..<inputs.count {
      outputs[i] = self.noise(inputs[i])
    }
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
  private let noise = Noise()
  private let sineUnmanaged: Unmanaged<Arrow11>?
  private let triangleUnmanaged: Unmanaged<Arrow11>?
  private let sawtoothUnmanaged: Unmanaged<Arrow11>?
  private let squareUnmanaged: Unmanaged<Arrow11>?
  private let noiseUnmanaged: Unmanaged<Arrow11>?
  private var innerVals = [CoreFloat](repeating: 0, count: 512)

  var arrow: (Arrow11 & WidthHaver)? = nil
  private var arrUnmanaged: Unmanaged<Arrow11>? = nil

  var shape: OscShape {
    didSet {
      updateShape()
    }
  }
  var widthArr: Arrow11 {
    didSet {
      arrow?.widthArr = widthArr
    }
  }

  init(shape: OscShape, widthArr: Arrow11 = ArrowConst(value: 1)) {
    self.sineUnmanaged = Unmanaged.passUnretained(sine)
    self.triangleUnmanaged = Unmanaged.passUnretained(triangle)
    self.sawtoothUnmanaged = Unmanaged.passUnretained(sawtooth)
    self.squareUnmanaged = Unmanaged.passUnretained(square)
    self.noiseUnmanaged = Unmanaged.passUnretained(noise)
    self.widthArr = widthArr
    self.shape = shape
    super.init()
    self.updateShape()
  }
  
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &innerVals)
    arrUnmanaged?._withUnsafeGuaranteedRef { $0.process(inputs: innerVals, outputs: &outputs) }
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
  private var innerVals = [CoreFloat](repeating: 0, count: 512)

  init(chorusCentRadius: Int, chorusNumVoices: Int, valueToChorus: String) {
    self.chorusCentRadius = chorusCentRadius
    self.chorusNumVoices = chorusNumVoices
    self.valueToChorus = valueToChorus
    for power in -500...500 {
      centPowers.append(pow(cent, CoreFloat(power)))
    }
    super.init()
  }
  
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    vDSP.clear(&outputs)
    // set the freq and call arrow.of() repeatedly, and sum the results
    if chorusNumVoices > 1 {
      // get the constants of the given name (it is an array, as we have some duplication in the json)
      if let innerArrowWithHandles = innerArr as? ArrowWithHandles {
        if let freqArrows = innerArrowWithHandles.namedConsts[valueToChorus] {
          let baseFreq = freqArrows.first!.val
          let spreadFreqs = chorusedFreqs(freq: baseFreq)
          for freqArrow in freqArrows {
            for i in spreadFreqs.indices {
              freqArrow.val = spreadFreqs[i]
              (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &innerVals)
              vDSP.add(outputs, innerVals, result: &outputs)
            }
            // restore
            freqArrow.val = baseFreq
          }
        }
      } else {
        (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)
      }
    } else {
      (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)
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
  private var innerVals = [CoreFloat](repeating: 0, count: 512)
  private var cutoffs = [CoreFloat](repeating: 0, count: 512)
  private var resonances = [CoreFloat](repeating: 0, count: 512)
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
  func filter(_ t: CoreFloat, inner: CoreFloat, cutoff: CoreFloat, resonance: CoreFloat) -> CoreFloat {
    if self.previousTime == 0 {
      self.previousTime = t
      return 0
    }

    let dt = t - previousTime
    if (dt <= 1.0e-9) {
      return self.previousOutput1; // Return last output
    }
    let cutoff = min(0.5 / dt, cutoff)
    var w0 = 2 * .pi * cutoff * dt // cutoff freq over sample freq
    if w0 > .pi - 0.01 { // if dt is very large relative to frequency
      w0 = .pi - 0.01
    }
    let cosw0 = cos(w0)
    let sinw0 = sin(w0)
    // resonance (Q factor). 0.707 is maximally flat (Butterworth). > 0.707 adds a peak.
    let resonance = resonance
    let alpha = sinw0 / (2.0 * max(0.001, resonance))
    
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
    //print("\(output)")
    return output
  }
  
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &innerVals)
    cutoff.process(inputs: inputs, outputs: &cutoffs)
    resonance.process(inputs: inputs, outputs: &resonances)
    // Default implementation: loop
    for i in 0..<inputs.count {
      outputs[i] = self.filter(inputs[i], inner: innerVals[i], cutoff: cutoffs[i], resonance: resonances[i])
    }
  }
}

class ArrowWithHandles: Arrow11 {
  // the handles are dictionaries with values that give access to arrows within the arrow
  var namedBasicOscs     = [String: [BasicOscillator]]()
  var namedLowPassFilter = [String: [LowPassFilter2]]()
  var namedConsts        = [String: [ValHaver]]()
  var namedADSREnvelopes = [String: [ADSR]]()
  var namedChorusers     = [String: [Choruser]]()
  var namedCrossfaders   = [String: [ArrowCrossfade]]()
  var namedCrossfadersEqPow = [String: [ArrowEqualPowerCrossfade]]()
  var wrappedArrow: Arrow11
  
  private var wrappedArrowUnsafe: Unmanaged<Arrow11>
  
  init(_ wrappedArrow: Arrow11) {
    // has an arrow
    self.wrappedArrow = wrappedArrow
    self.wrappedArrowUnsafe = Unmanaged.passUnretained(wrappedArrow)
    // does not participate in its superclass arrowness
    super.init()
  }
  
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    wrappedArrowUnsafe._withUnsafeGuaranteedRef { $0.process(inputs: inputs, outputs: &outputs) }
  }

  func withMergeDictsFromArrow(_ arr2: ArrowWithHandles) -> ArrowWithHandles {
    namedADSREnvelopes.merge(arr2.namedADSREnvelopes) { (a, b) in return a + b }
    namedConsts.merge(arr2.namedConsts) { (a, b) in
      return a + b
    }
    namedBasicOscs.merge(arr2.namedBasicOscs) { (a, b) in return a + b }
    namedLowPassFilter.merge(arr2.namedLowPassFilter) { (a, b) in return a + b }
    namedChorusers.merge(arr2.namedChorusers) { (a, b) in return a + b }
    namedCrossfaders.merge(arr2.namedCrossfaders) { (a, b) in return a + b }
    namedCrossfadersEqPow.merge(arr2.namedCrossfadersEqPow) { (a, b) in return a + b }
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
  
  indirect case osc(name: String, shape: BasicOscillator.OscShape, width: ArrowSyntax)
  
  // see https://www.compilenrun.com/docs/language/swift/swift-enumerations/swift-recursive-enumerations/
  func compile() -> ArrowWithHandles {
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
      return composition!.withMergeDictsFromArrows(arrows)
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

    }
  }
}

#Preview {
  let osc = NoiseSmoothStep(noiseFreq: 2, min: 0, max: 2)
  osc.innerArr = ArrowIdentity()
  return ArrowChart(arrow: osc, ymin: 0, ymax: 2)
}
