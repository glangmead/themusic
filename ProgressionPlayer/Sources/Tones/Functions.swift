//
//  Functions.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/15/25.
//

import Foundation
import Overture

struct Interval<F: Numeric & Comparable> {
  let start: F?
  let end: F?
  func contains(_ val: F) -> Bool {
    return ((start == nil) || (val >= start!)) && ((end == nil) || (val <= end!))
  }
}

struct IntervalFunc<F: Numeric & Comparable> {
  let interval: Interval<F>
  let f: (F) -> F
  func val(_ time: F) -> F {
    if interval.contains(time) {
      return f(time)
    }
    return 0
  }
}

struct PiecewiseFunc<F: Numeric & Comparable> {
  let ifuncs: [IntervalFunc<F>]
  func val(_ time: F) -> F {
    for i_f in ifuncs {
      if i_f.interval.contains(time) {
        return i_f.f(time)
      }
    }
    return 0
  }
}

struct CycleSequence<C: Collection>: Sequence {
  let cycledElements: C
  
  init(_ cycledElements: C) {
    self.cycledElements = cycledElements
  }
  
  public func makeIterator() -> CycleIterator<C> {
    return CycleIterator(cycling: cycledElements)
  }
}

struct CycleIterator<C: Collection>: IteratorProtocol {
  let cycledElements: C
  var cycledElementIterator: C.Iterator
  
  init(cycling cycledElements: C) {
    self.cycledElements = cycledElements
    self.cycledElementIterator = cycledElements.makeIterator()
  }
  
  public mutating func next() -> C.Iterator.Element? {
    if let next = cycledElementIterator.next() {
      return next
    } else {
      self.cycledElementIterator = cycledElements.makeIterator() // Cycle back again
      return cycledElementIterator.next()
    }
  }
}

extension Collection {
  func cycle() -> CycleSequence<Self> {
    CycleSequence(self)
  }
}
