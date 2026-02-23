//
//  Effects.swift
//  Orbital
//
//  Extracted from ToneGenerator.swift
//

import Accelerate
import Foundation

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
    let a = amp.of(t)
    let k = leafFactor.of(t)
    let theta = (freq.of(t) * t) + phase
    // Rose curve on the upper hemisphere of a sphere of radius `a`.
    // phi (colatitude from +Y pole) ranges over [-π/2, π/2] so
    // cos(phi) ≥ 0 — the curve stays in the upper hemisphere.
    // No abs() so the particle passes smoothly through the pole.
    let phi = (CoreFloat.pi / 2) * sin(k * theta)
    return (a * sin(phi) * cos(theta),
            a * cos(phi),
            a * sin(phi) * sin(theta))
  }
}

final class Choruser: Arrow11 {
  var chorusCentRadius: Int
  var chorusNumVoices: Int
  var valueToChorus: String
  var centPowers = ContiguousArray<CoreFloat>()
  let cent: CoreFloat = 1.0005777895065548 // '2 ** (1/1200)' in python
  private var innerVals = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

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
    outputs.withUnsafeMutableBufferPointer { outBuf in
      vDSP_vclrD(outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
    }
    // set the freq and call arrow.of() repeatedly, and sum the results
    if chorusNumVoices > 1 {
      // get the constants of the given name (it is an array, as we have some duplication in the json)
      if let innerArrowWithHandles = innerArr as? ArrowWithHandles {
        if let freqArrows = innerArrowWithHandles.namedConsts[valueToChorus] {
          let baseFreq = freqArrows.first!.val
          let spreadFreqs = chorusedFreqs(freq: baseFreq)
          let count = vDSP_Length(inputs.count)
          for freqArrow in freqArrows {
            for i in spreadFreqs.indices {
              freqArrow.val = spreadFreqs[i]
              (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &innerVals)
              // no slicing - use C API with explicit count
              innerVals.withUnsafeBufferPointer { innerBuf in
                outputs.withUnsafeMutableBufferPointer { outBuf in
                  vDSP_vaddD(outBuf.baseAddress!, 1, innerBuf.baseAddress!, 1, outBuf.baseAddress!, 1, count)
                }
              }
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
  private var innerVals = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var cutoffs = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var resonances = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
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

  override func setSampleRateRecursive(rate: CoreFloat) {
    cutoff.setSampleRateRecursive(rate: rate)
    resonance.setSampleRateRecursive(rate: rate)
    super.setSampleRateRecursive(rate: rate)
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
    
    let count = inputs.count
    inputs.withUnsafeBufferPointer { inBuf in
      outputs.withUnsafeMutableBufferPointer { outBuf in
        innerVals.withUnsafeBufferPointer { innerBuf in
          cutoffs.withUnsafeBufferPointer { cutoffBuf in
            resonances.withUnsafeBufferPointer { resBuf in
              guard let inBase = inBuf.baseAddress,
                    let outBase = outBuf.baseAddress,
                    let innerBase = innerBuf.baseAddress,
                    let cutoffBase = cutoffBuf.baseAddress,
                    let resBase = resBuf.baseAddress else { return }
              
              for i in 0..<count {
                outBase[i] = self.filter(inBase[i], inner: innerBase[i], cutoff: cutoffBase[i], resonance: resBase[i])
              }
            }
          }
        }
      }
    }
  }
}
