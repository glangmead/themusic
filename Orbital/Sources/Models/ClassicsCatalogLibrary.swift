//
//  ClassicsCatalogLibrary.swift
//  Orbital
//
//  Observable data manager for the classical music catalog.
//  Loads composers and works from the catalog_v2 bundle data,
//  lazily loads per-composer works off the main thread, and caches results.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.langmead.Orbital", category: "ClassicsCatalog")

@MainActor @Observable
class ClassicsCatalogLibrary {

  // MARK: - Sort

  enum SortOrder: String, CaseIterable, Identifiable {
    case lastName  = "Last Name"
    case birthYear = "Birth Year"
    var id: String { rawValue }
  }

  var sortOrder: SortOrder = .lastName { didSet { recomputeSorted() } }
  var sortAscending: Bool = true { didSet { recomputeSorted() } }

  // MARK: - Data

  private(set) var composers: [CatalogComposer] = []
  private(set) var sortedComposers: [CatalogComposer] = []
  private var worksCache: [String: [CatalogWork]] = [:]
  private var composerCountsCache: [String: ComposerCounts] = [:]

  struct ComposerCounts: Sendable {
    let totalWorks: Int
    let worksWithMidi: Int
  }

  // MARK: - Derived

  private func recomputeSorted() {
    sortedComposers = composers.sorted { a, b in
      let asc: Bool
      switch sortOrder {
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
    composers = Bundle.main.decode(
      [CatalogComposer].self, from: "composers.json", subdirectory: "catalog_v2"
    )
    recomputeSorted()
    logger.notice("Loaded \(self.composers.count) composers")
  }

  func counts(for slug: String) -> ComposerCounts? {
    composerCountsCache[slug]
  }

  /// Preload works for all composers. Loads all files off the main actor
  /// in a single detached task, then applies results in one batch to
  /// minimize @Observable churn.
  func preloadAllWorkGroups() async {
    // Wait for load() to populate composers — the .task that calls load()
    // and the .task that calls this method run concurrently.
    while composers.isEmpty {
      try? await Task.sleep(for: .milliseconds(50))
    }
    let slugs = composers.map(\.slug).filter { worksCache[$0] == nil }
    logger.notice("preloadAllWorkGroups: \(slugs.count) composers to load")
    guard !slugs.isEmpty else { return }

    // Load all files off the main actor in one batch.
    let results = await Task.detached(priority: .utility) {
      slugs.map { slug in
        (slug, ClassicsCatalogLibrary.loadWorksFromBundle(composerSlug: slug))
      }
    }.value

    // Single batch update — one @Observable notification instead of 131.
    for (slug, works) in results {
      worksCache[slug] = works
      composerCountsCache[slug] = ComposerCounts(
        totalWorks: works.count,
        worksWithMidi: works.filter { !($0.sources?.isEmpty ?? true) }.count
      )
    }
  }

  /// Load and cache works for a composer. No-op if already cached.
  func loadWorksIfNeeded(for composer: CatalogComposer) async {
    let slug = composer.slug
    logger.notice("loadWorksIfNeeded: slug=\(slug) cached=\(self.worksCache[slug] != nil)")
    guard worksCache[slug] == nil else { return }

    let works = await Task.detached(priority: .userInitiated) {
      ClassicsCatalogLibrary.loadWorksFromBundle(composerSlug: slug)
    }.value

    worksCache[slug] = works
    composerCountsCache[slug] = ComposerCounts(
      totalWorks: works.count,
      worksWithMidi: works.filter { !($0.sources?.isEmpty ?? true) }.count
    )
  }

  func cachedWorks(for slug: String) -> [CatalogWork] {
    worksCache[slug] ?? []
  }

  // MARK: - Bundle I/O (nonisolated — runs off main actor via Task.detached)

  nonisolated static func loadWorksFromBundle(composerSlug: String) -> [CatalogWork] {
    guard let url = Bundle.main.url(
      forResource: composerSlug, withExtension: "json", subdirectory: "catalog_v2/works"
    ) else {
      logger.error("No bundle URL for \(composerSlug).json")
      return []
    }
    guard let data = try? Data(contentsOf: url) else {
      logger.error("Failed to read data from \(url.path)")
      return []
    }
    do {
      let file = try JSONDecoder().decode(ComposerWorksFile.self, from: data)
      logger.notice("Loaded \(file.works.count) works for \(composerSlug)")
      return file.works
    } catch {
      logger.error("Failed to decode \(composerSlug): \(error.localizedDescription)")
      return []
    }
  }
}
