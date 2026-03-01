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
// Feedback comb filter with linear interpolation for fractional delay.
// output[n] = input[n] + feedback * output[n - D]
// where D = sampleRate / frequency. This is the core of Karplus-Strong
// string synthesis: feed a noise burst in and get a pitched, decaying tone.
// The frequency response has peaks at multiples of the fundamental (harmonics),
// spaced like the teeth of a comb — hence "comb filter."
// Linear interpolation between adjacent delay buffer samples allows
// non-integer delay lengths, matching SuperCollider's CombL behavior.
final class CombFilter: Arrow11 {
  private var innerVals = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var freqs = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var feedbacks = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

  // Circular delay buffer. Sized for the lowest frequency we support (~20 Hz
  // at 48 kHz = 2400 samples). Pre-allocated to avoid any allocation in process().
  private var delayBuffer: [CoreFloat]
  private var writeIndex: Int = 0
  private let delayBufferSize: Int

  // Track the last time value seen so we can detect gaps from AudioGate closure.
  // A large jump means the voice was idle and we should clear stale buffer data.
  private var lastTime: CoreFloat = 0

  var frequency: Arrow11
  var feedback: Arrow11

  /// maxDelaySeconds caps the buffer size. 0.05s supports fundamentals down to ~20 Hz.
  init(frequency: Arrow11, feedback: Arrow11, maxDelaySeconds: CoreFloat = 0.05) {
    self.frequency = frequency
    self.feedback = feedback
    // Allocate for worst case sample rate (48 kHz) — will work fine at 44.1 kHz too.
    self.delayBufferSize = Int(48000 * maxDelaySeconds) + 2
    self.delayBuffer = [CoreFloat](repeating: 0, count: Int(48000 * maxDelaySeconds) + 2)
    super.init()
  }

  override func setSampleRateRecursive(rate: CoreFloat) {
    frequency.setSampleRateRecursive(rate: rate)
    feedback.setSampleRateRecursive(rate: rate)
    super.setSampleRateRecursive(rate: rate)
  }

  /// Clear the delay buffer and reset write position.
  func reset() {
    delayBuffer.withUnsafeMutableBufferPointer { buf in
      vDSP_vclrD(buf.baseAddress!, 1, vDSP_Length(delayBufferSize))
    }
    writeIndex = 0
    lastTime = 0
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &innerVals)
    frequency.process(inputs: inputs, outputs: &freqs)
    feedback.process(inputs: inputs, outputs: &feedbacks)

    let count = inputs.count
    let bufSize = delayBufferSize

    // Detect time gap from AudioGate closure. A normal inter-frame gap at
    // 44.1 kHz / 512 samples is ~0.012s. Anything over 0.05s means the
    // voice was gated off and the buffer contains stale resonance.
    if count > 0 {
      let currentTime = inputs[0]
      if lastTime > 0 && (currentTime - lastTime) > 0.05 {
        delayBuffer.withUnsafeMutableBufferPointer { buf in
          vDSP_vclrD(buf.baseAddress!, 1, vDSP_Length(bufSize))
        }
        writeIndex = 0
      }
      lastTime = inputs[count - 1]
    }

    innerVals.withUnsafeBufferPointer { innerBuf in
      freqs.withUnsafeBufferPointer { freqBuf in
        feedbacks.withUnsafeBufferPointer { fbBuf in
          outputs.withUnsafeMutableBufferPointer { outBuf in
            guard let innerBase = innerBuf.baseAddress,
                  let freqBase = freqBuf.baseAddress,
                  let fbBase = fbBuf.baseAddress,
                  let outBase = outBuf.baseAddress else { return }

            delayBuffer.withUnsafeMutableBufferPointer { delayBuf in
              guard let delayBase = delayBuf.baseAddress else { return }

              for i in 0..<count {
                let freq = max(20.0, freqBase[i])
                let delaySamples = sampleRate / freq
                // Clamp to buffer bounds
                let clampedDelay = min(delaySamples, CoreFloat(bufSize - 2))

                // Linear interpolation between two buffer positions
                let intDelay = Int(clampedDelay)
                let frac = clampedDelay - CoreFloat(intDelay)

                // Read from circular buffer
                var readIndex1 = writeIndex - intDelay
                if readIndex1 < 0 { readIndex1 += bufSize }
                var readIndex2 = readIndex1 - 1
                if readIndex2 < 0 { readIndex2 += bufSize }

                let delayed = delayBase[readIndex1] + frac * (delayBase[readIndex2] - delayBase[readIndex1])

                let output = innerBase[i] + fbBase[i] * delayed

                // Write to circular buffer and advance
                delayBase[writeIndex] = output
                writeIndex += 1
                if writeIndex >= bufSize { writeIndex = 0 }

                outBase[i] = output
              }
            }
          }
        }
      }
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
    if dt <= 1.0e-9 {
      return self.previousOutput1 // Return last output
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
    // print("\(output)")
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
