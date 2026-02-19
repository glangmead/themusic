//
//  PatternStorage.swift
//  Orbital
//

import Foundation

/// Save and load edited patterns to/from the app's documents directory.
enum PatternStorage {
  private static var documentsPatternDir: URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("patterns", isDirectory: true)
  }

  /// Save a PatternSyntax to the documents directory as JSON.
  static func save(_ pattern: PatternSyntax, filename: String) {
    let dir = documentsPatternDir
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(filename)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(pattern) else { return }
    try? data.write(to: url)
  }

  /// Load a PatternSyntax from the documents directory, returning nil if not found.
  static func load(filename: String) -> PatternSyntax? {
    let url = documentsPatternDir.appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(PatternSyntax.self, from: data)
  }

  /// Check whether an edited pattern exists in the documents directory.
  static func exists(filename: String) -> Bool {
    let url = documentsPatternDir.appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: url.path)
  }
}
