//
//  TakesStore.swift
//  Orbital
//
//  Owns the takes registry. Persists to a JSON file in the user's documents
//  directory (which may be iCloud-synced). All mutating operations run on the
//  main actor; disk writes are debounced and run on a detached Task so the UI
//  thread never blocks on file I/O.
//
//  Retention: any non-favorite entry older than 6 months is pruned at the
//  start of every recordStart() call. Favorites survive forever.
//

import Foundation

@MainActor @Observable
final class TakesStore {
  /// In-memory ledger; observers see updates as plays start/stop and as
  /// favorites change. Direct mutation is allowed (and used by tests to
  /// inject old timestamps for retention testing); production code should
  /// go through the typed API methods below.
  var ledger: TakesLedger = TakesLedger(entries: [])

  private let storageURL: URL
  private var pendingWriteTask: Task<Void, Never>?

  /// Anything older than this and not favorited is pruned on next write.
  private static let retentionInterval: TimeInterval = 60 * 60 * 24 * 30 * 6  // ~6 months

  /// Coalesce writes within this window so a flurry of recordStop / favorite
  /// taps only triggers one disk write.
  private static let writeDebounce: Duration = .seconds(1)

  init(documentsURL: URL) {
    self.storageURL = documentsURL.appending(path: "takes.json")
    load()
  }

  private func load() {
    guard let data = try? Data(contentsOf: storageURL) else { return }
    if let decoded = try? JSONDecoder().decode(TakesLedger.self, from: data) {
      ledger = decoded
    }
  }

  /// Append a fresh entry for a play that just started. Returns the entry's
  /// UUID so the caller can later call `recordStop`/`updatePlayedSeconds` on
  /// it. Triggers retention pruning.
  @discardableResult
  func recordStart(songId: String, seed: String) -> UUID {
    pruneOldEntries()
    let entry = TakeEntry(
      id: UUID(),
      songId: songId,
      seed: seed,
      startedAt: Date(),
      playedSeconds: 0,
      favorite: false,
      label: nil,
      appVersion: TakeEntry.currentAppVersion
    )
    ledger.entries.append(entry)
    scheduleWrite()
    return entry.id
  }

  /// Update the played-seconds counter on an existing entry. Used both for
  /// final stop (recordStop) and for periodic pause-flushes.
  func updatePlayedSeconds(id: UUID, _ value: Double) {
    guard let idx = ledger.entries.firstIndex(where: { $0.id == id }) else { return }
    ledger.entries[idx].playedSeconds = value
    scheduleWrite()
  }

  /// Convenience alias for stop, semantically distinct from a mid-play update.
  func recordStop(id: UUID, playedSeconds: Double) {
    updatePlayedSeconds(id: id, playedSeconds)
  }

  /// Toggle favorite status on an entry.
  func setFavorite(id: UUID, _ value: Bool) {
    guard let idx = ledger.entries.firstIndex(where: { $0.id == id }) else { return }
    ledger.entries[idx].favorite = value
    scheduleWrite()
  }

  /// Delete an entry by id (regardless of favorite status).
  func delete(id: UUID) {
    ledger.entries.removeAll { $0.id == id }
    scheduleWrite()
  }

  /// Per-song view, sorted newest first.
  func entries(for songId: String) -> [TakeEntry] {
    ledger.entries
      .filter { $0.songId == songId }
      .sorted { $0.startedAt > $1.startedAt }
  }

  private func pruneOldEntries() {
    let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
    ledger.entries.removeAll { !$0.favorite && $0.startedAt < cutoff }
  }

  private func scheduleWrite() {
    pendingWriteTask?.cancel()
    let snapshot = ledger
    let url = storageURL
    // Detached so the debounce sleep AND the disk I/O run off the main actor.
    // A plain `Task { ... }` inside this @MainActor class would inherit main
    // actor isolation and serialize disk writes onto the UI thread.
    pendingWriteTask = Task.detached {
      try? await Task.sleep(for: Self.writeDebounce)
      guard !Task.isCancelled else { return }
      Self.writeToDisk(ledger: snapshot, url: url)
    }
  }

  /// Force a synchronous flush of the latest snapshot. Called from app
  /// background notifications so process kill doesn't lose recent edits.
  func flushNow() {
    pendingWriteTask?.cancel()
    pendingWriteTask = nil
    Self.writeToDisk(ledger: ledger, url: storageURL)
  }

  nonisolated private static func writeToDisk(ledger: TakesLedger, url: URL) {
    do {
      let data = try JSONEncoder().encode(ledger)
      try data.write(to: url, options: .atomic)
    } catch {
      // Non-fatal: the ledger is also kept in memory and will retry on next change.
      print("[TakesStore] write failed: \(error.localizedDescription)")
    }
  }
}
