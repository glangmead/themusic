//
//  EmitterBridge.swift
//  Orbital
//
//  Arrow11 bridges and arithmetic operators for emitters, extracted from Iterators.swift.
//

import Foundation

// MARK: - EmitterArrow

/// Bridges a float emitter (IteratorProtocol<CoreFloat>) into an Arrow11
/// so it can be used as a modulator in the existing MusicEvent pipeline.
final class EmitterArrow: Arrow11 {
  private var emitter: any IteratorProtocol<CoreFloat>

  init(emitter: any IteratorProtocol<CoreFloat>) {
    self.emitter = emitter
    super.init()
  }

  override func of(_ t: CoreFloat) -> CoreFloat {
    emitter.next() ?? 0
  }
}

// MARK: - SumIterator

/// Sums the next() values of multiple float emitters.
struct SumIterator: Sequence, IteratorProtocol {
  var sources: [any IteratorProtocol<CoreFloat>]

  mutating func next() -> CoreFloat? {
    var total: CoreFloat = 0
    for i in sources.indices {
      total += sources[i].next() ?? 0
    }
    return total
  }
}

// MARK: - ReciprocalIterator

/// Returns 1/x of the next() value from a source emitter.
struct ReciprocalIterator: Sequence, IteratorProtocol {
  var source: any IteratorProtocol<CoreFloat>

  mutating func next() -> CoreFloat? {
    guard let val = source.next(), val != 0 else { return 0 }
    return 1.0 / val
  }
}

// MARK: - IndexPickerIterator

/// Uses an int emitter to pick elements from a fixed array.
class IndexPickerIterator<Element>: Sequence, IteratorProtocol {
  private var indexEmitter: any IteratorProtocol<Int>
  private let items: [Element]

  init(items: [Element], indexEmitter: any IteratorProtocol<Int>) {
    self.items = items
    self.indexEmitter = indexEmitter
  }

  func next() -> Element? {
    guard !items.isEmpty else { return nil }
    guard let idx = indexEmitter.next() else { return nil }
    let clamped = Swift.max(0, Swift.min(idx, items.count - 1))
    return items[clamped]
  }
}

// MARK: - MetaModulationArrow

/// An Arrow11 that reads from a float emitter and writes the value
/// to a MutableParam on the target emitter. Returns the written value.
final class MetaModulationArrow: Arrow11 {
  private var source: any IteratorProtocol<CoreFloat>
  private let target: MutableParam

  init(source: any IteratorProtocol<CoreFloat>, target: MutableParam) {
    self.source = source
    self.target = target
    super.init()
  }

  override func of(_ t: CoreFloat) -> CoreFloat {
    let val = source.next() ?? target.val
    target.val = val
    return val
  }
}
