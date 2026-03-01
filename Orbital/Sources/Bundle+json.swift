//
//  Bundle+json.swift
//  Orbital
//
//  Created by Greg Langmead on 12/11/25.
//

import Foundation

extension Bundle {
  func decode<T: Decodable>(_ type: T.Type, from file: String, dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate, keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys, subdirectory: String? = nil) -> T {
    guard let url = self.url(forResource: file, withExtension: nil, subdirectory: subdirectory) else {
      fatalError("Failed to locate \(file) in bundle.")
    }

    guard let data = try? Data(contentsOf: url) else {
      fatalError("Failed to load \(file) from bundle.")
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = dateDecodingStrategy
    decoder.keyDecodingStrategy = keyDecodingStrategy

    do {
      return try decoder.decode(T.self, from: data)
    } catch DecodingError.keyNotFound(let key, let context) {
      fatalError("Failed to decode \(file) from bundle due to missing key '\(key.stringValue)' not found – \(context.debugDescription)")
    } catch DecodingError.typeMismatch(_, let context) {
      fatalError("Failed to decode \(file) from bundle due to type mismatch – \(context.debugDescription)")
    } catch DecodingError.valueNotFound(let type, let context) {
      fatalError("Failed to decode \(file) from bundle due to missing \(type) value – \(context.debugDescription)")
    } catch DecodingError.dataCorrupted(_) {
      fatalError("Failed to decode \(file) from bundle because it appears to be invalid JSON")
    } catch {
      fatalError("Failed to decode \(file) from bundle: \(error.localizedDescription)")
    }
  }
}

/// Decode a JSON file, optionally from an explicit base directory URL instead of the app bundle.
/// When `resourceBaseURL` is nil, delegates to `Bundle.main.decode(...)`.
/// When set, looks for `subdirectory/filename` under that directory.
func decodeJSON<T: Decodable>(_ type: T.Type, from file: String, subdirectory: String? = nil, resourceBaseURL: URL? = nil) -> T {
  guard let base = resourceBaseURL else {
    return Bundle.main.decode(type, from: file, subdirectory: subdirectory)
  }
  var url = base
  if let subdirectory { url = url.appendingPathComponent(subdirectory) }
  url = url.appendingPathComponent(file)
  guard let data = try? Data(contentsOf: url) else {
    fatalError("Failed to load \(file) from \(url.path).")
  }
  do {
    return try JSONDecoder().decode(T.self, from: data)
  } catch {
    fatalError("Failed to decode \(file) from \(url.path): \(error.localizedDescription)")
  }
}

/// Resolve a resource URL, optionally from an explicit base directory URL instead of the app bundle.
/// When `resourceBaseURL` is nil, delegates to `Bundle.main.url(forResource:withExtension:)`.
/// When set, looks for `filename.ext` under that directory and common subdirectories (samples/).
func resolveResourceURL(name: String, ext: String, resourceBaseURL: URL? = nil) -> URL? {
  guard let base = resourceBaseURL else {
    return Bundle.main.url(forResource: name, withExtension: ext)
  }
  let filename = "\(name).\(ext)"
  // Check root directory first, then common resource subdirectories
  for subdir in ["", "samples"] {
    let url = subdir.isEmpty ? base.appendingPathComponent(filename) : base.appendingPathComponent(subdir).appendingPathComponent(filename)
    if FileManager.default.fileExists(atPath: url.path) { return url }
  }
  // Fall back to bundle for built-in resources (e.g. shipped sample files)
  return Bundle.main.url(forResource: name, withExtension: ext)
}
