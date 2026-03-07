//
//  ClassicsCatalog.swift
//  Orbital
//
//  Codable types for the classical music catalog:
//    ComposerEntry        — catalog/composers.json
//    WorkEntry            — catalog/works/[slug].json
//    ComposerWorksCatalog — wraps the above
//    PlaybackRendition    — catalog_playback/[slug]/index.json (per-work entry)
//    ComposerPlaybackCatalog — wraps the above
//    WorkGroup            — runtime: WorkEntry + [PlaybackRendition], keyed by wikidata_id
//

import Foundation

// MARK: - ComposerEntry (catalog/composers.json)

struct ComposerEntry: Codable, Identifiable, Sendable {
  var id: String { slug }
  let slug: String
  let qid: String
  let name: String
  let birth: String?
  let death: String?
  let portraitUrl: String?
  let wikipediaUrl: String?
  let wikipediaExtract: String?
  let pageviewsYearly: Int?
  let appleClassicalUrl: String?

  var birthYear: Int? {
    guard let birth, birth.count >= 4, let y = Int(birth.prefix(4)), y > 0 else { return nil }
    return y
  }

  var deathYear: Int? {
    guard let death, death.count >= 4, let y = Int(death.prefix(4)), y > 0 else { return nil }
    return y
  }

  /// Best-effort last name for alphabetical sorting.
  var lastName: String {
    name.components(separatedBy: " ").last ?? name
  }

  /// Formatted lifespan string, e.g. "1685 – 1750" or "b. 1685".
  var lifespan: String {
    switch (birthYear, deathYear) {
    case let (b?, d?): return "\(b) – \(d)"
    case let (b?, nil): return "b. \(b)"
    case let (nil, d?): return "d. \(d)"
    case (nil, nil): return ""
    }
  }

  enum CodingKeys: String, CodingKey {
    case slug, qid, name, birth, death
    case portraitUrl = "portrait_url"
    case wikipediaUrl = "wikipedia_url"
    case wikipediaExtract = "wikipedia_extract"
    case pageviewsYearly = "pageviews_yearly"
    case appleClassicalUrl = "apple_classical_url"
  }
}

// MARK: - WorkEntry (catalog/works/[slug].json)

struct WorkEntry: Codable, Identifiable, Sendable {
  var id: String { qid }
  let qid: String
  let title: String
  let appleClassicalUrl: String?
  let date: String?
  let hasMxl: Bool?
  let pageviewsAnnual: Int?

  enum CodingKeys: String, CodingKey {
    case qid, title, date
    case appleClassicalUrl = "apple_classical_url"
    case hasMxl = "has_mxl"
    case pageviewsAnnual = "pageviews_annual"
  }
}

/// Wraps catalog/works/[slug].json
struct ComposerWorksCatalog: Codable, Sendable {
  let composerSlug: String
  let composerQid: String
  let workCount: Int
  let midiFileCount: Int
  let works: [WorkEntry]

  enum CodingKeys: String, CodingKey {
    case works
    case composerSlug = "composer_slug"
    case composerQid = "composer_qid"
    case workCount = "work_count"
    case midiFileCount = "midi_file_count"
  }
}

// MARK: - PlaybackRendition (catalog_playback/[slug]/index.json work entries)

struct PdmxInfo: Codable, Sendable {
  let rating: Double?
  let nFavorites: Int?
  let nViews: Int?
  let durationSeconds: Double?

  enum CodingKeys: String, CodingKey {
    case rating
    case nFavorites = "n_favorites"
    case nViews = "n_views"
    case durationSeconds = "duration_seconds"
  }
}

struct PlaybackRendition: Codable, Identifiable, Sendable {
  var id: String { midi ?? wikidataId ?? title }
  let title: String
  let midi: String?
  let musicxml: String?
  let wikidataId: String?
  let wikidataTitle: String?
  let displayTitle: String?
  let key: String?
  let tempoBpm: Int?
  let nMeasures: Int?
  let nParts: Int?
  let nNotes: Int?
  let notesPerSecond: Double?
  let appleClassicalSearchUrl: String?
  let pdmx: PdmxInfo?
  let instrumentsGm: [String]?
  let timeSignature: String?

  enum CodingKeys: String, CodingKey {
    case title, midi, musicxml, key
    case wikidataId = "wikidata_id"
    case wikidataTitle = "wikidata_title"
    case displayTitle = "display_title"
    case tempoBpm = "tempo_bpm"
    case nMeasures = "n_measures"
    case nParts = "n_parts"
    case nNotes = "n_notes"
    case notesPerSecond = "notes_per_second"
    case appleClassicalSearchUrl = "apple_music_classical_search_url"
    case pdmx
    case instrumentsGm = "instruments_gm"
    case timeSignature = "time_signature"
  }
}

/// Wraps catalog_playback/[slug]/index.json
struct ComposerPlaybackCatalog: Codable, Sendable {
  let composerName: String
  let nameLastFirst: String?
  let slug: String
  let appleMusicPlaylist: String?
  let era: String?
  let dates: String?
  let nationality: String?
  let notable: Bool?
  let works: [PlaybackRendition]

  enum CodingKeys: String, CodingKey {
    case slug, era, dates, nationality, notable, works
    case composerName = "composer_name"
    case nameLastFirst = "name_last_first"
    case appleMusicPlaylist = "apple_music_playlist"
  }
}

// MARK: - WorkGroup (runtime, not Codable)

/// A group of MIDI renditions that all belong to the same Wikidata work,
/// optionally enriched with work metadata from the catalog.
struct WorkGroup: Identifiable, Sendable {
  let wikidataId: String
  let displayTitle: String
  let workEntry: WorkEntry?
  let renditions: [PlaybackRendition]

  var id: String { wikidataId }
}
