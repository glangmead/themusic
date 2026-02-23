//
//  MusicPattern.swift
//  Orbital
//
//  Extracted from Pattern.swift
//

import Foundation

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
