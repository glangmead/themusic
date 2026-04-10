//
//  TakesStoreTests.swift
//  OrbitalTests
//

import Testing
import Foundation
@testable import Orbital

@Suite("TakesStore", .serialized)
@MainActor
struct TakesStoreTests {
  /// Build a store backed by a fresh temp directory so tests don't see each
  /// other's data and don't pollute the real Documents folder.
  private func makeStore() -> (TakesStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "TakesStoreTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = TakesStore(documentsURL: dir)
    return (store, dir)
  }

  @Test("recordStart appends a new entry")
  func recordStartAppends() {
    let (store, _) = makeStore()
    let id = store.recordStart(songId: "score/foo.json", seed: "GH4K2M9P3A")
    #expect(store.ledger.entries.count == 1)
    let entry = store.ledger.entries[0]
    #expect(entry.id == id)
    #expect(entry.songId == "score/foo.json")
    #expect(entry.seed == "GH4K2M9P3A")
    #expect(entry.playedSeconds == 0)
    #expect(entry.favorite == false)
    #expect(entry.label == nil)
  }

  @Test("recordStop updates playedSeconds")
  func recordStopUpdates() {
    let (store, _) = makeStore()
    let id = store.recordStart(songId: "score/a.json", seed: "0000000001")
    store.recordStop(id: id, playedSeconds: 123.45)
    #expect(store.ledger.entries[0].playedSeconds == 123.45)
  }

  @Test("setFavorite toggles flag")
  func favoriteToggles() {
    let (store, _) = makeStore()
    let id = store.recordStart(songId: "score/a.json", seed: "0000000001")
    store.setFavorite(id: id, true)
    #expect(store.ledger.entries[0].favorite == true)
    store.setFavorite(id: id, false)
    #expect(store.ledger.entries[0].favorite == false)
  }

  @Test("delete removes by id")
  func deleteRemoves() {
    let (store, _) = makeStore()
    let id1 = store.recordStart(songId: "score/a.json", seed: "0000000001")
    _ = store.recordStart(songId: "score/a.json", seed: "0000000002")
    store.delete(id: id1)
    #expect(store.ledger.entries.count == 1)
    #expect(store.ledger.entries[0].seed == "0000000002")
  }

  @Test("entries(for:) filters and sorts newest first")
  func filterAndSort() async {
    let (store, _) = makeStore()
    _ = store.recordStart(songId: "score/a.json", seed: "0000000001")
    try? await Task.sleep(for: .milliseconds(10))
    _ = store.recordStart(songId: "score/b.json", seed: "0000000002")
    try? await Task.sleep(for: .milliseconds(10))
    _ = store.recordStart(songId: "score/a.json", seed: "0000000003")

    let aEntries = store.entries(for: "score/a.json")
    #expect(aEntries.count == 2)
    #expect(aEntries[0].seed == "0000000003")  // newest first
    #expect(aEntries[1].seed == "0000000001")

    let bEntries = store.entries(for: "score/b.json")
    #expect(bEntries.count == 1)
    #expect(bEntries[0].seed == "0000000002")
  }

  @Test("Old non-favorite entries are pruned on next recordStart")
  func retentionPrunesOldEntries() {
    let (store, _) = makeStore()
    // Inject an entry directly into the ledger with an old timestamp.
    let oldEntry = TakeEntry(
      id: UUID(),
      songId: "score/a.json",
      seed: "OLDOLDOLDX",
      startedAt: Date().addingTimeInterval(-60 * 60 * 24 * 200),  // 200 days ago
      playedSeconds: 0,
      favorite: false,
      label: nil,
      appVersion: "0.1.0"
    )
    store.ledger.entries.append(oldEntry)
    #expect(store.ledger.entries.count == 1)

    // Trigger prune.
    _ = store.recordStart(songId: "score/a.json", seed: "0000000001")

    // Old non-favorite is gone, new entry remains.
    #expect(store.ledger.entries.count == 1)
    #expect(store.ledger.entries[0].seed == "0000000001")
  }

  @Test("Old favorite entries survive prune")
  func favoritesSurvivePrune() {
    let (store, _) = makeStore()
    let oldFav = TakeEntry(
      id: UUID(),
      songId: "score/a.json",
      seed: "OLDFAVXXXX",
      startedAt: Date().addingTimeInterval(-60 * 60 * 24 * 200),
      playedSeconds: 0,
      favorite: true,
      label: nil,
      appVersion: "0.1.0"
    )
    store.ledger.entries.append(oldFav)

    _ = store.recordStart(songId: "score/a.json", seed: "0000000001")

    #expect(store.ledger.entries.count == 2)
    #expect(store.ledger.entries.contains { $0.seed == "OLDFAVXXXX" })
  }

  @Test("flushNow persists to disk; new store reads back the same ledger")
  func roundTripDisk() {
    let dir = FileManager.default.temporaryDirectory.appending(path: "TakesStoreTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store1 = TakesStore(documentsURL: dir)
    let id = store1.recordStart(songId: "score/foo.json", seed: "ABCDEFGHJK")
    store1.recordStop(id: id, playedSeconds: 42.5)
    store1.setFavorite(id: id, true)
    store1.flushNow()

    let store2 = TakesStore(documentsURL: dir)
    #expect(store2.ledger.entries.count == 1)
    let entry = store2.ledger.entries[0]
    #expect(entry.id == id)
    #expect(entry.seed == "ABCDEFGHJK")
    #expect(entry.playedSeconds == 42.5)
    #expect(entry.favorite == true)
  }
}
