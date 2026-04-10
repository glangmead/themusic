//
//  MIDIDownloadLedger.swift
//  Orbital
//
//  Tracks which MIDI files have been downloaded, mapping source URLs
//  to local file paths within Documents/midi_downloads/.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.langmead.Orbital", category: "MIDIDownloadLedger")

struct MIDILedgerEntry: Codable, Sendable {
  let sourceUrl: String
  let composerSlug: String
  let localPath: String
  let downloadedAt: Date

  enum CodingKeys: String, CodingKey {
    case sourceUrl = "source_url"
    case composerSlug = "composer_slug"
    case localPath = "local_path"
    case downloadedAt = "downloaded_at"
  }
}

@MainActor @Observable
final class MIDIDownloadLedger {
  /// The base directory for all MIDI downloads (Documents/midi_downloads/).
  let baseDirectory: URL

  /// Maps source URL string to its ledger entry.
  private(set) var entries: [String: MIDILedgerEntry] = [:]

  /// True while `load()` is reading the ledger file from disk (and, for iCloud,
  /// possibly downloading it). Drives tab-level loading indicators.
  private(set) var isLoading = false

  private var fileURL: URL {
    baseDirectory.appending(path: "ledger.json")
  }

  init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
  }

  // MARK: - Queries

  func isDownloaded(_ sourceUrl: String) -> Bool {
    entries[sourceUrl] != nil
  }

  /// Returns the absolute file URL for a downloaded MIDI, or nil if not downloaded.
  func localURL(for sourceUrl: String) -> URL? {
    guard let entry = entries[sourceUrl] else { return nil }
    return baseDirectory.appending(path: entry.localPath)
  }

  /// Number of downloaded files for a given composer.
  func downloadCount(for composerSlug: String) -> Int {
    entries.values.filter { $0.composerSlug == composerSlug }.count
  }

  // MARK: - Mutations

  func record(sourceUrl: String, composerSlug: String, localPath: String) {
    let entry = MIDILedgerEntry(
      sourceUrl: sourceUrl,
      composerSlug: composerSlug,
      localPath: localPath,
      downloadedAt: .now
    )
    entries[sourceUrl] = entry
    save()
  }

  func remove(sourceUrl: String) {
    guard let entry = entries.removeValue(forKey: sourceUrl) else { return }
    let fileURL = baseDirectory.appending(path: entry.localPath)
    try? FileManager.default.removeItem(at: fileURL)
    save()
  }

  // MARK: - Persistence

  /// Loads the ledger off the main thread using `NSFileCoordinator` so that
  /// iCloud can bring the file local before we read it. Safe to call on the
  /// main actor — the blocking IO runs in a `nonisolated` helper.
  func load() async {
    let url = fileURL
    isLoading = true
    defer { isLoading = false }
    let loaded = await Self.readLedgerFile(at: url)
    guard let loaded else { return }
    entries = Dictionary(uniqueKeysWithValues: loaded.map { ($0.sourceUrl, $0) })
    logger.info("Loaded \(loaded.count) ledger entries")
  }

  /// Synchronous worker invoked from a `nonisolated` async context, which
  /// guarantees it runs on the cooperative pool rather than the main actor.
  nonisolated private static func readLedgerFile(at url: URL) async -> [MIDILedgerEntry]? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path(percentEncoded: false)) else {
      logger.info("No ledger file found, starting fresh")
      return nil
    }

    // Hint iCloud to bring the file local before we coordinate a read.
    // No-op (and harmless error) for non-ubiquitous files.
    try? fm.startDownloadingUbiquitousItem(at: url)

    let coordinator = NSFileCoordinator()
    var coordError: NSError?
    var result: [MIDILedgerEntry]?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
      do {
        let data = try Data(contentsOf: coordinatedURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        result = try decoder.decode([MIDILedgerEntry].self, from: data)
      } catch {
        logger.error("Failed to read/decode ledger: \(error.localizedDescription)")
      }
    }
    if let coordError {
      logger.error("File coordination failed: \(coordError.localizedDescription)")
    }
    return result
  }

  private func save() {
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let entryList = entries.values.sorted { $0.downloadedAt < $1.downloadedAt }
      let data = try encoder.encode(entryList)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      logger.error("Failed to save ledger: \(error.localizedDescription)")
    }
  }
}
