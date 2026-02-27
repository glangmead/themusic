//
//  Iterators.swift
//  Orbital
//
//  Extracted from Pattern.swift
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

// A class that uses an arrow to tell it how long to wait before calling next() on an iterator
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

// MARK: - Tymoczko Chord Types

/// The 14 chord types from Tymoczko's "Tonality" diagram 7.1.3,
/// used for Baroque/Classical major-key chord progressions.
enum TymoczkoChords713: Hashable {
  case I, vi, IV, ii, V, iii
  case I6, IV6, ii6, V6, iii6, vi6, viio6, I64

  /// 1-indexed scale degrees for each chord voicing.
  var scaleDegrees: [Int] {
    switch self {
    case .I:     [1, 3, 5]
    case .vi:    [6, 1, 3]
    case .IV:    [4, 6, 1]
    case .ii:    [2, 4, 6]
    case .V:     [5, 7, 2]
    case .iii:   [3, 5, 7]
    case .I6:    [3, 5, 1]
    case .IV6:   [6, 1, 4]
    case .ii6:   [4, 6, 2]
    case .V6:    [7, 2, 5]
    case .iii6:  [5, 7, 3]
    case .vi6:   [1, 3, 6]
    case .viio6: [2, 4, 7]
    case .I64:   [5, 1, 3]
    }
  }

  /// Roman numeral display name for UI presentation.
  var displayName: String {
    switch self {
    case .I:     "I"
    case .vi:    "vi"
    case .IV:    "IV"
    case .ii:    "ii"
    case .V:     "V"
    case .iii:   "iii"
    case .I6:    "I6"
    case .IV6:   "IV6"
    case .ii6:   "ii6"
    case .V6:    "V6"
    case .iii6:  "iii6"
    case .vi6:   "vi6"
    case .viio6: "viio6"
    case .I64:   "I64"
    }
  }

  /// Look up the chord display name for a given index in `MarkovChordIndexIterator.chordOrder`.
  static func chordDisplayName(forIndex index: Int) -> String? {
    guard index >= 0, index < MarkovChordIndexIterator.chordOrder.count else { return nil }
    return MarkovChordIndexIterator.chordOrder[index].displayName
  }

  /// Probabilistic state transitions according to Tymoczko diagram 7.1.3 of Tonality.
  static func stateTransitionsBaroqueClassicalMajor(_ start: TymoczkoChords713) -> [(TymoczkoChords713, CoreFloat)] {
    switch start {
    case .I:
      return [            (.vi, 0.07),  (.IV, 0.21),  (.ii, 0.14), (.viio6, 0.05),  (.V, 0.50), (.I64, 0.05)]
    case .vi:
      return [                          (.IV, 0.13),  (.ii, 0.41), (.viio6, 0.06),  (.V, 0.28), (.I6, 0.12) ]
    case .IV:
      return [(.I, 0.35),                             (.ii, 0.16), (.viio6, 0.10),  (.V, 0.40), (.IV6, 0.10)]
    case .ii:
      return [            (.vi, 0.05),                             (.viio6, 0.20),  (.V, 0.70), (.I64, 0.05)]
    case .viio6:
      return [(.I, 0.85), (.vi, 0.02),  (.IV, 0.03),                                (.V, 0.10)]
    case .V:
      return [(.I, 0.88), (.vi, 0.05),  (.IV6, 0.05), (.ii, 0.01)]
    case .V6:
      return [                                                                      (.V, 0.8),  (.I6, 0.2)  ]
    case .I6:
      return [(.I, 0.50), (.vi,0.07/2), (.IV, 0.11),  (.ii, 0.07), (.viio6, 0.025), (.V, 0.25)              ]
    case .IV6:
      return [(.I, 0.17),               (.IV, 0.65),  (.ii, 0.08), (.viio6, 0.05),  (.V, 0.4/2)             ]
    case .ii6:
      return [                                        (.ii, 0.10), (.viio6, 0.10),  (.V6, 0.8)              ]
    case .I64:
      return [                                                                      (.V, 1.0)               ]
    case .iii:
      return [                                                                      (.V, 0.5),  (.I6, 0.5)  ]
    case .iii6:
      return [                                                                      (.V, 0.5),  (.I64, 0.5) ]
    case .vi6:
      return [                                                                      (.V, 0.5),  (.I64, 0.5) ]
    }
  }

  /// Weighted random draw using exponential variates.
  static func weightedDraw<A>(items: [(A, CoreFloat)]) -> A? {
    func exp2<B>(_ item: (B, CoreFloat)) -> (B, CoreFloat) {
      (item.0, -1.0 * log(CoreFloat.random(in: 0...1)) / item.1)
    }
    return items.map({ exp2($0) }).min(by: { $0.1 < $1.1 })?.0
  }
}

// MARK: - MarkovChordIndexIterator

/// Emitter iterator that outputs 0-based chord indices using the Tymoczko
/// Baroque/Classical major Markov transition table.
/// The index corresponds to the chord's position in `MarkovChordIndexIterator.chordOrder`,
/// which must match the intervalMaterial ordering in the pattern JSON.
struct MarkovChordIndexIterator: Sequence, IteratorProtocol {
  private var currentChord: TymoczkoChords713 = .I
  private var neverCalled = true

  /// Fixed ordering of chords → intervalMaterial index (0-based).
  static let chordOrder: [TymoczkoChords713] = [
    .I, .vi, .IV, .ii, .V, .iii,
    .I6, .IV6, .ii6, .V6, .iii6, .vi6, .viio6, .I64
  ]
  private static let chordToIndex: [TymoczkoChords713: Int] = {
    Dictionary(uniqueKeysWithValues: chordOrder.enumerated().map { ($1, $0) })
  }()

  mutating func next() -> Int? {
    let candidates = TymoczkoChords713.stateTransitionsBaroqueClassicalMajor(currentChord)
    var nextChord = TymoczkoChords713.weightedDraw(items: candidates)!
    if neverCalled { neverCalled = false; nextChord = .I }
    currentChord = nextChord
    return Self.chordToIndex[nextChord]
  }
}

// MARK: - Midi1700sChordGenerator

// [MidiNote]
struct Midi1700sChordGenerator: Sequence, IteratorProtocol {
  // two pieces of data for the "key", e.g. "E minor"
  var scaleGenerator: any IteratorProtocol<Scale>
  var rootNoteGenerator: any IteratorProtocol<NoteClass>
  var currentChord: TymoczkoChords713 = .I
  var neverCalled = true

  mutating func next() -> [MidiNote]? {
    // the key
    let scaleRootNote = rootNoteGenerator.next()
    let scale = scaleGenerator.next()
    let candidates = TymoczkoChords713.stateTransitionsBaroqueClassicalMajor(currentChord)
    var nextChord = TymoczkoChords713.weightedDraw(items: candidates)!
    if neverCalled {
      neverCalled = false
      nextChord = .I
    }
    let chordDegrees = nextChord.scaleDegrees

    print("Gonna play \(nextChord)")

    // notes
    var midiNotes = [MidiNote]()
    for i in chordDegrees.indices {
      let chordDegree = chordDegrees[i]
      for octave in 0..<6 {
        if CoreFloat.random(in: 0...2) > 1 || (i == 0 && octave < 2) {
          let scaleRootNote = Note(scaleRootNote!.letter, accidental: scaleRootNote!.accidental, octave: octave)
          let chordDegreeAboveRoot = scale?.intervals[chordDegree-1]
          midiNotes.append(
            MidiNote(
              note: MidiValue(scaleRootNote.shiftUp(chordDegreeAboveRoot!)!.noteNumber),
              velocity: 127
            )
          )
        }
      }
    }

    self.currentChord = nextChord
    print("with notes: \(midiNotes)")
    return midiNotes
  }
}

// generate an exact MidiValue
struct MidiPitchGenerator: Sequence, IteratorProtocol {
  var scaleGenerator: any IteratorProtocol<Scale>
  var degreeGenerator: any IteratorProtocol<Int>
  var rootNoteGenerator: any IteratorProtocol<NoteClass>
  var octaveGenerator: any IteratorProtocol<Int>
  
  mutating func next() -> MidiValue? {
    // a scale is a collection of intervals
    let scale = scaleGenerator.next()!
    // a degree is a position within the scale
    let degree = degreeGenerator.next()!
    // from these two we can get a specific interval
    let interval = scale.intervals[degree]
    
    let root = rootNoteGenerator.next()!
    let octave = octaveGenerator.next()!
    // knowing the root class and octave gives us the root note of this scale
    let note = Note(root.letter, accidental: root.accidental, octave: octave)
    return MidiValue(note.shiftUp(interval)!.noteNumber)
  }
}

// when velocity is not meaningful
struct MidiPitchAsChordGenerator: Sequence, IteratorProtocol {
  var pitchGenerator: MidiPitchGenerator
  mutating func next() -> [MidiNote]? {
    guard let pitch = pitchGenerator.next() else { return nil }
    return [MidiNote(note: pitch, velocity: 127)]
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

// MARK: - HierarchyChordGenerator

/// Generates [MidiNote] from the shared hierarchy's current voiced chord.
/// The octave for the chord's bass note comes from the octaveEmitter.
struct HierarchyChordGenerator: Sequence, IteratorProtocol {
  let hierarchy: PitchHierarchy
  let voicing: VoicingStyle
  var octaveEmitter: any IteratorProtocol<Int>

  mutating func next() -> [MidiNote]? {
    guard let octave = octaveEmitter.next() else { return nil }
    let midis = hierarchy.voicedMidi(voicing: voicing, baseOctave: octave)
    guard !midis.isEmpty else { return nil }
    return midis.map { MidiNote(note: MidiValue($0), velocity: 127) }
  }
}

// MARK: - HierarchyMelodyGenerator

/// Generates single-note melodies by resolving degrees through the shared hierarchy.
/// The `level` parameter controls whether resolution uses the chord layer or scale layer:
///   - .scale: degreeEmitter emits scale degree values directly (supports large ranges with
///             octave wrapping, e.g. using a fragment-pool emitter over a chromatic scale).
///   - .chord: degreeEmitter emits chord-tone indices into the hierarchy's voicedDegrees.
struct HierarchyMelodyGenerator: Sequence, IteratorProtocol {
  let hierarchy: PitchHierarchy
  let level: HierarchyLevel
  var degreeEmitter: any IteratorProtocol<Int>
  var octaveEmitter: any IteratorProtocol<Int>

  mutating func next() -> [MidiNote]? {
    guard let degree = degreeEmitter.next() else { return nil }
    guard let octave = octaveEmitter.next() else { return nil }
    let note = MelodyNote(chordToneIndex: degree, perturbation: .none)
    guard let midi = hierarchy.resolve(note, at: level, octave: octave) else { return nil }
    return [MidiNote(note: MidiValue(midi), velocity: 127)]
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
