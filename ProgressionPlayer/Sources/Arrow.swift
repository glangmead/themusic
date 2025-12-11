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
  var of: (CoreFloat) -> ()
  init(of: @escaping (CoreFloat) -> ()) {
    self.of = of
  }

  func asControl() -> Arrow10 {
    return ControlArrow10(of: self)
  }
}

class Arrow11 {
  var of: (CoreFloat) -> CoreFloat
  init(of: @escaping (CoreFloat) -> CoreFloat) {
    self.of = of
  }
  
  func withSidecars(_ sidecars: [Arrow10]) -> Arrow11 {
    return Arrow11WithSidecars(arr: self, sidecars: sidecars)
  }

  func withSidecar(_ sidecar: Arrow10) -> Arrow11 {
    return withSidecars([sidecar])
  }

  func asControl() -> Arrow11 {
    return ControlArrow11(of: self)
  }
}

class Arrow21 {
  var of: (CoreFloat, CoreFloat) -> CoreFloat
  init(of: @escaping (CoreFloat, CoreFloat) -> CoreFloat) {
    self.of = of
  }
}

class Arrow13 {
  var of: (CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat)
  init(of: @escaping (CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat)) {
    self.of = of
  }
}

class Arrow12 {
  var of: (CoreFloat) -> (CoreFloat, CoreFloat)
  init(of: @escaping (CoreFloat) -> (CoreFloat, CoreFloat)) {
    self.of = of
  }
}

// An arrow that wraps an arrow and limits how often the arrow gets called with a new time
// The name comes from the paradigm that control signals like LFOs don't need to fire as often
// as audio data.
class ControlArrow11: Arrow11 {
  var lastTimeEmitted = 0.0
  var lastEmission = 0.0
  let timeBetweenEmissions = 441.0 / 44100.0
  init(of arrow: Arrow11) {
    weak var fself: ControlArrow11? = nil
    super.init(of: { t in
      if t - fself!.lastTimeEmitted >= fself!.timeBetweenEmissions {
        fself!.lastEmission = arrow.of(t)
        fself!.lastTimeEmitted = t
      }
      return fself!.lastEmission
    })
    fself = self
  }
}

class ControlArrow10: Arrow10 {
  var lastTimeEmitted = 0.0
  let timeBetweenEmissions = 4410.0 / 44100.0
  init(of arrow: Arrow10) {
    weak var fself: ControlArrow10? = nil
    super.init(of: { t in
      if t - fself!.lastTimeEmitted >= fself!.timeBetweenEmissions {
        arrow.of(t)
        fself!.lastTimeEmitted = t
      }
    })
    fself = self
  }
}

class ArrowSum: Arrow11 {
  init(_ arrows: [Arrow11]) {
    super.init(of: {x in
      arrows.map({$0.of(x)}).reduce(0, +)
    })
  }
}

class ArrowProd: Arrow11 {
  init(_ arrows: [Arrow11]) {
    super.init(of: {x in
      arrows.map({$0.of(x)}).reduce(1, *)
    })
  }
}

class ArrowIdentity: Arrow11 {
  init() {
    super.init(of: { $0 })
  }
}

class ArrowCompose: Arrow11 {
  init(outer: Arrow11, inner: Arrow11) {
    super.init(of: { t in
      outer.of(inner.of(t))
    })
  }
}

class ArrowSin: Arrow11 {
  init() {
    super.init(of: {Foundation.sin($0)})
  }
}

class ArrowCos: Arrow11 {
  init() {
    super.init(of: {Foundation.cos($0)})
  }
}

class ArrowConst: Arrow11, Equatable {
  var val: CoreFloat

  init(_ value: CoreFloat) {
    self.val = value
    weak var fself: ArrowConst? = nil
    super.init(of: { _ in
      fself!.val
    })
    fself = self
  }
  
  static func == (lhs: ArrowConst, rhs: ArrowConst) -> Bool {
    lhs.val == rhs.val
  }
}

class ArrowConstF: Arrow11, Equatable {
  var val: Float

  init(_ val: Float) {
    self.val = val
    weak var fself: ArrowConstF? = nil
    super.init(of: { _ in
      Double(fself!.val)
    })
    fself = self
  }

  static func == (lhs: ArrowConstF, rhs: ArrowConstF) -> Bool {
    lhs.val == rhs.val
  }
}

class Arrow11WithSidecars: Arrow11 {
  init(arr: Arrow11, sidecars: [Arrow10]) {
    super.init(of: {x in
      for sidecar in sidecars {
        sidecar.of(x)
      }
      return arr.of(x)
    })
  }
}

