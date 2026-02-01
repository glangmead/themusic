//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import Accelerate
import AVFAudio

typealias CoreFloat = Float

class Arrow11 {
  // these are arrows with which we can compose (arr/arrs run first, then this arrow)
  var innerArr: Arrow11? = nil {
    didSet {
      if let inner = innerArr {
        self.innerArrUnmanaged = Unmanaged.passUnretained(inner)
      }
    }
  }
  private var innerArrUnmanaged: Unmanaged<Arrow11>? = nil

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
    var input = [CoreFloat](repeating: 0, count: 512)
    input[0] = t
    var result = [CoreFloat](repeating: 0, count: 512)
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
  let timeBetweenEmissionsSecs: CoreFloat = 441.0 / 44100.0
  private var scratchBuffer = [CoreFloat](repeating: 0, count: 512)

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    (innerArr ?? ArrowIdentity()).process(inputs: inputs, outputs: &scratchBuffer)
    for i in 0..<inputs.count {
      let t = inputs[i]
      if t - lastTimeEmittedSecs >= timeBetweenEmissionsSecs {
        lastEmission = scratchBuffer[i]
        lastTimeEmittedSecs = t
      }
      outputs[i] = lastEmission
    }
    let mean = vDSP.mean(outputs)
  }
}

final class ArrowSum: Arrow11 {
  private var scratchBuffer = [CoreFloat](repeating: 0, count: 512)
  
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    if innerArrsUnmanaged.isEmpty {
      vDSP.clear(&outputs)
      return
    }
    
    // Process first child directly to output
    innerArrsUnmanaged[0]._withUnsafeGuaranteedRef {
      $0.process(inputs: inputs, outputs: &outputs)
    }
    
    // Process remaining children via scratch
    if innerArrsUnmanaged.count > 1 {
      for i in 1..<innerArrsUnmanaged.count {
        innerArrsUnmanaged[i]._withUnsafeGuaranteedRef {
          $0.process(inputs: inputs, outputs: &scratchBuffer)
        }
        // output = output + scratch
        vDSP.add(scratchBuffer, outputs, result: &outputs)
      }
    }
  }
}

final class ArrowProd: Arrow11 {
  private var scratchBuffer = [CoreFloat](repeating: 0, count: 512)
  private var scratchBuffer2 = [CoreFloat](repeating: 0, count: 512)
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    if innerArrsUnmanaged.isEmpty {
      vDSP.fill(&outputs, with: 1)
      return
    }
    
    for i in innerArrs.indices {
      if let arrowConst = innerArrs[i] as? ArrowConst {
        if arrowConst.val == 300 {
          print("got a 300 here")
        }
      }
    }
    
    // Process first child directly to output
    innerArrsUnmanaged[0]._withUnsafeGuaranteedRef {
      $0.process(inputs: inputs, outputs: &outputs)
    }
    
    // Process remaining children via scratch
    if innerArrsUnmanaged.count > 1 {
      for i in 1..<innerArrsUnmanaged.count {
        innerArrsUnmanaged[i]._withUnsafeGuaranteedRef {
          $0.process(inputs: inputs, outputs: &scratchBuffer)
        }
        // output = output * scratch
        vDSP.multiply(scratchBuffer, outputs, result: &scratchBuffer2)
        outputs = scratchBuffer2
      }
    }
  }
}

func clamp(_ val: CoreFloat, min: CoreFloat, max: CoreFloat) -> CoreFloat {
  if val < min { return min }
  if val > max { return max }
  return val
}

final class ArrowExponentialRandom: Arrow11 {
  var min: CoreFloat
  var max: CoreFloat
  init(min: CoreFloat, max: CoreFloat) {
    let neg = min < 0 || max < 0
    self.min = neg ? clamp(min, min: min, max: -0.001) : clamp(min, min: 0.001, max: min)
    self.max = neg ? clamp(max, min: max, max: -0.001) : clamp(max, min: 0.001, max: max)
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Default implementation: loop
    for i in 0..<inputs.count {
      outputs[i] = min * exp(log(max / min) * CoreFloat.random(in: 0...1))
    }
  }
}

func sqrtPosNeg(_ val: CoreFloat) -> CoreFloat {
  val >= 0 ? sqrt(val) : -sqrt(-val)
}

// Mix two of the arrows in a list, viewing the mixPoint as a point somewhere between two of the arrows
// Compare to Supercollider's `Select`
final class ArrowCrossfade: Arrow11 {
  private var mixPoints = [CoreFloat](repeating: 0, count: 512)
  private var arrowOuts = [[CoreFloat]]()
  var mixPointArr: Arrow11
  init(innerArrs: [Arrow11], mixPointArr: Arrow11) {
    self.mixPointArr = mixPointArr
    arrowOuts = [[CoreFloat]](repeating: [CoreFloat](repeating: 0, count: 512), count: innerArrs.count)
    super.init(innerArrs: innerArrs)
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
  private var mixPoints = [CoreFloat](repeating: 0, count: 512)
  private var arrowOuts = [[CoreFloat]]()
  var mixPointArr: Arrow11
  init(innerArrs: [Arrow11], mixPointArr: Arrow11) {
    self.mixPointArr = mixPointArr
    arrowOuts = [[CoreFloat]](repeating: [CoreFloat](repeating: 0, count: 512), count: innerArrs.count)
    super.init(innerArrs: innerArrs)
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
  init(min: CoreFloat, max: CoreFloat) {
    self.min = min
    self.max = max
    super.init()
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    CoreFloat.random(in: min...max)
  }
  
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    // Default implementation: loop
    for i in 0..<inputs.count {
      outputs[i] = CoreFloat.random(in: min...max)
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
    // Identity: copy inputs to outputs
    outputs = inputs
  }
}

protocol ValHaver: AnyObject {
  var val: CoreFloat { get set }
}

final class ArrowConst: Arrow11, ValHaver, Equatable {
  var val: CoreFloat
  init(value: CoreFloat) {
    self.val = value
    super.init()
  }
  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    vDSP.fill(&outputs, with: val)
    //vDSP_vfill(&val, outputs.baseAddress!, 1, vDSP_Length(inputs.count))
  }

  static func == (lhs: ArrowConst, rhs: ArrowConst) -> Bool {
    lhs.val == rhs.val
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
    vDSP.fill(&outputs, with: twoToTheVal)
    //vDSP_vfill(&twoToTheVal, outputs.baseAddress!, 1, vDSP_Length(inputs.count))
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
    vDSP.fill(&outputs, with: centToTheVal)
    //vDSP_vfill(&centToTheVal, outputs.baseAddress!, 1, vDSP_Length(inputs.count))
  }
  static func == (lhs: ArrowConstCent, rhs: ArrowConstCent) -> Bool {
    lhs.val == rhs.val
  }
}

