//
//  MIDIDownloadManager.swift
//  Orbital
//
//  Handles downloading MIDI files from direct-download sources
//  (kern, mutopia, jsbach) and recording them in the ledger.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.langmead.Orbital", category: "MIDIDownloadManager")

@MainActor @Observable
final class MIDIDownloadManager {
  let ledger: MIDIDownloadLedger

  /// Tracks in-flight downloads by source URL.
  private(set) var activeDownloads: Set<String> = []

  init(ledger: MIDIDownloadLedger) {
    self.ledger = ledger
  }

  // MARK: - Download

  /// Downloads a MIDI file directly and records it in the ledger.
  /// Returns the local file URL on success.
  @discardableResult
  func download(url urlString: String, composerSlug: String) async throws -> URL {
    guard !ledger.isDownloaded(urlString) else {
      // Already downloaded — return existing path
      return ledger.localURL(for: urlString)!
    }

    guard let url = URL(string: urlString) else {
      throw DownloadError.invalidURL(urlString)
    }

    activeDownloads.insert(urlString)
    defer { activeDownloads.remove(urlString) }

    // Ensure composer subdirectory exists
    let composerDir = ledger.baseDirectory.appending(path: composerSlug)
    try FileManager.default.createDirectory(at: composerDir, withIntermediateDirectories: true)

    // Determine local filename
    let filename = Self.localFilename(from: urlString, existingIn: composerDir)
    let destURL = composerDir.appending(path: filename)
    let relativePath = "\(composerSlug)/\(filename)"

    // Download
    logger.info("Downloading \(urlString)")
    let (tempURL, response) = try await URLSession.shared.download(from: url)

    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      try? FileManager.default.removeItem(at: tempURL)
      throw DownloadError.httpError(httpResponse.statusCode)
    }

    // Move to final location (overwrite if exists)
    if FileManager.default.fileExists(atPath: destURL.path()) {
      try FileManager.default.removeItem(at: destURL)
    }
    try FileManager.default.moveItem(at: tempURL, to: destURL)

    // Record in ledger
    ledger.record(sourceUrl: urlString, composerSlug: composerSlug, localPath: relativePath)

    logger.info("Downloaded to \(relativePath)")
    return destURL
  }

  // MARK: - Filename extraction

  /// Extracts a local filename from a MIDI source URL.
  ///
  /// Rules:
  /// 1. URL path ends in .mid → use last path component
  /// 2. URL has `file` query parameter → extract, take last component, ensure .mid
  /// 3. Fallback → SHA256 hash prefix + .mid
  ///
  /// Appends `_2`, `_3` etc. if the name collides with an existing file.
  nonisolated static func localFilename(from urlString: String, existingIn directory: URL) -> String {
    var base = extractBaseName(from: urlString)

    // Ensure .mid extension
    if !base.hasSuffix(".mid") {
      if let dotIndex = base.lastIndex(of: ".") {
        base = String(base[..<dotIndex]) + ".mid"
      } else {
        base += ".mid"
      }
    }

    // Sanitize: keep only alphanumeric, hyphen, underscore, dot, parens
    let stem = String(base.dropLast(4)) // remove .mid
    let sanitized = stem.map { c -> Character in
      if c.isLetter || c.isNumber || c == "-" || c == "_" || c == "(" || c == ")" {
        return c
      }
      return "_"
    }
    base = String(sanitized) + ".mid"

    // Handle collisions
    var candidate = base
    var counter = 2
    while FileManager.default.fileExists(atPath: directory.appending(path: candidate).path()) {
      let stemPart = String(base.dropLast(4))
      candidate = "\(stemPart)_\(counter).mid"
      counter += 1
    }

    return candidate
  }

  nonisolated private static func extractBaseName(from urlString: String) -> String {
    guard let components = URLComponents(string: urlString) else {
      return hashFallback(urlString)
    }

    // Rule 1: path ends in .mid
    let path = components.path
    if path.hasSuffix(".mid") {
      return URL(filePath: path).lastPathComponent
    }

    // Rule 2: file query parameter
    if let fileParam = components.queryItems?.first(where: { $0.name == "file" })?.value {
      let lastComponent = URL(filePath: fileParam).lastPathComponent
      if !lastComponent.isEmpty {
        return lastComponent
      }
    }

    // Rule 3: hash fallback
    return hashFallback(urlString)
  }

  nonisolated private static func hashFallback(_ urlString: String) -> String {
    // Simple hash: use first 12 chars of the URL's hash value as hex
    let hash = abs(urlString.hashValue)
    return String(format: "%012x", hash) + ".mid"
  }

  // MARK: - Errors

  enum DownloadError: LocalizedError {
    case invalidURL(String)
    case httpError(Int)

    var errorDescription: String? {
      switch self {
      case .invalidURL(let url): "Invalid URL: \(url)"
      case .httpError(let code): "HTTP error \(code)"
      }
    }
  }
}
