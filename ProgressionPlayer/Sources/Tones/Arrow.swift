//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import AVFAudio
import Overture
import SwiftUI

// This is Double because an AVAudioSourceNodeRenderBlock sends the input (time) as a Float64
typealias CoreFloat = Double

class Arrow11 {
  // these are arrows with which we can compose (arr/arrs run first, then this arrow)
  var innerArr: Arrow11? = nil
  var innerArrs = ContiguousArray<Arrow11>()
  
  init(innerArr: Arrow11? = nil) {
    self.innerArr = innerArr
  }
  
  init(innerArrs: ContiguousArray<Arrow11>) {
    self.innerArrs = innerArrs
  }
  
  init(innerArrs: [Arrow11]) {
    self.innerArrs = ContiguousArray<Arrow11>(innerArrs)
  }
  
  func inner(_ t: CoreFloat) -> CoreFloat {
    innerArr?.of(t) ?? t
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
  var lastTimeEmittedSecs = 0.0
  var lastEmission = 0.0
  let timeBetweenEmissionsSecs = 441.0 / 44100.0
  
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
    var total: CoreFloat = 0
    for i in 0..<innerArrs.count {
      total += innerArrs[i].of(t)
    }
    return total
  }
}

final class ArrowProd: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    var result: CoreFloat = 1
    for i in 0..<innerArrs.count {
      result *= innerArrs[i].of(t)
    }
    return result
  }
}

final class ArrowIdentity: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat { t }
  init() {
    super.init()
  }
}

final class ArrowConst: Arrow11, Equatable {
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

final class ArrowConstF: Arrow11, Equatable {
  var val: Float
  init(value: Float) {
    self.val = value
    super.init()
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    CoreFloat(val)
  }
  static func == (lhs: ArrowConstF, rhs: ArrowConstF) -> Bool {
    lhs.val == rhs.val
  }
}

