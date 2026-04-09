//
//  PatternStorage.swift
//  Orbital
//

import Foundation

/// Save and load edited patterns to/from the iCloud Documents directory.
enum PatternStorage {
  /// Set by ResourceManager at startup. When nil, falls back to local Documents.
  @MainActor static var resourceBaseURL: URL?

  @MainActor private static var patternsDir: URL {
    if let base = resourceBaseURL {
      return base.appendingPathComponent("patterns", isDirectory: true)
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("patterns", isDirectory: true)
  }

  /// Save a PatternSyntax as JSON.
  @MainActor static func save(_ pattern: PatternSyntax, filename: String) {
    let url = patternsDir.appendingPathComponent(filename)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(pattern) else { return }
    try? data.write(to: url)
  }

  /// Load a PatternSyntax, returning nil if not found.
  @MainActor static func load(filename: String) -> PatternSyntax? {
    let url = patternsDir.appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(PatternSyntax.self, from: data)
  }

  /// Check whether a pattern exists.
  @MainActor static func exists(filename: String) -> Bool {
    let url = patternsDir.appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: url.path)
  }

  /// Delete a pattern file. For iCloud, this is permanent.
  @MainActor static func delete(filename: String) {
    let url = patternsDir.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: url)
  }

  /// Duplicate a pattern file with versioned naming.
  /// "Foo.json" → "Foo v2.json", "Foo v2.json" → "Foo v3.json", etc.
  /// Returns the new filename (relative to patterns/), or nil on failure.
  @MainActor static func duplicate(filename: String) -> String? {
    let sourceURL = patternsDir.appendingPathComponent(filename)
    let newFilename = nextVersionFilename(filename)
    let destURL = patternsDir.appendingPathComponent(newFilename)
    guard (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil else { return nil }
    return newFilename
  }

  /// Given "subdir/Foo.json" returns "subdir/Foo v2.json".
  /// Given "subdir/Foo v2.json" returns "subdir/Foo v3.json".
  /// Keeps incrementing if the computed filename already exists on disk.
  @MainActor private static func nextVersionFilename(_ filename: String) -> String {
    let dir = (filename as NSString).deletingLastPathComponent
    let ext = (filename as NSString).pathExtension
    var stem = ((filename as NSString).lastPathComponent as NSString).deletingPathExtension

    if let range = stem.range(of: #" v(\d+)$"#, options: .regularExpression),
       let numRange = stem.range(of: #"\d+$"#, options: .regularExpression),
       let n = Int(stem[numRange]) {
      stem = String(stem[stem.startIndex..<range.lowerBound]) + " v\(n + 1)"
    } else {
      stem += " v2"
    }

    var candidate = dir.isEmpty ? "\(stem).\(ext)" : "\(dir)/\(stem).\(ext)"
    while FileManager.default.fileExists(atPath: patternsDir.appendingPathComponent(candidate).path) {
      if let numRange = stem.range(of: #"\d+$"#, options: .regularExpression),
         let n = Int(stem[numRange]) {
        stem = String(stem[stem.startIndex..<numRange.lowerBound]) + "\(n + 1)"
      } else {
        stem += " v2"
      }
      candidate = dir.isEmpty ? "\(stem).\(ext)" : "\(dir)/\(stem).\(ext)"
    }

    return candidate
  }
}
