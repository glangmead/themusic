//
//  IteratorWrappers.swift
//  Orbital
//
//  Time-gating, latching, and adapter wrappers extracted from Iterators.swift.
//

import Foundation

// A class that uses an arrow to tell it how long to wait before calling next() on an iterator.
// While waiting to call next() on the internal iterator, it returns the most recent value repeatedly.
class WaitingIterator<Element>: Sequence, IteratorProtocol {
  // state
  var savedTime: TimeInterval
  var timeBetweenChanges: Arrow11
  var mostRecentElement: Element?
  var neverCalled = true
  // underlying iterator
  var timeIndependentIterator: any IteratorProtocol<Element>

  init(iterator: any IteratorProtocol<Element>, timeBetweenChanges: Arrow11) {
    self.timeIndependentIterator = iterator
    self.timeBetweenChanges = timeBetweenChanges
    self.savedTime = Date.now.timeIntervalSince1970
    mostRecentElement = nil
  }

  func next() -> Element? {
    let now = Date.now.timeIntervalSince1970
    let timeElapsed = CoreFloat(now - savedTime)
    // yeah the arrow tells us how long to wait, given what time it is
    if timeElapsed > timeBetweenChanges.of(timeElapsed) || neverCalled {
      mostRecentElement = timeIndependentIterator.next()
      savedTime = now
      neverCalled = false
    }
    return mostRecentElement
  }
}

// MARK: - LatchingIterator

/// An iterator wrapper that caches its last value for a short window.
/// Multiple callers within the window receive the same value without
/// advancing the inner iterator. After the window expires, the next
/// call advances the inner iterator and starts a new latch window.
/// Used for shared emitter instances across tracks (~15ms = 1/64 second).
class LatchingIterator<Element>: Sequence, IteratorProtocol {
  private var inner: any IteratorProtocol<Element>
  private var cachedValue: Element?
  private var lastAdvanceTime: TimeInterval = 0
  private let latchDuration: TimeInterval

  init(inner: any IteratorProtocol<Element>, latchDuration: TimeInterval = 1.0 / 64.0) {
    self.inner = inner
    self.latchDuration = latchDuration
  }

  func next() -> Element? {
    let now = Date.now.timeIntervalSince1970
    if let cached = cachedValue, (now - lastAdvanceTime) < latchDuration {
      return cached
    }
    cachedValue = inner.next()
    lastAdvanceTime = now
    return cachedValue
  }
}

// MARK: - FragmentPoolIterator

/// Randomly picks a fragment from a pool, yields its values one at a time,
/// then picks another fragment when the current one is exhausted. Loops forever.
/// Used as a general-purpose int emitter (e.g. for intervalPicker in table patterns).
struct FragmentPoolIterator: Sequence, IteratorProtocol {
  let fragments: [[Int]]
  private var currentIndex: Int
  private var position: Int = 0

  init(fragments: [[Int]]) {
    self.fragments = fragments
    self.currentIndex = fragments.isEmpty ? 0 : Int.random(in: 0..<fragments.count)
  }

  mutating func next() -> Int? {
    guard !fragments.isEmpty else { return nil }
    let fragment = fragments[currentIndex]
    if position >= fragment.count {
      currentIndex = Int.random(in: 0..<fragments.count)
      position = 0
    }
    let value = fragments[currentIndex][position]
    print("pool: playing \(value) from \(fragments[currentIndex])")
    position += 1
    return value
  }
}

// MARK: - CapturingIterator

/// Wraps an iterator and writes the float-coerced last value to a shadow ArrowConst
/// that was provided to the init() on each next().
/// Used so that arrow-based modulators can read emitter values.
class CapturingIterator<T>: Sequence, IteratorProtocol {
  private var inner: any IteratorProtocol<T>
  private let shadow: ArrowConst
  private let toFloat: (T) -> CoreFloat

  init(inner: any IteratorProtocol<T>, shadow: ArrowConst, toFloat: @escaping (T) -> CoreFloat) {
    self.inner = inner
    self.shadow = shadow
    self.toFloat = toFloat
  }

  func next() -> T? {
    guard let value = inner.next() else { return nil }
    shadow.val = toFloat(value)
    return value
  }
}

// MARK: - IntToFloatIterator

/// Adapts an Int iterator to produce CoreFloat values.
struct IntToFloatIterator: Sequence, IteratorProtocol {
  var source: any IteratorProtocol<Int>
  mutating func next() -> CoreFloat? {
    guard let val = source.next() else { return nil }
    return CoreFloat(val)
  }
}
