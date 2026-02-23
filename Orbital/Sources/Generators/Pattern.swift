//
//  Player.swift
//  Orbital
//
//  Created by Greg Langmead on 1/21/26.
//

import Foundation
import Tonic
import AVFAudio

// an arrow that has an additional value and a closure that can make use of it when called with a time
final class EventUsingArrow: Arrow11 {
  var event: MusicEvent? = nil
  var ofEvent: (_ event: MusicEvent, _ t: CoreFloat) -> CoreFloat
  
  init(ofEvent: @escaping (_: MusicEvent, _: CoreFloat) -> CoreFloat) {
    self.ofEvent = ofEvent
    super.init()
  }
  
  override func of(_ t: CoreFloat) -> CoreFloat {
    ofEvent(event!, innerArr?.of(t) ?? 0)
  }
}

// a musical utterance to play at one point in time, a set of simultaneous noteOns
struct MusicEvent {
  let noteHandler: NoteHandler
  let notes: [MidiNote]
  let sustain: CoreFloat // time between noteOn and noteOff in seconds
  let gap: CoreFloat // time reserved for this event, before next event is played
  let modulators: [String: Arrow11]
  let timeOrigin: Double
  let clock: any Clock<Duration>
  
  init(
    noteHandler: NoteHandler,
    notes: [MidiNote],
    sustain: CoreFloat,
    gap: CoreFloat,
    modulators: [String: Arrow11],
    timeOrigin: Double,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.noteHandler = noteHandler
    self.notes = notes
    self.sustain = sustain
    self.gap = gap
    self.modulators = modulators
    self.timeOrigin = timeOrigin
    self.clock = clock
  }
  
  mutating func play() async throws {
    let now = CoreFloat(Date.now.timeIntervalSince1970 - timeOrigin)

    // Set up EventUsingArrow references
    for (_, modulatingArrow) in modulators {
      if let eventUsingArrow = modulatingArrow as? EventUsingArrow {
        eventUsingArrow.event = self
      } else if let handleWH = modulatingArrow as? ArrowWithHandles {
        for eventUsingArrowList in handleWH.namedEventUsing.values {
          for eventUsingArrow in eventUsingArrowList {
            eventUsingArrow.event = self
          }
        }
      }
    }

    // Apply modulators per-voice when possible, otherwise globally
    if let spatialPreset = noteHandler as? SpatialPreset, !modulators.isEmpty {
      spatialPreset.notesOnWithModulators(notes, modulators: modulators, now: now)
    } else {
      // Global modulation fallback (single-voice presets)
      if let handles = noteHandler.handles {
        for (key, modulatingArrow) in modulators {
          if let arrowConsts = handles.namedConsts[key] {
            let value = modulatingArrow.of(now)
            for arrowConst in arrowConsts {
              arrowConst.val = value
            }
          }
        }
      }
      noteHandler.notesOn(notes)
    }
    do {
      try await clock.sleep(for: .seconds(TimeInterval(sustain)))
    } catch {
      
    }
    noteHandler.notesOff(notes)
  }
  
  func cancel() {
    noteHandler.notesOff(notes)
  }
}

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

struct Midi1700sChordGenerator: Sequence, IteratorProtocol {
  // two pieces of data for the "key", e.g. "E minor"
  var scaleGenerator: any IteratorProtocol<Scale>
  var rootNoteGenerator: any IteratorProtocol<NoteClass>
  var currentChord: TymoczkoChords713 = .I
  var neverCalled = true
  
  enum TymoczkoChords713 {
    case I6
    case IV6
    case ii6
    case viio6
    case V6
    case I
    case vi
    case IV
    case ii
    case I64
    case V
    case iii
    case iii6
    case vi6
  }
  
  func scaleDegrees(chord: TymoczkoChords713) -> [Int] {
    switch chord {
    case .I6:    [3, 5, 1]
    case .IV6:   [6, 1, 4]
    case .ii6:   [4, 6, 2]
    case .viio6: [2, 4, 7]
    case .V6:    [7, 2, 5]
    case .I:     [1, 3, 5]
    case .vi:    [6, 1, 3]
    case .IV:    [4, 6, 1]
    case .ii:    [2, 4, 6]
    case .I64:   [5, 1, 3]
    case .V:     [5, 7, 2]
    case .iii:   [3, 5, 7]
    case .iii6:  [5, 7, 3]
    case .vi6:   [1, 3, 6]
    }
  }
  
  // probabilistic state transitions according to Tymoczko diagram 7.1.3 of Tonality
  var stateTransitionsBaroqueClassicalMajor: (TymoczkoChords713) -> [(TymoczkoChords713, CoreFloat)] = { start in
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
  
  func minBy2<A, B: Comparable>(_ items: [(A, B)]) -> A? {
    items.min(by: {t1, t2 in t1.1 < t2.1})?.0
  }
  
  func exp2<A>(_ item: (A, CoreFloat)) -> (A, CoreFloat) {
    (item.0, -1.0 * log(CoreFloat.random(in: 0...1)) / item.1)
  }
  
  func weightedDraw<A>(items: [(A, CoreFloat)]) -> A? {
    minBy2(items.map({exp2($0)}))
  }
  
  mutating func next() -> [MidiNote]? {
    // the key
    let scaleRootNote = rootNoteGenerator.next()
    let scale = scaleGenerator.next()
    let candidates = stateTransitionsBaroqueClassicalMajor(currentChord)
    var nextChord = weightedDraw(items: candidates)!
    if neverCalled {
      neverCalled = false
      nextChord = .I
    }
    let chordDegrees = scaleDegrees(chord: nextChord)
    
    print("Gonna play \(nextChord)")
    
    // notes
    var midiNotes = [MidiNote]()
    for i in chordDegrees.indices {
      let chordDegree = chordDegrees[i]
      //print("adding chord degree \(chordDegree)")
      for octave in 0..<6 {
        if CoreFloat.random(in: 0...2) > 1 || (i == 0 && octave < 2) {
          let scaleRootNote = Note(scaleRootNote!.letter, accidental: scaleRootNote!.accidental, octave: octave)
          //print("scale root note in octave \(octave): \(scaleRootNote.noteNumber)")
          let chordDegreeAboveRoot = scale?.intervals[chordDegree-1]
          //print("shifting scale root note by \(chordDegreeAboveRoot!)")
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

// sample notes from a scale
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
  case gaussian(avg: CoreFloat, stdev: CoreFloat)
}

struct FloatSampler: Sequence, IteratorProtocol {
  typealias Element = CoreFloat
  let distribution: ProbabilityDistribution
  let min: CoreFloat
  let max: CoreFloat
  init(min: CoreFloat, max: CoreFloat, dist: ProbabilityDistribution = .uniform) {
    self.distribution = dist
    self.min = min
    self.max = max
  }
  
  func next() -> CoreFloat? {
    CoreFloat.random(in: min...max)
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

// MARK: - IntSampler

/// Generates random integers in a range. Stateless — safe with any update mode.
struct IntSampler: Sequence, IteratorProtocol {
  let min: Int
  let max: Int

  func next() -> Int? {
    Int.random(in: min...max)
  }
}

// MARK: - ExponentialFloatSampler

/// Exponential distribution sampling mapped to [min, max].
/// λ is chosen so ~95% of raw samples fall within the range; values beyond max are clamped.
/// Heavily biased toward min.
struct ExponentialFloatSampler: Sequence, IteratorProtocol {
  let min: CoreFloat
  let max: CoreFloat
  private let lambda: CoreFloat

  init(min: CoreFloat, max: CoreFloat) {
    self.min = Swift.min(min, max)
    self.max = Swift.max(min, max)
    let range = self.max - self.min
    self.lambda = range > 0 ? -log(0.05) / range : 1
  }

  func next() -> CoreFloat? {
    let u = CoreFloat.random(in: CoreFloat.ulpOfOne...1)
    let raw = -log(u) / lambda
    let result = clamp(min + raw, min: min, max: max)
    return result
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

// MARK: - TableNoteGenerator

/// Generates [MidiNote] from table-based note material.
/// On each next(), picks an interval entry (single degree or chord),
/// resolves each degree against the current scale/root/octave to produce MIDI notes.
struct TableNoteGenerator: Sequence, IteratorProtocol {
  let intervalMaterial: [[Int]]
  var intervalPicker: any IteratorProtocol<Int>
  var scaleEmitter: any IteratorProtocol<Scale>
  var rootEmitter: any IteratorProtocol<NoteClass>
  var octaveEmitter: any IteratorProtocol<Int>

  mutating func next() -> [MidiNote]? {
    guard !intervalMaterial.isEmpty else { return nil }
    guard let idx = intervalPicker.next() else { return nil }
    let clamped = Swift.max(0, Swift.min(idx, intervalMaterial.count - 1))
    let degrees = intervalMaterial[clamped]

    guard let scale = scaleEmitter.next() else { return nil }
    guard let root = rootEmitter.next() else { return nil }
    guard let octave = octaveEmitter.next() else { return nil }

    let rootNote = Note(root.letter, accidental: root.accidental, octave: octave)

    var notes: [MidiNote] = []
    for degree in degrees {
      let clampedDegree = Swift.max(0, Swift.min(degree, scale.intervals.count - 1))
      let interval = scale.intervals[clampedDegree]
      if let shifted = rootNote.shiftUp(interval) {
        notes.append(MidiNote(note: MidiValue(shifted.noteNumber), velocity: 127))
      }
    }
    return notes.isEmpty ? nil : notes
  }
}

/// A multi-track generative music pattern. Each track has its own preset,
/// note generator, timing, and modulators, and runs concurrently.
actor MusicPattern {
  /// State for a single track within the pattern.
  struct Track {
    let spatialPreset: SpatialPreset
    let modulators: [String: Arrow11]
    var notes: any IteratorProtocol<[MidiNote]>
    var sustains: any IteratorProtocol<CoreFloat>
    var gaps: any IteratorProtocol<CoreFloat>
    let name: String
  }

  private var tracks: [Track]
  private let clock: any Clock<Duration>
  var timeOrigin: Double
  var isPaused: Bool = false

  init(tracks: [Track], clock: any Clock<Duration> = ContinuousClock()) {
    self.tracks = tracks
    self.clock = clock
    self.timeOrigin = Date.now.timeIntervalSince1970
  }

  func setPaused(_ paused: Bool) {
    self.isPaused = paused
    if paused {
      for track in tracks {
        track.spatialPreset.allNotesOff()
      }
    }
  }

  /// Generate the next event for a specific track.
  private func nextEvent(trackIndex: Int) -> MusicEvent? {
    guard trackIndex < tracks.count else { return nil }
    guard let notes = tracks[trackIndex].notes.next() else { return nil }
    guard let sustain = tracks[trackIndex].sustains.next() else { return nil }
    guard let gap = tracks[trackIndex].gaps.next() else { return nil }

    return MusicEvent(
      noteHandler: tracks[trackIndex].spatialPreset,
      notes: notes,
      sustain: sustain,
      gap: gap,
      modulators: tracks[trackIndex].modulators,
      timeOrigin: timeOrigin,
      clock: clock
    )
  }

  /// Play all tracks concurrently. Each track runs its own event loop.
  /// Cancelling the calling task propagates to all track tasks.
  func play() async {
    await withTaskGroup(of: Void.self) { group in
      for trackIndex in tracks.indices {
        group.addTask { [self] in
          await self.playTrack(trackIndex)
        }
      }
    }
  }

  /// Event loop for a single track.
  private func playTrack(_ trackIndex: Int) async {
    await withTaskGroup(of: Void.self) { group in
      while !Task.isCancelled {
        // Wait while paused, checking cancellation periodically
        while isPaused {
          guard !Task.isCancelled else { return }
          do {
            try await clock.sleep(for: .milliseconds(50))
          } catch {
            return
          }
        }
        guard !Task.isCancelled else { return }
        guard var event = nextEvent(trackIndex: trackIndex) else { return }
        group.addTask {
          try? await event.play()
        }
        do {
          try await clock.sleep(for: .seconds(TimeInterval(event.gap)))
        } catch {
          return
        }
      }
    }
  }

  /// Detach audio nodes from all tracks.
  func detachNodes() {
    for track in tracks {
      track.spatialPreset.detachNodes()
    }
  }

  /// Full teardown: detach nodes and destroy Preset objects.
  func cleanup() {
    for track in tracks {
      track.spatialPreset.cleanup()
    }
  }
}

