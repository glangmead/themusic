//
//  Arrow.swift
//  Orbital
//
//  Created by Greg Langmead on 10/14/25.
//

import Accelerate
import AVFAudio

typealias CoreFloat = Double
let MAX_BUFFER_SIZE = 1024

class Arrow11 {
  var sampleRate: CoreFloat = 44100 // to be updated from outside if different, but this is a good guess
  func setSampleRateRecursive(rate: CoreFloat) {
    sampleRate = rate
    innerArr?.setSampleRateRecursive(rate: rate)
    innerArrs.forEach({$0.setSampleRateRecursive(rate: rate)})
  }

  // MARK: - Per-node random reset (shareable song seeds)
  //
  // Random-consuming Arrow nodes (ArrowRandom, NoiseSmoothStep,
  // ArrowExponentialRandom) own their own Xorshift128Plus state. The walker in
  // ArrowSeedMap.build assigns each consumer a stable per-node sub-seed
  // derived from the song seed and the node's structural path. This method
  // walks the graph (mirror of setSampleRateRecursive) so each consumer can
  // look itself up by ObjectIdentifier in the seedMap and reseed.
  //
  // Called from the main actor on a stopped engine, before engine.start().
  // Per-node state is then mutated only by the render thread that owns the
  // node, lock-free.
  func resetRandomRecursive(seedMap: [ObjectIdentifier: UInt64]) {
    applyRandomSeed(seedMap: seedMap)
    innerArr?.resetRandomRecursive(seedMap: seedMap)
    innerArrs.forEach { $0.resetRandomRecursive(seedMap: seedMap) }
  }

  /// Override in random-consuming subclasses to reseed internal PRNG state
  /// from the seed map. Default is a no-op.
  func applyRandomSeed(seedMap: [ObjectIdentifier: UInt64]) {}

  /// Stable identifier for this node's role in the structural path used by
  /// ArrowSeedMap.build. Defaults to the type name. Override only if a single
  /// type plays multiple roles whose seeds should differ.
  var pathSegment: String { String(describing: type(of: self)) }

  /// True if this node draws from a per-node PRNG via `applyRandomSeed`.
  /// The walker uses this to decide whether to assign a seed-map entry.
  var consumesRandomness: Bool { false }

  /// Reference fields beyond `innerArr`/`innerArrs` that participate in
  /// random reset (e.g. `ArrowCrossfade.mixPointArr`). The walker visits
  /// these AFTER `innerArr`/`innerArrs`, with a labeled path segment per
  /// entry. Default is empty.
  var extraRandomChildren: [(label: String, node: Arrow11)] { [] }

  // these are arrows with which we can compose (arr/arrs run first, then this arrow)
  var innerArr: Arrow11? {
    didSet {
      if let inner = innerArr {
        self.innerArrUnmanaged = Unmanaged.passUnretained(inner)
      }
    }
  }
  private var innerArrUnmanaged: Unmanaged<Arrow11>?

  var innerArrs = ContiguousArray<Arrow11>() {
    didSet {
      innerArrsUnmanaged = []
      for arrow in innerArrs {
        innerArrsUnmanaged.append(Unmanaged.passUnretained(arrow))
      }
    }
  }
  internal var innerArrsUnmanaged = ContiguousArray<Unmanaged<Arrow11>>()

  init(innerArr: Arrow11? = nil) {
    self.innerArr = innerArr
    if let inner = innerArr {
      self.innerArrUnmanaged = Unmanaged.passUnretained(inner)
    }
  }

  init(innerArrs: ContiguousArray<Arrow11>) {
    self.innerArrs = innerArrs
    innerArrsUnmanaged = []
    for arrow in innerArrs {
      innerArrsUnmanaged.append(Unmanaged.passUnretained(arrow))
    }
  }

  init(innerArrs: [Arrow11]) {
    self.innerArrs = ContiguousArray<Arrow11>(innerArrs)
    innerArrsUnmanaged = []
    for arrow in innerArrs {
      innerArrsUnmanaged.append(Unmanaged.passUnretained(arrow))
    }
  }

  // old single-time behavior, wrapping the vector version
  func of(_ t: CoreFloat) -> CoreFloat {
    var input = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
    input[0] = t
    var result = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
    process(inputs: input, outputs: &result)
    return result[0]
  }

  func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &outputs)
  }

  final func asControl() -> Arrow11 {
    return ControlArrow11(innerArr: self)
  }
}

class Arrow13 {
  func of(_ t: CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat) { (t, t, t) }
}

// An arrow that wraps an arrow and limits how often the arrow gets called with a new time
// The name comes from the paradigm that control signals like LFOs don't need to fire as often
// as audio data.
final class ControlArrow11: Arrow11 {
  var lastTimeEmittedSecs: CoreFloat = 0.0
  var lastEmission: CoreFloat = 0.0
  let infrequency = 10
  private var scratchBuffer = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &scratchBuffer)
    var i = 0
    outputs.withUnsafeMutableBufferPointer { outBuf in
      while i < inputs.count {
        var val = scratchBuffer[i]
        let spanEnd = min(i + infrequency, inputs.count)
        let spanCount = vDSP_Length(spanEnd - i)
        vDSP_vfillD(&val, outBuf.baseAddress! + i, 1, spanCount)
        i += infrequency
      }
    }
  }
}

final class AudioGate: Arrow11 {
  var isOpen: Bool = true

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    if !isOpen {
      outputs.withUnsafeMutableBufferPointer { outBuf in
        vDSP_vclrD(outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
      }
      return
    }
    super.process(inputs: inputs, outputs: &outputs)
  }
}

final class ArrowSum: Arrow11 {
  private var scratchBuffer = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    if innerArrsUnmanaged.isEmpty {
      outputs.withUnsafeMutableBufferPointer { outBuf in
        vDSP_vclrD(outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
      }
      return
    }

    // Process first child directly to output
    innerArrsUnmanaged[0]._withUnsafeGuaranteedRef {
      $0.process(inputs: inputs, outputs: &outputs)
    }

    // Process remaining children via scratch
    if innerArrsUnmanaged.count > 1 {
      let count = vDSP_Length(inputs.count)
      for i in 1..<innerArrsUnmanaged.count {
        innerArrsUnmanaged[i]._withUnsafeGuaranteedRef {
          $0.process(inputs: inputs, outputs: &scratchBuffer)
        }
        // output = output + scratch (no slicing - use C API with explicit count)
        scratchBuffer.withUnsafeBufferPointer { scratchBuf in
          outputs.withUnsafeMutableBufferPointer { outBuf in
            vDSP_vaddD(scratchBuf.baseAddress!, 1, outBuf.baseAddress!, 1, outBuf.baseAddress!, 1, count)
          }
        }
      }
    }
  }
}

final class ArrowProd: Arrow11 {
  private var scratchBuffer = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Process first child directly to output
    innerArrsUnmanaged[0]._withUnsafeGuaranteedRef {
      $0.process(inputs: inputs, outputs: &outputs)
    }

    // Process remaining children via scratch
    if innerArrsUnmanaged.count > 1 {
      let count = vDSP_Length(inputs.count)
      for i in 1..<innerArrsUnmanaged.count {
        innerArrsUnmanaged[i]._withUnsafeGuaranteedRef {
          $0.process(inputs: inputs, outputs: &scratchBuffer)
        }
        // output = output * scratch (no slicing - use C API with explicit count)
        scratchBuffer.withUnsafeBufferPointer { scratchBuf in
          outputs.withUnsafeMutableBufferPointer { outBuf in
            vDSP_vmulD(scratchBuf.baseAddress!, 1, outBuf.baseAddress!, 1, outBuf.baseAddress!, 1, count)
          }
        }
      }
    }
  }
}

func clamp(_ val: CoreFloat, min: CoreFloat, max: CoreFloat) -> CoreFloat {
  if val < min { return min }
  if val > max { return max }
  return val
}

/// Samples from an exponential distribution mapped to [min, max].
/// Rate λ is chosen so that ~95% of raw samples fall within the range;
/// values beyond max are clamped.  The result is heavily biased toward min.
final class ArrowExponentialRandom: Arrow11 {
  var min: CoreFloat
  var max: CoreFloat
  /// Rate parameter: λ = -ln(0.05) / (max - min) ≈ 3 / (max - min)
  private var lambda: CoreFloat
  /// Per-node PRNG seeded by ArrowSeedMap via applyRandomSeed.
  /// Lock-free, owned by the render thread once playback starts.
  private var prng = Xorshift128Plus(seed: 0)

  override var consumesRandomness: Bool { true }
  override var pathSegment: String { "ArrowExponentialRandom" }

  override func applyRandomSeed(seedMap: [ObjectIdentifier: UInt64]) {
    if let seed = seedMap[ObjectIdentifier(self)] {
      prng = Xorshift128Plus(seed: seed)
    }
  }

  init(min: CoreFloat, max: CoreFloat) {
    self.min = Swift.min(min, max)
    self.max = Swift.max(min, max)
    let range = self.max - self.min
    self.lambda = range > 0 ? -log(0.05) / range : 1
    super.init()
  }

  /// Inverse-transform sample: x = -ln(U) / λ, shifted and clamped to [min, max].
  override func of(_ t: CoreFloat) -> CoreFloat {
    let u = prng.nextFloat(in: CoreFloat.ulpOfOne...1)  // avoid ln(0)
    let raw = -log(u) / lambda
    return clamp(min + raw, min: min, max: max)
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    outputs.withUnsafeMutableBufferPointer { buf in
      guard let base = buf.baseAddress else { return }
      let lo = min, hi = max, lam = lambda
      for i in 0..<inputs.count {
        let u = prng.nextFloat(in: CoreFloat.ulpOfOne...1)
        let raw = -log(u) / lam
        base[i] = clamp(lo + raw, min: lo, max: hi)
      }
    }
  }
}

func sqrtPosNeg(_ val: CoreFloat) -> CoreFloat {
  val >= 0 ? sqrt(val) : -sqrt(-val)
}

// Mix two of the arrows in a list, viewing the mixPoint as a point somewhere between two of the arrows
// Compare to Supercollider's `Select`
final class ArrowCrossfade: Arrow11 {
  private var mixPoints = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var arrowOuts = [[CoreFloat]]()
  var mixPointArr: Arrow11
  init(innerArrs: [Arrow11], mixPointArr: Arrow11) {
    self.mixPointArr = mixPointArr
    arrowOuts = [[CoreFloat]](repeating: [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE), count: innerArrs.count)
    super.init(innerArrs: innerArrs)
  }

  override func setSampleRateRecursive(rate: CoreFloat) {
    mixPointArr.setSampleRateRecursive(rate: rate)
    super.setSampleRateRecursive(rate: rate)
  }

  override func resetRandomRecursive(seedMap: [ObjectIdentifier: UInt64]) {
    mixPointArr.resetRandomRecursive(seedMap: seedMap)
    super.resetRandomRecursive(seedMap: seedMap)
  }

  override var extraRandomChildren: [(label: String, node: Arrow11)] {
    [("mixPoint", mixPointArr)]
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    mixPointArr.process(inputs: inputs, outputs: &mixPoints)
    // run all the arrows
    for arri in innerArrsUnmanaged.indices {
      innerArrsUnmanaged[arri]._withUnsafeGuaranteedRef { $0.process(inputs: inputs, outputs: &arrowOuts[arri]) }
    }
    // post-process to combine the correct two
    for i in inputs.indices {
      let mixPointLocal = clamp(mixPoints[i], min: 0, max: CoreFloat(innerArrsUnmanaged.count - 1))
      let arrow2Weight = mixPointLocal - floor(mixPointLocal)
      let arrow1Index = Int(floor(mixPointLocal))
      let arrow2Index = min(innerArrsUnmanaged.count - 1, Int(floor(mixPointLocal) + 1))
      outputs[i] =
        arrow2Weight * arrowOuts[arrow2Index][i] +
        (1.0 - arrow2Weight) * arrowOuts[arrow1Index][i]
    }
  }
}

// Mix two of the arrows in a list, viewing the mixPoint as a point somewhere between two of the arrows
// Use sqrt to maintain equal power and avoid a dip in perceived volume at the center point.
// Compare to Supercollider's `SelectX`
final class ArrowEqualPowerCrossfade: Arrow11 {
  private var mixPoints = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)
  private var arrowOuts = [[CoreFloat]]()
  var mixPointArr: Arrow11
  init(innerArrs: [Arrow11], mixPointArr: Arrow11) {
    self.mixPointArr = mixPointArr
    arrowOuts = [[CoreFloat]](repeating: [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE), count: innerArrs.count)
    super.init(innerArrs: innerArrs)
  }

  override func setSampleRateRecursive(rate: CoreFloat) {
    mixPointArr.setSampleRateRecursive(rate: rate)
    super.setSampleRateRecursive(rate: rate)
  }

  override func resetRandomRecursive(seedMap: [ObjectIdentifier: UInt64]) {
    mixPointArr.resetRandomRecursive(seedMap: seedMap)
    super.resetRandomRecursive(seedMap: seedMap)
  }

  override var extraRandomChildren: [(label: String, node: Arrow11)] {
    [("mixPoint", mixPointArr)]
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    mixPointArr.process(inputs: inputs, outputs: &mixPoints)
    // run all the arrows
    for arri in innerArrsUnmanaged.indices {
      innerArrsUnmanaged[arri]._withUnsafeGuaranteedRef { $0.process(inputs: inputs, outputs: &arrowOuts[arri]) }
    }
    // post-process to combine the correct two
    for i in inputs.indices {
      let mixPointLocal = clamp(mixPoints[i], min: 0, max: CoreFloat(innerArrsUnmanaged.count - 1))
      let arrow2Weight = mixPointLocal - floor(mixPointLocal)
      let arrow1Index = Int(floor(mixPointLocal))
      let arrow2Index = min(innerArrsUnmanaged.count - 1, Int(floor(mixPointLocal) + 1))
      outputs[i] =
        sqrtPosNeg(arrow2Weight * arrowOuts[arrow2Index][i]) +
        sqrtPosNeg((1.0 - arrow2Weight) * arrowOuts[arrow1Index][i])
    }
  }
}

final class ArrowRandom: Arrow11 {
  var min: CoreFloat
  var max: CoreFloat
  /// Per-node PRNG seeded by ArrowSeedMap via applyRandomSeed.
  /// Lock-free, owned by the render thread once playback starts.
  private var prng = Xorshift128Plus(seed: 0)

  override var consumesRandomness: Bool { true }
  override var pathSegment: String { "ArrowRandom" }

  override func applyRandomSeed(seedMap: [ObjectIdentifier: UInt64]) {
    if let seed = seedMap[ObjectIdentifier(self)] {
      prng = Xorshift128Plus(seed: seed)
    }
  }

  init(min: CoreFloat, max: CoreFloat) {
    self.min = min
    self.max = max
    super.init()
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    prng.nextFloat(in: min...max)
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    outputs.withUnsafeMutableBufferPointer { buf in
      guard let base = buf.baseAddress else { return }
      let lo = min, hi = max
      for i in 0..<inputs.count {
        base[i] = prng.nextFloat(in: lo...hi)
      }
    }
  }
}

final class ArrowImpulse: Arrow11 {
  var fireTime: CoreFloat
  var hasFired = false
  init(fireTime: CoreFloat) {
    self.fireTime = fireTime
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Default implementation: loop
    for i in 0..<inputs.count {
      if !hasFired && inputs[i] >= fireTime {
        hasFired = true
        outputs[i] = 1.0
      }
      outputs[i] = 0.0
    }
  }
}

final class ArrowLine: Arrow11 {
  var start: CoreFloat = 0
  var end: CoreFloat = 1
  var duration: CoreFloat = 1
  private var firstCall = true
  private var startTime: CoreFloat = 0
  init(start: CoreFloat, end: CoreFloat, duration: CoreFloat) {
    self.start = start
    self.end = end
    self.duration = duration
    super.init()
  }
  func line(_ t: CoreFloat) -> CoreFloat {
    if firstCall {
      startTime = t
      firstCall = false
      return start
    }
    if t > startTime + duration {
      return 0
    }
    return start + ((t - startTime) / duration) * (end - start)
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Default implementation: loop
    for i in 0..<inputs.count {
      outputs[i] = self.line(inputs[i])
    }
  }
}

final class ArrowIdentity: Arrow11 {
  init() {
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Identity: copy inputs to outputs without allocation
    let count = vDSP_Length(inputs.count)
    inputs.withUnsafeBufferPointer { inBuf in
      outputs.withUnsafeMutableBufferPointer { outBuf in
        vDSP_mmovD(inBuf.baseAddress!, outBuf.baseAddress!, count, 1, count, count)
      }
    }
  }
}

protocol ValHaver: AnyObject {
  var val: CoreFloat { get set }
}

final class ArrowConst: Arrow11, ValHaver, Equatable {
  var val: CoreFloat
  /// When set, this ArrowConst reads from the forwarded source's val instead of its own.
  /// Used by emitterValue arrows to read captured emitter values.
  var forwardTo: ArrowConst?
  init(value: CoreFloat) {
    self.val = value
    super.init()
  }
  /// The effective value: reads from forwardTo if set, otherwise self.val.
  var effectiveVal: CoreFloat { forwardTo?.val ?? val }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    outputs.withUnsafeMutableBufferPointer { outBuf in
      var v = effectiveVal
      vDSP_vfillD(&v, outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
    }
  }

  static func == (lhs: ArrowConst, rhs: ArrowConst) -> Bool {
    lhs.val == rhs.val
  }
}

/// Emits 1/val for every sample. Useful for building reciprocal expressions
/// from event-derived values (e.g. `1 / (noteClass + 1)`).
final class ArrowConstReciprocal: Arrow11, ValHaver, Equatable {
  var val: CoreFloat
  init(value: CoreFloat) {
    self.val = value
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    outputs.withUnsafeMutableBufferPointer { outBuf in
      var v = val != 0 ? 1.0 / val : 0.0
      vDSP_vfillD(&v, outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
    }
  }
  static func == (lhs: ArrowConstReciprocal, rhs: ArrowConstReciprocal) -> Bool {
    lhs.val == rhs.val
  }
}

/// Composes with an inner arrow and emits 1/x for each sample.
/// Returns 0 when the input is 0.
final class ArrowReciprocal: Arrow11 {
  private var scratchBuffer = [CoreFloat](repeating: 0, count: MAX_BUFFER_SIZE)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &scratchBuffer)
    let count = inputs.count
    for i in 0..<count {
      let v = scratchBuffer[i]
      outputs[i] = v != 0 ? 1.0 / v : 0.0
    }
  }
}

final class ArrowConstOctave: Arrow11, ValHaver, Equatable {
  var val: CoreFloat {
    didSet {
      twoToTheVal = pow(2, val)
    }
  }
  var twoToTheVal: CoreFloat
  init(value: CoreFloat) {
    self.val = value
    self.twoToTheVal = pow(2, val)
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    outputs.withUnsafeMutableBufferPointer { outBuf in
      var v = twoToTheVal
      vDSP_vfillD(&v, outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
    }
  }
  static func == (lhs: ArrowConstOctave, rhs: ArrowConstOctave) -> Bool {
    lhs.val == rhs.val
  }
}

final class ArrowConstCent: Arrow11, ValHaver, Equatable {
  let cent: CoreFloat = 1.0005777895065548 // '2 ** (1/1200)' in python
  var val: CoreFloat {
    didSet {
      self.centToTheVal = pow(cent, val)
    }
  }
  var centToTheVal: CoreFloat

  init(value: CoreFloat) {
    self.val = value
    self.centToTheVal = pow(cent, val)
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    outputs.withUnsafeMutableBufferPointer { outBuf in
      var v = centToTheVal
      vDSP_vfillD(&v, outBuf.baseAddress!, 1, vDSP_Length(inputs.count))
    }
  }
  static func == (lhs: ArrowConstCent, rhs: ArrowConstCent) -> Bool {
    lhs.val == rhs.val
  }
}
