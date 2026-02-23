//
//  MusicEvent.swift
//  Orbital
//
//  Extracted from Pattern.swift
//

import Foundation

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
