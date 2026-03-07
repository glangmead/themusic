//
//  ClassicsCatalogLibrary.swift
//  Orbital
//
//  Observable data manager for the classical music catalog.
//  Loads composers from bundle, lazily loads per-composer work groups
//  off the main thread, and caches results.
//

import Foundation

@MainActor @Observable
class ClassicsCatalogLibrary {

  // MARK: - Sort

  enum SortOrder: String, CaseIterable, Identifiable {
    case pageviews = "Wikipedia Views"
    case lastName  = "Last Name"
    case birthYear = "Birth Year"
    var id: String { rawValue }
  }

  var sortOrder: SortOrder = .pageviews { didSet { recomputeSorted() } }
  var sortAscending: Bool = false { didSet { recomputeSorted() } }

  // MARK: - Data

  private(set) var composers: [ComposerEntry] = []
  private(set) var sortedComposers: [ComposerEntry] = []
  private var workGroupsCache: [String: [WorkGroup]] = [:]
  private var composerCountsCache: [String: ComposerCounts] = [:]

  struct ComposerCounts {
    let playableGroups: Int   // distinct wikidata works with playable MIDI
    let totalRenditions: Int  // total individual MIDI files
  }

  // MARK: - Derived

  private func recomputeSorted() {
    sortedComposers = composers.sorted { a, b in
      let asc: Bool
      switch sortOrder {
      case .pageviews:
        asc = (a.pageviewsYearly ?? 0) < (b.pageviewsYearly ?? 0)
      case .lastName:
        asc = a.lastName.localizedCaseInsensitiveCompare(b.lastName) == .orderedAscending
      case .birthYear:
        asc = (a.birthYear ?? 0) < (b.birthYear ?? 0)
      }
      return sortAscending ? asc : !asc
    }
  }

  // MARK: - Loading

  func load() {
    composers = Bundle.main.decode([ComposerEntry].self, from: "composers.json", subdirectory: "catalog")
    recomputeSorted()
  }

  func counts(for slug: String) -> ComposerCounts? {
    composerCountsCache[slug]
  }

  /// Load and cache work groups for a composer. Safe to call repeatedly; no-op if already cached.
  func loadWorkGroupsIfNeeded(for composer: ComposerEntry) async {
    let slug = composer.slug
    guard workGroupsCache[slug] == nil else { return }

    let groups = await Task.detached(priority: .userInitiated) {
      ClassicsCatalogLibrary.computeWorkGroups(composerSlug: slug)
    }.value

    workGroupsCache[slug] = groups
    composerCountsCache[slug] = ComposerCounts(
      playableGroups: groups.count,
      totalRenditions: groups.reduce(0) { $0 + $1.renditions.count }
    )
  }

  func cachedWorkGroups(for slug: String) -> [WorkGroup] {
    workGroupsCache[slug] ?? []
  }

  // MARK: - Bundle I/O (nonisolated — runs off main actor via Task.detached)

  nonisolated static func computeWorkGroups(composerSlug: String) -> [WorkGroup] {
    // Load the playback catalog (required — composer must have playable MIDI)
    let playbackSubdir = "catalog_playback/\(composerSlug)"
    guard let playbackURL = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: playbackSubdir) else {
      print("[ClassicsCatalog] catalog_playback/\(composerSlug)/index.json not found in bundle")
      return []
    }
    guard let data = try? Data(contentsOf: playbackURL) else {
      print("[ClassicsCatalog] Could not read data at \(playbackURL.path)")
      return []
    }
    let playbackCatalog: ComposerPlaybackCatalog
    do {
      playbackCatalog = try JSONDecoder().decode(ComposerPlaybackCatalog.self, from: data)
    } catch {
      print("[ClassicsCatalog] Decode error for \(composerSlug): \(error)")
      return []
    }

    // Load the works catalog (optional — enriches sections with work metadata)
    var worksByQid: [String: WorkEntry] = [:]
    if let worksURL = Bundle.main.url(forResource: composerSlug, withExtension: "json", subdirectory: "catalog/works"),
    let worksData = try? Data(contentsOf: worksURL),
    let worksCatalog = try? JSONDecoder().decode(ComposerWorksCatalog.self, from: worksData) {
      for work in worksCatalog.works {
        worksByQid[work.qid] = work
      }
    }

    // Group renditions by wikidata_id, preserving order of first appearance.
    // Skip renditions with no MIDI file (null midi in JSON).
    var groups: [String: [PlaybackRendition]] = [:]
    var groupOrder: [String] = []
    for rendition in playbackCatalog.works where rendition.midi != nil {
      let key = rendition.wikidataId ?? "ungrouped/\(rendition.midi!)"
      if groups[key] == nil {
        groups[key] = []
        groupOrder.append(key)
      }
      groups[key]!.append(rendition)
    }

    return groupOrder.compactMap { key in
      guard let renditions = groups[key], !renditions.isEmpty else { return nil }
      let workEntry = renditions.first?.wikidataId.flatMap { worksByQid[$0] }
      let displayTitle = renditions.first?.displayTitle
        ?? renditions.first?.wikidataTitle
        ?? renditions.first?.title
        ?? key
      return WorkGroup(
        wikidataId: key,
        displayTitle: displayTitle,
        workEntry: workEntry,
        renditions: renditions
      )
    }
  }
}
