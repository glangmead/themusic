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

class Arrow10 {
  func of(_ t: CoreFloat) {  }

  func asControl() -> Arrow10 {
    return ControlArrow10(self)
  }
}

class Arrow11 {
  func of(_ t: CoreFloat) -> CoreFloat { t }
  
  func asControl() -> Arrow11 {
    return ControlArrow11(self)
  }
}

class Arrow13 {
  func of(_ t: CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat) { (t, t, t) }
}

// An arrow that wraps an arrow and limits how often the arrow gets called with a new time
// The name comes from the paradigm that control signals like LFOs don't need to fire as often
// as audio data.
final class ControlArrow11: Arrow11 {
  var wrapped: Arrow11
  var lastTimeEmittedSecs = 0.0
  var lastEmission = 0.0
  let timeBetweenEmissionsSecs = 441.0 / 44100.0
  
  init(_ wrapped: Arrow11) {
    self.wrapped = wrapped
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    if t - lastTimeEmittedSecs >= timeBetweenEmissionsSecs {
      lastEmission = wrapped.of(t)
      lastTimeEmittedSecs = t
    }
    return lastEmission
  }
}

final class ControlArrow10: Arrow10 {
  var wrapped: Arrow10
  var lastTimeEmitted = 0.0
  let timeBetweenEmissions = 4410.0 / 44100.0
  init(_ wrapped: Arrow10) {
    self.wrapped = wrapped
  }
  override func of(_ t: CoreFloat) {
    if t - lastTimeEmitted >= timeBetweenEmissions {
      wrapped.of(t)
      lastTimeEmitted = t
    }
  }
}

final class ArrowSum: Arrow11 {
  var arrows: [Arrow11]
  init(_ arrows: [Arrow11]) {
    self.arrows = arrows
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    var total: CoreFloat = 0
    for arrow in arrows {
      total += arrow.of(t)
    }
    return total
  }
}

final class ArrowProd: Arrow11 {
  var arrows: [Arrow11]
  init(_ arrows: [Arrow11]) {
    self.arrows = arrows
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    var result: CoreFloat = 1
    for arrow in arrows {
      result *= arrow.of(t)
    }
    return result
  }
}

final class ArrowIdentity: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat { t }
}

final class ArrowCompose: Arrow11 {
  var outer: Arrow11
  var inner: Arrow11
  init(outer: Arrow11, inner: Arrow11) {
    self.outer = outer
    self.inner = inner
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    outer.of(inner.of(t))
  }
}

final class ArrowSin: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    Foundation.sin(t)
  }
}

final class ArrowCos: Arrow11 {
  override func of(_ t: CoreFloat) -> CoreFloat {
    Foundation.cos(t)
  }
}

final class ArrowConst: Arrow11, Equatable {
  var val: CoreFloat
  init(_ value: CoreFloat) {
    self.val = value
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
  init(_ value: Float) {
    self.val = value
  }
  override func of(_ t: CoreFloat) -> CoreFloat {
    CoreFloat(val)
  }
  static func == (lhs: ArrowConstF, rhs: ArrowConstF) -> Bool {
    lhs.val == rhs.val
  }
}

