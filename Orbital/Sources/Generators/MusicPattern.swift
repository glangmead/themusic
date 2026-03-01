//
//  MusicPattern.swift
//  Orbital
//
//  Extracted from Pattern.swift
//

import Foundation

// MARK: - CompiledHierarchyOperation

/// The typed operation applied by a CompiledHierarchyModulator each time it fires.
enum CompiledHierarchyOperation {
  /// Transpose up by n steps at the given hierarchy level (n=0 is a no-op).
  case T(n: Int, level: HierarchyLevel)
  /// Transpose down by n steps at the given hierarchy level (n=0 is a no-op).
  case t(n: Int, level: HierarchyLevel)
  /// Apply n leading-tone transforms (n=0 is a no-op).
  case L(n: Int)
  /// Advance the Markov chord chain n times, applying the last result (n=0 is a no-op).
  case markovChord(n: Int, iterator: any IteratorProtocol<ChordInScale>)
}

// MARK: - CompiledHierarchyModulator

/// A compiled hierarchy modulator: fires on a timer and applies a typed operation to the shared hierarchy.
final class CompiledHierarchyModulator {
  let hierarchy: PitchHierarchy
  var operation: CompiledHierarchyOperation
  var intervalEmitter: any IteratorProtocol<CoreFloat>

  init(
    hierarchy: PitchHierarchy,
    operation: CompiledHierarchyOperation,
    intervalEmitter: any IteratorProtocol<CoreFloat>
  ) {
    self.hierarchy = hierarchy
    self.operation = operation
    self.intervalEmitter = intervalEmitter
  }
}

// MARK: - MusicPattern

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
    /// Emitter name -> shadow ArrowConst holding last emitted value (float-coerced).
    /// Empty for non-table compilation paths.
    let emitterShadows: [String: ArrowConst]
  }

  private var tracks: [Track]
  private let clock: any Clock<Duration>
  var timeOrigin: Double
  var isPaused: Bool = false

  /// Hierarchy modulators that fire on independent timers.
  private let hierarchyModulators: [CompiledHierarchyModulator]

  /// One annotation stream per track; UI subscribes to these.
  private(set) var annotationStreams: [AsyncStream<EventAnnotation>] = []
  private var annotationContinuations: [AsyncStream<EventAnnotation>.Continuation] = []

  // MARK: - Chord label stream

  /// Beat-indexed chord change events with human-readable labels.
  /// Empty for non-score patterns.
  private let chordLabelEvents: [(beat: Double, label: String)]
  private let chordLabelSecondsPerBeat: Double
  private let chordLabelTotalBeats: Double
  private let chordLabelLoop: Bool

  /// The most recently emitted chord label. Updated by playChordLabels() and
  /// read by playTrack() to populate EventAnnotation.chordSymbol.
  private(set) var currentChordLabel: String?

  /// Stream that yields a label string each time the harmony changes.
  /// Fires at beat-accurate absolute times, independent of note rhythm.
  private(set) var chordLabelStream: AsyncStream<String>
  private var chordLabelContinuation: AsyncStream<String>.Continuation?

  init(
    tracks: [Track],
    hierarchyModulators: [CompiledHierarchyModulator] = [],
    chordLabelEvents: [(beat: Double, label: String)] = [],
    secondsPerBeat: Double = 0,
    totalBeats: Double = 0,
    loop: Bool = false,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.tracks = tracks
    self.hierarchyModulators = hierarchyModulators
    self.clock = clock
    self.timeOrigin = Date.now.timeIntervalSince1970
    self.chordLabelEvents = chordLabelEvents
    self.chordLabelSecondsPerBeat = secondsPerBeat
    self.chordLabelTotalBeats = totalBeats
    self.chordLabelLoop = loop

    let (clStream, clContinuation) = AsyncStream<String>.makeStream()
    self.chordLabelStream = clStream
    self.chordLabelContinuation = clContinuation

    for _ in tracks.indices {
      let (stream, continuation) = AsyncStream<EventAnnotation>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      annotationStreams.append(stream)
      annotationContinuations.append(continuation)
    }
  }

  /// Accessor for the annotation streams. Called from MainActor before play() starts.
  func getAnnotationStreams() -> [AsyncStream<EventAnnotation>] {
    annotationStreams
  }

  /// Accessor for the chord label stream. Called from MainActor before play() starts.
  func getChordLabelStream() -> AsyncStream<String> {
    chordLabelStream
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
  /// Hierarchy modulators also run as concurrent tasks.
  /// Cancelling the calling task propagates to all child tasks.
  func play() async {
    timeOrigin = Date.now.timeIntervalSince1970
    await withTaskGroup(of: Void.self) { group in
      for trackIndex in tracks.indices {
        group.addTask { [self] in
          await self.playTrack(trackIndex)
        }
      }
      for mod in hierarchyModulators {
        group.addTask {
          await self.runHierarchyModulator(mod)
        }
      }
      // Chord label emission runs as a separate timer loop rather than being
      // interleaved with note events. This is necessary because chord changes
      // (from chordEvents) and note onsets (from tracks) are independent: a
      // chord can change at any beat even if no note fires at that exact moment.
      // The pre-compiled note arrays also have no beat information left in them
      // at runtime, so there is no way for playTrack() to know when a chord
      // boundary was crossed.
      if !chordLabelEvents.isEmpty {
        group.addTask { [self] in
          await self.playChordLabels()
        }
      }
    }
  }

  /// Timer loop that yields chord label strings at beat-accurate absolute times.
  private func playChordLabels() async {
    var beatOffset = 0.0
    repeat {
      for event in chordLabelEvents {
        let targetTime = timeOrigin + (beatOffset + event.beat) * chordLabelSecondsPerBeat
        let sleepSeconds = targetTime - Date.now.timeIntervalSince1970
        if sleepSeconds > 0 {
          do {
            try await clock.sleep(for: .seconds(sleepSeconds))
          } catch {
            return
          }
        }
        guard !Task.isCancelled else { return }
        currentChordLabel = event.label
        chordLabelContinuation?.yield(event.label)
      }
      beatOffset += chordLabelTotalBeats
    } while chordLabelLoop && !Task.isCancelled
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

        // Build and yield annotation for the UI event log
        if trackIndex < annotationContinuations.count {
          let track = tracks[trackIndex]
          var emitterValues: [String: CoreFloat] = [:]
          for (name, shadow) in track.emitterShadows {
            emitterValues[name] = shadow.val
          }
          let annotation = EventAnnotation(
            trackIndex: trackIndex,
            trackName: track.name,
            timestamp: Date.now.timeIntervalSince1970 - timeOrigin,
            chordSymbol: currentChordLabel,
            notes: event.notes,
            sustain: event.sustain,
            gap: event.gap,
            emitterValues: emitterValues
          )
          annotationContinuations[trackIndex].yield(annotation)
        }

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

  /// Timer loop for a hierarchy modulator: sleeps for the interval then applies the operation.
  private func runHierarchyModulator(_ mod: CompiledHierarchyModulator) async {
    while !Task.isCancelled {
      guard let interval = mod.intervalEmitter.next(), interval > 0 else { return }
      do {
        try await clock.sleep(for: .seconds(TimeInterval(interval)))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      switch mod.operation {
      case .T(let n, let level):
        mod.hierarchy.T(n, at: level)
      case .t(let n, let level):
        mod.hierarchy.t(n, at: level)
      case .L(let n):
        mod.hierarchy.L(n)
      case .markovChord(let n, var iter):
        // n=0 is a no-op; n=1 advances once; n>1 skips ahead by calling n times and keeping the last.
        guard n > 0 else { break }
        var last: ChordInScale?
        for _ in 0..<n { last = iter.next() }
        // Write the mutated iterator state back into the enum case.
        mod.operation = .markovChord(n: n, iterator: iter)
        if let chord = last { mod.hierarchy.chord = chord }
      }
    }
  }

  /// Signal all annotation streams and the chord label stream that playback has ended.
  private func finishAnnotations() {
    for continuation in annotationContinuations {
      continuation.finish()
    }
    chordLabelContinuation?.finish()
    chordLabelContinuation = nil
  }

  /// Detach audio nodes from all tracks.
  func detachNodes() {
    finishAnnotations()
    for track in tracks {
      track.spatialPreset.detachNodes()
    }
  }

  /// Full teardown: detach nodes and destroy Preset objects.
  func cleanup() {
    finishAnnotations()
    for track in tracks {
      track.spatialPreset.cleanup()
    }
  }
}
