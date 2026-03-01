//
//  Samplers.swift
//  Orbital
//
//  Stateless and mutable random samplers extracted from Iterators.swift.
//

import Foundation
import Tonic

struct ListSampler<Element>: Sequence, IteratorProtocol {
  let items: [Element]
  init(_ items: [Element]) {
    self.items = items
  }
  func next() -> Element? {
    items.randomElement()
  }
}

// sample notes from a scale: [MidiNote]
struct ScaleSampler: Sequence, IteratorProtocol {
  typealias Element = [MidiNote]
  var scale: Scale

  init(scale: Scale = Scale.aeolian) {
    self.scale = scale
  }

  func next() -> [MidiNote]? {
    return [MidiNote(
      note: MidiValue(Note.A.shiftUp(scale.intervals.randomElement()!)!.noteNumber),
      velocity: (50...127).randomElement()!
    )]
  }
}

enum ProbabilityDistribution {
  case uniform
  case exponential
}

struct FloatSampler: Sequence, IteratorProtocol {
  typealias Element = CoreFloat
  let distribution: ProbabilityDistribution
  let min: CoreFloat
  let max: CoreFloat
  private let lambda: CoreFloat

  init(min: CoreFloat, max: CoreFloat, dist: ProbabilityDistribution = .uniform) {
    self.distribution = dist
    self.min = Swift.min(min, max)
    self.max = Swift.max(min, max)
    let range = self.max - self.min
    self.lambda = range > 0 ? -log(0.05) / range : 1
  }

  func next() -> CoreFloat? {
    switch distribution {
    case .uniform:
      return CoreFloat.random(in: min...max)
    case .exponential:
      let u = CoreFloat.random(in: CoreFloat.ulpOfOne...1)
      let raw = -log(u) / lambda
      return clamp(min + raw, min: min, max: max)
    }
  }
}

// MARK: - IntSampler

/// Generates random integers in a range. Stateless — safe with any update mode.
struct IntSampler: Sequence, IteratorProtocol {
  let min: Int
  let max: Int

  func next() -> Int? {
    Int.random(in: min...max)
  }
}

// MARK: - MutableParam

/// A mutable parameter holder for emitters, enabling meta-modulation.
/// When a modulator targets "emitterName.arg1", the compiler wires
/// the modulating arrow to write to this object's `val` property.
/// The emitter reads `val` on each `next()` call.
final class MutableParam {
  var val: CoreFloat
  init(_ val: CoreFloat) { self.val = val }
}

// MARK: - MutableFloatSampler

/// A FloatSampler variant whose min/max can be changed at runtime
/// via MutableParam references, enabling meta-modulation.
struct MutableFloatSampler: Sequence, IteratorProtocol {
  let minParam: MutableParam
  let maxParam: MutableParam

  func next() -> CoreFloat? {
    let lo = minParam.val
    let hi = maxParam.val
    guard hi > lo else { return lo }
    return CoreFloat.random(in: lo...hi)
  }
}
