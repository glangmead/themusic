//
//  CatalogV2Models.swift
//  Orbital
//
//  Codable types for the v2 classical music catalog backed by music_catalog data.
//    CatalogComposer   — catalog_v2/composers.json
//    CatalogWork       — catalog_v2/works/[slug].json
//    MIDISource        — a downloadable MIDI source within a work
//

import Foundation

// MARK: - CatalogComposer

struct CatalogComposer: Codable, Identifiable, Sendable {
  var id: String { slug }
  let slug: String
  let qid: String
  let name: String
  let birth: String?
  let death: String?
  let portraitUrl: String?
  let wikipediaUrl: String?
  let wikipediaExtract: String?
  let appleClassicalUrl: String?
  let era: String?
  let nationality: String?

  var birthYear: Int? {
    guard let birth, birth.count >= 4, let y = Int(birth.prefix(4)), y > 0 else { return nil }
    return y
  }

  var deathYear: Int? {
    guard let death, death.count >= 4, let y = Int(death.prefix(4)), y > 0 else { return nil }
    return y
  }

  var lastName: String {
    name.components(separatedBy: " ").last ?? name
  }

  var lifespan: String {
    switch (birthYear, deathYear) {
    case let (b?, d?): "\(b) – \(d)"
    case let (b?, nil): "b. \(b)"
    case let (nil, d?): "d. \(d)"
    case (nil, nil): ""
    }
  }

  enum CodingKeys: String, CodingKey {
    case slug, qid, name, birth, death, era, nationality
    case portraitUrl = "portrait_url"
    case wikipediaUrl = "wikipedia_url"
    case wikipediaExtract = "wikipedia_extract"
    case appleClassicalUrl = "apple_classical_url"
  }
}

// MARK: - MIDISource

struct MIDISource: Codable, Identifiable, Sendable {
  var id: String { origin + ":" + (midiUrls.first ?? "") }
  let origin: String
  let license: String
  let licenseUrl: String?
  let midiUrls: [String]

  /// Sources that require a WebView for the user to interact with the site.
  var requiresWebView: Bool { origin == "kunstderfuge.com" }

  enum CodingKeys: String, CodingKey {
    case origin, license
    case licenseUrl = "license_url"
    case midiUrls = "midi_urls"
  }
}

// MARK: - CatalogWork

struct CatalogWork: Codable, Identifiable, Sendable {
  var id: String { qid ?? "\(title):\(catalogNumbers?.description ?? "")" }
  let title: String
  let qid: String?
  let catalogNumbers: [String: String]?
  let key: String?
  let instruments: [String]?
  let yearComposed: Int?
  let sources: [MIDISource]?

  /// All MIDI URLs across all sources.
  var allMidiUrls: [String] {
    sources?.flatMap(\.midiUrls) ?? []
  }

  /// Whether any source requires a WebView.
  var hasDirectDownload: Bool {
    sources?.contains { !$0.requiresWebView && !$0.midiUrls.isEmpty } ?? false
  }

  /// Formatted catalog number string, e.g. "BWV 565" or "Op. 27/2".
  var catalogLabel: String? {
    guard let catalogNumbers, let (cat, num) = catalogNumbers.first else { return nil }
    return "\(cat) \(num)"
  }

  enum CodingKeys: String, CodingKey {
    case title, qid, key, instruments, sources
    case catalogNumbers = "catalog_numbers"
    case yearComposed = "year_composed"
  }
}

// MARK: - ComposerWorksFile

struct ComposerWorksFile: Codable, Sendable {
  let works: [CatalogWork]
}
