import Foundation

enum PatternFilename {
  /// Characters forbidden in APFS filenames, mapped to visually similar Unicode alternatives.
  private static let escapeTable: [(dangerous: String, safe: String)] = [
    ("/", "\u{2215}"),  // FRACTION SLASH
    (":", "\u{A789}")  // MODIFIER LETTER COLON
  ]

  /// Derive a display name from a pattern filename (e.g. "Aurora Arpeggio.json" → "Aurora Arpeggio").
  static func displayName(from filename: String) -> String {
    var name = filename
    if name.hasSuffix(".json") {
      name = String(name.dropLast(5))
    }
    for (dangerous, safe) in escapeTable {
      name = name.replacing(safe, with: dangerous)
    }
    return name
  }

  /// Derive a pattern filename from a display name (e.g. "Aurora Arpeggio" → "Aurora Arpeggio.json").
  static func filename(from displayName: String) -> String {
    var name = displayName
    for (dangerous, safe) in escapeTable {
      name = name.replacing(dangerous, with: safe)
    }
    return name + ".json"
  }
}
