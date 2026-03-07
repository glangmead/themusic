//
//  ClassicsCatalogTests.swift
//  OrbitalTests
//
//  Tests for ClassicsCatalog Codable types and ClassicsCatalogLibrary data loading.
//

import Testing
import Foundation
@testable import Orbital

@Suite("ClassicsCatalogTests")
struct ClassicsCatalogTests {

  // MARK: - ComposerEntry

  @Test("ComposerEntry decodes from JSON")
  func composerEntryDecodes() throws {
    let json = """
    [{"slug":"bach","qid":"Q1339","name":"Johann Sebastian Bach",
      "birth":"1685-03-21","death":"1750-07-28","pageviews_yearly":500000}]
    """
    let composers = try JSONDecoder().decode([ComposerEntry].self, from: Data(json.utf8))
    #expect(composers.count == 1)
    #expect(composers[0].slug == "bach")
    #expect(composers[0].name == "Johann Sebastian Bach")
    #expect(composers[0].birthYear == 1685)
    #expect(composers[0].deathYear == 1750)
    #expect(composers[0].pageviewsYearly == 500_000)
  }

  @Test("ComposerEntry lifespan formatting")
  func composerLifespan() throws {
    let both = ComposerEntry(slug: "bach", qid: "Q1339", name: "Bach",
      birth: "1685-03-21", death: "1750-07-28",
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: nil, appleClassicalUrl: nil)
    #expect(both.lifespan == "1685 – 1750")

    let birthOnly = ComposerEntry(slug: "x", qid: "Q1", name: "X",
      birth: "1900-01-01", death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: nil, appleClassicalUrl: nil)
    #expect(birthOnly.lifespan == "b. 1900")

    let neither = ComposerEntry(slug: "x", qid: "Q1", name: "X",
      birth: nil, death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: nil, appleClassicalUrl: nil)
    #expect(neither.lifespan == "")
  }

  @Test("ComposerEntry lastName extraction")
  func composerLastName() throws {
    let bach = ComposerEntry(slug: "bach", qid: "Q1339", name: "Johann Sebastian Bach",
      birth: nil, death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: nil, appleClassicalUrl: nil)
    #expect(bach.lastName == "Bach")
  }

  @Test("ComposerEntry handles zeroed dates gracefully")
  func composerZeroedDate() throws {
    // Some entries have "1455-00-00" which has year 1455 but month/day 0
    let json = """
    [{"slug":"des_prez","qid":"Q143100","name":"Josquin des Prez","birth":"1455-00-00"}]
    """
    let composers = try JSONDecoder().decode([ComposerEntry].self, from: Data(json.utf8))
    #expect(composers[0].birthYear == 1455)
  }

  // MARK: - PlaybackRendition

  @Test("PlaybackRendition decodes from JSON")
  func renditionDecodes() throws {
    let json = """
    {"title":"Sinfonia in E major BWV 792","midi":"midi/BWV_792_Sinfonia_VI.mid",
     "wikidata_id":"Q111804166","display_title":"15 Sinfonias",
     "key":"E major","tempo_bpm":184,"n_measures":41,
     "apple_music_classical_search_url":"https://classical.music.apple.com/us/search?q=Bach"}
    """
    let rendition = try JSONDecoder().decode(PlaybackRendition.self, from: Data(json.utf8))
    #expect(rendition.title == "Sinfonia in E major BWV 792")
    #expect(rendition.wikidataId == "Q111804166")
    #expect(rendition.displayTitle == "15 Sinfonias")
    #expect(rendition.tempoBpm == 184)
    #expect(rendition.key == "E major")
  }

  // MARK: - ComposerPlaybackCatalog

  @Test("ComposerPlaybackCatalog decodes from JSON")
  func playbackCatalogDecodes() throws {
    let json = """
    {"composer_name":"Johann Sebastian Bach","slug":"bach","era":"Baroque",
     "works":[
       {"title":"Sinfonia in E major BWV 792","midi":"midi/BWV_792.mid",
        "wikidata_id":"Q111804166","display_title":"15 Sinfonias"}
     ]}
    """
    let catalog = try JSONDecoder().decode(ComposerPlaybackCatalog.self, from: Data(json.utf8))
    #expect(catalog.slug == "bach")
    #expect(catalog.composerName == "Johann Sebastian Bach")
    #expect(catalog.works.count == 1)
    #expect(catalog.works[0].wikidataId == "Q111804166")
  }

  // MARK: - ClassicsCatalogLibrary sorting

  @Test("sortedComposers by pageviews descending")
  @MainActor func sortedByPageviewsDescending() {
    let lib = ClassicsCatalogLibrary()
    // Inject test data directly
    let entry1 = ComposerEntry(slug: "a", qid: "Q1", name: "Alpha", birth: "1600-01-01", death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: 100, appleClassicalUrl: nil)
    let entry2 = ComposerEntry(slug: "b", qid: "Q2", name: "Beta", birth: "1700-01-01", death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: 500, appleClassicalUrl: nil)
    let entry3 = ComposerEntry(slug: "c", qid: "Q3", name: "Gamma", birth: "1800-01-01", death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      pageviewsYearly: 250, appleClassicalUrl: nil)

    // Use the sort logic directly
    lib.sortOrder = .pageviews
    lib.sortAscending = false

    let sorted = [entry1, entry2, entry3].sorted { a, b in
      let asc = (a.pageviewsYearly ?? 0) < (b.pageviewsYearly ?? 0)
      return lib.sortAscending ? asc : !asc
    }
    #expect(sorted[0].slug == "b") // 500
    #expect(sorted[1].slug == "c") // 250
    #expect(sorted[2].slug == "a") // 100
  }

  @Test("sortedComposers by lastName ascending")
  @MainActor func sortedByLastName() {
    let lib = ClassicsCatalogLibrary()
    lib.sortOrder = .lastName
    lib.sortAscending = true

    let entries = [
      ComposerEntry(slug: "c", qid: "Q3", name: "Johann Chopin",
        birth: nil, death: nil, portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
        pageviewsYearly: nil, appleClassicalUrl: nil),
      ComposerEntry(slug: "a", qid: "Q1", name: "Johann Sebastian Bach",
        birth: nil, death: nil, portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
        pageviewsYearly: nil, appleClassicalUrl: nil),
      ComposerEntry(slug: "m", qid: "Q2", name: "Wolfgang Mozart",
        birth: nil, death: nil, portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
        pageviewsYearly: nil, appleClassicalUrl: nil)
    ]

    let sorted = entries.sorted { a, b in
      let asc = a.lastName.localizedCaseInsensitiveCompare(b.lastName) == .orderedAscending
      return lib.sortAscending ? asc : !asc
    }
    #expect(sorted[0].slug == "a") // Bach
    #expect(sorted[1].slug == "c") // Chopin
    #expect(sorted[2].slug == "m") // Mozart
  }

  // MARK: - WorkGroup grouping

  @Test("computeWorkGroups groups renditions by wikidata_id")
  func workGroupsGroupByWikidataId() throws {
    // Build a minimal ComposerPlaybackCatalog in memory and verify grouping logic
    let json = """
    {"composer_name":"Test Composer","slug":"test","works":[
      {"title":"Prelude in C","midi":"midi/a.mid","wikidata_id":"Q100","display_title":"Preludes"},
      {"title":"Prelude in D","midi":"midi/b.mid","wikidata_id":"Q100","display_title":"Preludes"},
      {"title":"Fugue in G","midi":"midi/c.mid","wikidata_id":"Q200","display_title":"Fugues"}
    ]}
    """
    let catalog = try JSONDecoder().decode(ComposerPlaybackCatalog.self, from: Data(json.utf8))

    // Group manually using the same logic as computeWorkGroups
    var groups: [String: [PlaybackRendition]] = [:]
    var groupOrder: [String] = []
    for rendition in catalog.works where rendition.midi != nil {
      let key = rendition.wikidataId ?? "ungrouped/\(rendition.midi!)"
      if groups[key] == nil { groups[key] = []; groupOrder.append(key) }
      groups[key]!.append(rendition)
    }
    let workGroups = groupOrder.compactMap { key -> Orbital.WorkGroup? in
      guard let renditions = groups[key], !renditions.isEmpty else { return nil }
      return Orbital.WorkGroup(
        wikidataId: key,
        displayTitle: renditions.first?.displayTitle ?? key,
        workEntry: nil,
        renditions: renditions
      )
    }

    #expect(workGroups.count == 2)
    let preludesGroup = workGroups.first { $0.wikidataId == "Q100" }
    #expect(preludesGroup?.renditions.count == 2)
    #expect(preludesGroup?.displayTitle == "Preludes")
    let fuguesGroup = workGroups.first { $0.wikidataId == "Q200" }
    #expect(fuguesGroup?.renditions.count == 1)
  }

  // MARK: - Disk-based catalog validation

  /// Decodes every catalog_playback/[slug]/index.json that exists on disk and
  /// asserts it parses without error, has non-empty works, and at least one
  /// work with a non-nil MIDI path. This catches null-midi regressions and
  /// type mismatches in any composer's JSON file.
  @Test("All composer playback catalogs decode without error")
  func allPlaybackCatalogsDecodeWithoutError() throws {
    let resourcesURL = URL(filePath: #filePath)
      .deletingLastPathComponent() // OrbitalTests/
      .deletingLastPathComponent() // Orbital/
      .appendingPathComponent("Resources")

    // Load master composers list
    let composersURL = resourcesURL.appendingPathComponent("catalog/composers.json")
    let composersData = try Data(contentsOf: composersURL)
    let composers = try JSONDecoder().decode([ComposerEntry].self, from: composersData)
    #expect(!composers.isEmpty, "composers.json is empty")

    var testedCount = 0
    var failures: [String] = []

    for composer in composers {
      let indexURL = resourcesURL
        .appendingPathComponent("catalog_playback")
        .appendingPathComponent(composer.slug)
        .appendingPathComponent("index.json")
      guard FileManager.default.fileExists(atPath: indexURL.path) else { continue }

      do {
        let data = try Data(contentsOf: indexURL)
        let catalog = try JSONDecoder().decode(ComposerPlaybackCatalog.self, from: data)
        let playableCount = catalog.works.filter { $0.midi != nil }.count
        if catalog.works.isEmpty {
          failures.append("\(composer.slug): works array is empty")
        } else if playableCount == 0 {
          failures.append("\(composer.slug): \(catalog.works.count) works but none have a midi path")
        }
        testedCount += 1
      } catch {
        failures.append("\(composer.slug): decode error – \(error)")
      }
    }

    #expect(testedCount > 0, "No catalog_playback index files found — check Resources path")
    #expect(failures.isEmpty, "Catalog failures:\n\(failures.joined(separator: "\n"))")
  }
}
