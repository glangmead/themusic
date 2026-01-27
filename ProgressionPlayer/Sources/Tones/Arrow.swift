//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import AVFAudio
import Overture
import SwiftUI

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

  func inner(_ t: CoreFloat) -> CoreFloat {
    innerArr?.of(t) ?? t
  }
  
  func unmanagedInner(_ t: CoreFloat) -> CoreFloat {
    innerArrUnmanaged?._withUnsafeGuaranteedRef { $0.of(t) } ?? t
  }
  
  func of (_ t: CoreFloat) -> CoreFloat { inner(t) }
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
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    if t - lastTimeEmittedSecs >= timeBetweenEmissionsSecs {
      lastEmission = inner(t)
      lastTimeEmittedSecs = t
    }
    return lastEmission
  }
}

final class ArrowSum: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    var result: CoreFloat = 0
    for i in 0..<innerArrsUnmanaged.count {
      result += innerArrsUnmanaged[i]._withUnsafeGuaranteedRef { $0.of(t) }
    }
    return result
  }
}

final class ArrowProd: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    var result: CoreFloat = 1
    for i in 0..<innerArrsUnmanaged.count {
      result *= innerArrsUnmanaged[i]._withUnsafeGuaranteedRef { $0.of(t) }
    }
    return result
  }
}

func clamp(_ val: CoreFloat, min: CoreFloat, max: CoreFloat) -> CoreFloat {
  if val < min { return min }
  if val > max { return max }
  return val
}

// Mix two of the arrows in a list, viewing the mixPoint as a point somewhere between two of the arrows
// Compare to Supercollider's `Select`
final class ArrowCrossfade: Arrow11 {
  var mixPointArr: Arrow11
  init(innerArrs: [Arrow11], mixPointArr: Arrow11 = ArrowConst(value: 0)) {
    self.mixPointArr = mixPointArr
    super.init(innerArrs: innerArrs)
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    // ensure mixPoint is between 0 and the number of arrows
    let mixPointLocal = clamp(mixPointArr.of(t), min: 0, max: CoreFloat(innerArrsUnmanaged.count))
    let arrow1 = innerArrsUnmanaged[Int(floor(mixPointLocal))]
    let arrow2 = innerArrsUnmanaged[Int(ceil(mixPointLocal))]
    let arrow1Weight = mixPointLocal - floor(mixPointLocal)
    
    return (arrow1Weight * arrow1._withUnsafeGuaranteedRef { $0.of(t) }) +
      ((1.0 - arrow1Weight) * arrow2._withUnsafeGuaranteedRef { $0.of(t) })
  }
}

// Mix two of the arrows in a list, viewing the mixPoint as a point somewhere between two of the arrows
// Use sqrt to maintain equal power and avoid a dip in perceived volume at the center point.
// Compare to Supercollider's `SelectX`
final class ArrowEqualPowerCrossfade: Arrow11 {
  var mixPointArr: Arrow11
  init(innerArrs: [Arrow11], mixPointArr: Arrow11 = ArrowConst(value: 0)) {
    self.mixPointArr = mixPointArr
    super.init(innerArrs: innerArrs)
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    // ensure mixPoint is between 0 and the number of arrows
    let mixPointLocal = clamp(mixPointArr.of(t), min: 0, max: CoreFloat(innerArrsUnmanaged.count))
    let arrow1 = innerArrsUnmanaged[Int(floor(mixPointLocal))]
    let arrow2 = innerArrsUnmanaged[Int(ceil(mixPointLocal))]
    let arrow1Weight = mixPointLocal - floor(mixPointLocal)
    
    return sqrt(arrow1Weight * arrow1._withUnsafeGuaranteedRef { $0.of(t) }) +
      sqrt((1.0 - arrow1Weight) * arrow2._withUnsafeGuaranteedRef { $0.of(t) })
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
  override func of(_ t: CoreFloat) -> CoreFloat {
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
}

final class ArrowIdentity: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat { t }
  init() {
    super.init()
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
  override func of(_ t: CoreFloat) -> CoreFloat {
    val
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
  override func of(_ t: CoreFloat) -> CoreFloat {
    twoToTheVal
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
  override func of(_ t: CoreFloat) -> CoreFloat {
    centToTheVal
  }
  static func == (lhs: ArrowConstCent, rhs: ArrowConstCent) -> Bool {
    lhs.val == rhs.val
  }
}

// Takes on random values every 1/sampleFreq seconds, and smoothly interpolates between
final class ArrowSmoothStep: Arrow11, WidthHaver {
  var widthArr: Arrow11 = ArrowConst(value: 1) // so that it can be a BasicOscillator
  var noiseFreq: CoreFloat = 1
  var min: CoreFloat = -1
  var max: CoreFloat = 1
  private var previousTime: CoreFloat = 0
  private var deltaTime: CoreFloat = 0
  private var lastNoiseTime: CoreFloat
  private var nextNoiseTime: CoreFloat
  private var lastSample: CoreFloat
  private var nextSample: CoreFloat
  private var epsilon: CoreFloat = 1e-7
  private var noiseDeltaTime: CoreFloat {
    1.0 / noiseFreq
  }
  
  init(sampleFreq: CoreFloat, min: CoreFloat = -1, max: CoreFloat = 1) {
    self.noiseFreq = sampleFreq
    self.min = min
    self.max = max
    self.lastSample = CoreFloat.random(in: min...max)
    self.nextSample = CoreFloat.random(in: min...max)
    lastNoiseTime = 0
    nextNoiseTime = lastNoiseTime + (1.0 / sampleFreq)
    super.init()
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    // compute the actual time between samples
    if previousTime == 0 {
      previousTime = t
      return 0
    } else if deltaTime == 0 {
      deltaTime = t - previousTime
      return 0
    }
    
    let modT = fmod(t, noiseDeltaTime)
    // generate smoothstep for x between 0 and 1, y between 0 and 1
    let betweenTime = modT / noiseDeltaTime
    let zeroOneSmooth = betweenTime * betweenTime * (3 - 2 * betweenTime)
    let result = lastSample + (zeroOneSmooth * (nextSample - lastSample))
    
    if abs(modT - noiseDeltaTime) <= deltaTime {
      lastSample = nextSample
      nextSample = CoreFloat.random(in: min...max)
      lastNoiseTime = nextNoiseTime
      nextNoiseTime += noiseDeltaTime
    }
    return result
  }
}

#Preview {
  let osc = ArrowSmoothStep(sampleFreq: 50)
  osc.innerArr = ArrowProd(innerArrs: [ArrowConst(value: 1), ArrowIdentity()])
  return ArrowChart(arrow: osc)
}
