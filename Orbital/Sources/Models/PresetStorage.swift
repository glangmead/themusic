//
//  PresetStorage.swift
//  Orbital
//

import Foundation

/// Save and load preset files to/from the iCloud Documents directory.
enum PresetStorage {
  @MainActor private static var presetsDir: URL {
    if let base = PatternStorage.resourceBaseURL {
      return base.appendingPathComponent("presets", isDirectory: true)
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("presets", isDirectory: true)
  }

  /// Duplicate a preset file with versioned naming.
  /// "foo.json" -> "foo_v2.json", "foo_v2.json" -> "foo_v3.json", etc.
  /// Returns the new filename, or nil on failure.
  @MainActor static func duplicate(filename: String) -> String? {
    let sourceURL = presetsDir.appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: sourceURL),
          var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    let newFilename = nextVersionFilename(filename)
    let oldName = (json["name"] as? String) ?? ""
    json["name"] = nextVersionName(oldName)

    guard let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return nil }
    let destURL = presetsDir.appendingPathComponent(newFilename)
    guard (try? newData.write(to: destURL)) != nil else { return nil }
    return newFilename
  }

  /// Given "foo.json" returns "foo_v2.json".
  /// Given "foo_v2.json" returns "foo_v3.json".
  /// Keeps incrementing if the computed filename already exists on disk.
  @MainActor private static func nextVersionFilename(_ filename: String) -> String {
    let ext = (filename as NSString).pathExtension
    var basename = (filename as NSString).deletingPathExtension

    if let range = basename.range(of: #"_v(\d+)$"#, options: .regularExpression),
       let numRange = basename.range(of: #"\d+$"#, options: .regularExpression),
       let n = Int(basename[numRange]) {
      basename = String(basename[basename.startIndex..<range.lowerBound]) + "_v\(n + 1)"
    } else {
      basename += "_v2"
    }

    var candidate = "\(basename).\(ext)"
    // If that file already exists, keep incrementing
    while FileManager.default.fileExists(atPath: presetsDir.appendingPathComponent(candidate).path) {
      if let numRange = basename.range(of: #"\d+$"#, options: .regularExpression),
         let n = Int(basename[numRange]) {
        basename = String(basename[basename.startIndex..<numRange.lowerBound]) + "\(n + 1)"
      } else {
        basename += "_v2"
      }
      candidate = "\(basename).\(ext)"
    }

    return candidate
  }

  /// Given "Foo" returns "Foo v2".
  /// Given "Foo v2" returns "Foo v3".
  private static func nextVersionName(_ name: String) -> String {
    if let range = name.range(of: #" v(\d+)$"#, options: .regularExpression),
       let numRange = name.range(of: #"\d+$"#, options: .regularExpression),
       let n = Int(name[numRange]) {
      return String(name[name.startIndex..<range.lowerBound]) + " v\(n + 1)"
    }
    return name + " v2"
  }
}
