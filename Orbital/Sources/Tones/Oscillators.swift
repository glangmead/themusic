//
//  Oscillators.swift
//  Orbital
//
//  Extracted from ToneGenerator.swift
//

import Accelerate
import Foundation

protocol WidthHaver {
  var widthArr: Arrow11 { get set }
}

final class Sine: Arrow11, WidthHaver {
  private var scratch = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var widthOutputs = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    let minBufferCount = inputs.count
    let count = vDSP_Length(minBufferCount)
    var intCount = Int32(minBufferCount)
    widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &scratch)

    scratch.withUnsafeMutableBufferPointer { scratchBuf in
      outputs.withUnsafeMutableBufferPointer { outBuf in
        widthOutputs.withUnsafeMutableBufferPointer { widthBuf in
          guard let scratchBase = scratchBuf.baseAddress,
                let outBase = outBuf.baseAddress,
                let widthBase = widthBuf.baseAddress else { return }

          // scratch = scratch * 2 * pi
          var twoPi = 2.0 * CoreFloat.pi
          vDSP_vsmulD(scratchBase, 1, &twoPi, scratchBase, 1, count)

          // outputs = outputs / widthOutputs
          vDSP_vdivD(widthBase, 1, outBase, 1, outBase, 1, count)

          // zero out samples where fmod(outputs[i], 1) > widthOutputs[i]
          // This implements pulse-width modulation gating
          for i in 0..<minBufferCount {
            let modVal = outBase[i] - floor(outBase[i])  // faster than fmod for positive values
            if modVal > widthBase[i] {
              outBase[i] = 0
            }
          }

          // sin(scratch) -> outputs
          vvsin(outBase, scratchBase, &intCount)
        }
      }
    }
  }
}

final class Triangle: Arrow11, WidthHaver {
  private var widthOutputs = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var scratch = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
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

    let n = inputs.count
    let count = vDSP_Length(n)
    outputs.withUnsafeMutableBufferPointer { outputsPtr in
      widthOutputs.withUnsafeBufferPointer { widthPtr in
        scratch.withUnsafeMutableBufferPointer { scratchPtr in
          guard let outBase = outputsPtr.baseAddress,
                let widthBase = widthPtr.baseAddress,
                let scratchBase = scratchPtr.baseAddress else { return }

          // outputs = frac(outputs)
          vDSP_vfracD(outBase, 1, outBase, 1, count)

          // scratch = outputs / width (normalized phase)
          vDSP_vdivD(widthBase, 1, outBase, 1, scratchBase, 1, count)

          // Triangle wave with width gating
          for i in 0..<n {
            let normalized = scratchBase[i]
            if normalized < 1.0 {
              // Triangle wave: 1 - 4 * abs(normalized - 0.5)
              outBase[i] = 1.0 - 4.0 * abs(normalized - 0.5)
            } else {
              outBase[i] = 0
            }
          }
        }
      }
    }
  }
}

final class Sawtooth: Arrow11, WidthHaver {
  private var widthOutputs = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var scratch = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)

    let n = inputs.count
    let count = vDSP_Length(n)
    outputs.withUnsafeMutableBufferPointer { outputsPtr in
      widthOutputs.withUnsafeBufferPointer { widthPtr in
        scratch.withUnsafeMutableBufferPointer { scratchPtr in
          guard let outBase = outputsPtr.baseAddress,
                let widthBase = widthPtr.baseAddress,
                let scratchBase = scratchPtr.baseAddress else { return }

          // outputs = frac(outputs)
          vDSP_vfracD(outBase, 1, outBase, 1, count)

          // scratch = 2 * outputs
          var two: CoreFloat = 2.0
          vDSP_vsmulD(outBase, 1, &two, scratchBase, 1, count)

          // scratch = scratch / width
          vDSP_vdivD(widthBase, 1, scratchBase, 1, scratchBase, 1, count)

          // scratch = scratch - 1
          var minusOne: CoreFloat = -1.0
          vDSP_vsaddD(scratchBase, 1, &minusOne, scratchBase, 1, count)

          // Sawtooth with width gating
          for i in 0..<n {
            if outBase[i] < widthBase[i] {
              outBase[i] = scratchBase[i]
            } else {
              outBase[i] = 0
            }
          }
        }
      }
    }
  }
}

final class Square: Arrow11, WidthHaver {
  private var widthOutputs = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  var widthArr: Arrow11 = ArrowConst(value: 1.0)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    widthArr.process(inputs: inputs, outputs: &widthOutputs)
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)

    let n = inputs.count
    let count = vDSP_Length(n)
    outputs.withUnsafeMutableBufferPointer { outputsPtr in
      widthOutputs.withUnsafeMutableBufferPointer { widthPtr in
        guard let outBase = outputsPtr.baseAddress,
              let widthBase = widthPtr.baseAddress else { return }

        // outputs = frac(outputs)
        vDSP_vfracD(outBase, 1, outBase, 1, count)

        // width = width * 0.5
        var half: CoreFloat = 0.5
        vDSP_vsmulD(widthBase, 1, &half, widthBase, 1, count)

        // Square wave
        for i in 0..<n {
          outBase[i] = outBase[i] <= widthBase[i] ? 1.0 : -1.0
        }
      }
    }
  }
}

final class Noise: Arrow11, WidthHaver {
  var widthArr: Arrow11 = ArrowConst(value: 1.0)

  private var randomInts = [UInt32](repeating: 0, count: MAX_BUFFER_SIZE)
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
        // vDSP_vfltu32(inputBase, 1, outputBase, 1, vDSP_Length(count))
        // Convert UInt32 to Double
        vDSP_vfltu32D(inputBase, 1, outputBase, 1, vDSP_Length(count))

        // Normalize to 0.0...1.0
        var s = scale
        // vDSP_vsmul(outputBase, 1, &s, outputBase, 1, vDSP_Length(count))
        vDSP_vsmulD(outputBase, 1, &s, outputBase, 1, vDSP_Length(count))
      }
    }
    // let avg = vDSP.mean(outputs)
    // print("avg noise: \(avg)")
  }
}

/// Takes on random values every 1/noiseFreq seconds, and smoothly interpolates between.
/// Uses smoothstep function (3x² - 2x³) to interpolate from 0 to 1, scaled to the desired speed and range.
/// 
/// This implementation uses sample counting rather than time tracking, which is simpler and more robust
/// across different sample rates. The smoothstep values are pre-computed in a lookup table when the
/// sample rate is set, eliminating per-sample division and fmod operations.
///
/// - Parameters:
///   - noiseFreq: the number of random numbers generated per second
///   - min: the minimum range of the random numbers (uniformly distributed)
///   - max: the maximum range of the random numbers (uniformly distributed)
final class NoiseSmoothStep: Arrow11 {
  var noiseFreq: CoreFloat {
    didSet {
      rebuildLUT()
    }
  }
  var min: CoreFloat
  var max: CoreFloat

  // The two random samples we're currently interpolating between
  private var lastSample: CoreFloat
  private var nextSample: CoreFloat

  // Sample counting for segment transitions
  private var sampleCounter: Int = 0
  private var samplesPerSegment: Int = 1

  // Pre-computed smoothstep lookup table for one full segment
  private var smoothstepLUT: [CoreFloat] = []

  override func setSampleRateRecursive(rate: CoreFloat) {
    super.setSampleRateRecursive(rate: rate)
    rebuildLUT()
  }

  private func rebuildLUT() {
    // Compute how many audio samples per noise segment
    samplesPerSegment = Swift.max(1, Int(sampleRate / noiseFreq))

    // Pre-compute smoothstep values for one full segment
    // smoothstep(x) = x² * (3 - 2x) (aka 3x³ - 2x²)for x in [0, 1]
    smoothstepLUT = [CoreFloat](repeating: 0, count: samplesPerSegment)
    let invSegment = 1.0 / CoreFloat(samplesPerSegment)
    for i in 0..<samplesPerSegment {
      let x = CoreFloat(i) * invSegment
      smoothstepLUT[i] = x * x * (3.0 - 2.0 * x)
    }

    // Reset counter to avoid out-of-bounds after sample rate change
    sampleCounter = 0
  }

  init(noiseFreq: CoreFloat, min: CoreFloat = -1, max: CoreFloat = 1) {
    self.noiseFreq = noiseFreq
    self.min = min
    self.max = max
    self.lastSample = CoreFloat.random(in: min...max)
    self.nextSample = CoreFloat.random(in: min...max)
    super.init()
    rebuildLUT()
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    let count = inputs.count
    guard samplesPerSegment > 0, !smoothstepLUT.isEmpty else { return }

    outputs.withUnsafeMutableBufferPointer { outBuf in
      smoothstepLUT.withUnsafeBufferPointer { lutBuf in
        guard let outBase = outBuf.baseAddress,
              let lutBase = lutBuf.baseAddress else { return }

        var last = lastSample
        var next = nextSample
        var counter = sampleCounter
        let segmentSize = samplesPerSegment

        for i in 0..<count {
          let t = lutBase[counter]
          outBase[i] = last + t * (next - last)

          counter += 1
          if counter >= segmentSize {
            counter = 0
            last = next
            next = CoreFloat.random(in: min...max)
          }
        }

        // Write back state
        lastSample = last
        nextSample = next
        sampleCounter = counter
      }
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
  private let sineUnmanaged: Unmanaged<Arrow11>
  private let triangleUnmanaged: Unmanaged<Arrow11>
  private let sawtoothUnmanaged: Unmanaged<Arrow11>
  private let squareUnmanaged: Unmanaged<Arrow11>
  private let noiseUnmanaged: Unmanaged<Arrow11>
  private var innerVals = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

  var arrow: (Arrow11 & WidthHaver)?
  private var arrUnmanaged: Unmanaged<Arrow11>?

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

  override func setSampleRateRecursive(rate: CoreFloat) {
    widthArr.setSampleRateRecursive(rate: rate)
    sine.setSampleRateRecursive(rate: rate)
    triangle.setSampleRateRecursive(rate: rate)
    sawtooth.setSampleRateRecursive(rate: rate)
    square.setSampleRateRecursive(rate: rate)
    noise.setSampleRateRecursive(rate: rate)
    super.setSampleRateRecursive(rate: rate)
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Ensure innerVals matches outputs size so downstream vDSP calls
    // (which use inputs.count) don't overrun the outputs buffer.
    if innerVals.count != outputs.count {
      innerVals = [CoreFloat](repeating: 0, count: outputs.count)
    }
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
