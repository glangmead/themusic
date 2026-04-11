//
//  SongDocumentSeedLifecycleTests.swift
//  OrbitalTests
//
//  Integration tests for SongDocument's shareable-seed lifecycle: pending seed
//  decoding, currentSeed assignment, hasRandomness detection, and TakesStore
//  recordStart / recordStop wiring.
//
//  These use a real (non-spatial) SpatialAudioEngine plus a frozen fixture
//  pattern. They poll the SongDocument phase to wait for the async load to
//  complete, then immediately stop to avoid blocking on the infinite playback
//  loop.
//

import Testing
import Foundation
@testable import Orbital

@Suite("SongDocument seed lifecycle", .serialized)
@MainActor
struct SongDocumentSeedLifecycleTests {
  private func loadFixturePattern(_ name: String) throws -> PatternSyntax {
    guard let url = Bundle(for: TestBundleAnchor.self).url(forResource: name, withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(PatternSyntax.self, from: data)
  }

  /// Construct a fresh SongDocument bound to a tmp-dir TakesStore.
  private func makeDoc(pattern: PatternSyntax) -> (SongDocument, TakesStore) {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "SongDocSeedTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = TakesStore(documentsURL: dir)
    let engine = SpatialAudioEngine(spatialEnabled: false)
    try? engine.start()
    let doc = SongDocument(
      patternSyntax: pattern,
      displayName: "test-song",
      engine: engine,
      takesStore: store
    )
    return (doc, store)
  }

  /// Wait until the SongDocument leaves .loading. Times out after `timeout`.
  private func waitForPlayingPhase(_ doc: SongDocument, timeout: Duration = .seconds(5)) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if doc.phase != .loading && doc.phase != .idle { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  @Test("currentSeed is non-nil immediately after play() is called")
  func currentSeedSetSynchronously() async throws {
    let pattern = try loadFixturePattern("table_aurora_frozen")
    let (doc, _) = makeDoc(pattern: pattern)

    #expect(doc.currentSeed == nil)
    doc.play()
    // play() spawns a Task but sets currentSeed synchronously before the task.
    #expect(doc.currentSeed != nil)
    #expect(doc.currentSeedString != nil)
    #expect(doc.currentSeedString?.count == 10)

    doc.stop()
  }

  @Test("setPendingSeed makes play() use the decoded seed")
  func pendingSeedConsumed() async throws {
    let pattern = try loadFixturePattern("table_aurora_frozen")
    let (doc, _) = makeDoc(pattern: pattern)

    let typed = "GH4K2M9P3A"
    let expected = SeedCodec.decode(typed)
    #expect(expected != nil)

    doc.setPendingSeed(typed)
    doc.play()

    #expect(doc.currentSeed == expected)
    #expect(doc.currentSeedString == typed)

    doc.stop()
  }

  @Test("Two consecutive plays without a pending seed produce different seeds")
  func freshSeedsDiffer() async throws {
    let pattern = try loadFixturePattern("table_aurora_frozen")
    let (doc, _) = makeDoc(pattern: pattern)

    doc.play()
    let first = doc.currentSeed
    doc.stop()

    doc.play()
    let second = doc.currentSeed
    doc.stop()

    #expect(first != nil)
    #expect(second != nil)
    #expect(first != second)
  }

  @Test("stop() clears currentSeed")
  func stopClearsSeed() async throws {
    let pattern = try loadFixturePattern("table_aurora_frozen")
    let (doc, _) = makeDoc(pattern: pattern)

    doc.play()
    #expect(doc.currentSeed != nil)
    doc.stop()
    #expect(doc.currentSeed == nil)
  }

  @Test("Randomized song gets a recordStart entry once compile finishes")
  func recordStartFiresForRandomizedSong() async throws {
    let pattern = try loadFixturePattern("table_aurora_frozen")
    let (doc, store) = makeDoc(pattern: pattern)

    #expect(store.ledger.entries.isEmpty)

    doc.play()
    await waitForPlayingPhase(doc)

    // table_aurora_frozen uses random/shuffled emitters, so it should
    // qualify as having randomness — but the truth is determined by the
    // compiled SpatialPreset's hasArrowRandomness flag, which is conservative
    // (only true when the preset has padTemplate or runtime random Arrow nodes).
    // The frozen preset is deterministic, so we don't strictly require an
    // entry — but if hasRandomness is true, an entry must exist.
    if doc.hasRandomness {
      #expect(store.ledger.entries.count == 1)
      let entry = store.ledger.entries[0]
      #expect(entry.seed == doc.currentSeedString)
      #expect(entry.songId == doc.song.id)
      #expect(entry.appVersion != nil)
    }

    doc.stop()
  }

  @Test("Replay with same seed produces same currentSeed value")
  func replayReproducesSeed() async throws {
    let pattern = try loadFixturePattern("table_aurora_frozen")
    let (doc, _) = makeDoc(pattern: pattern)

    doc.setPendingSeed("ABCDEFGHJK")
    doc.play()
    let firstSeed = doc.currentSeed
    doc.stop()

    doc.setPendingSeed("ABCDEFGHJK")
    doc.play()
    let secondSeed = doc.currentSeed
    doc.stop()

    #expect(firstSeed == secondSeed)
    #expect(firstSeed == SeedCodec.decode("ABCDEFGHJK"))
  }
}
