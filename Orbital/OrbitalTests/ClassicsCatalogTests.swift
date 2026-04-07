//
//  ClassicsCatalogTests.swift
//  OrbitalTests
//
//  Tests for catalog v2 Codable types and ClassicsCatalogLibrary data loading.
//

import Testing
import Foundation
@testable import Orbital

@Suite("ClassicsCatalogTests")
struct ClassicsCatalogTests {

  // MARK: - CatalogComposer

  @Test("CatalogComposer decodes from JSON")
  func composerDecodes() throws {
    let json = """
    [{"slug":"bach","qid":"Q1339","name":"Johann Sebastian Bach",
      "birth":"1685-03-21","death":"1750-07-28","era":"Baroque"}]
    """
    let composers = try JSONDecoder().decode([CatalogComposer].self, from: Data(json.utf8))
    #expect(composers.count == 1)
    #expect(composers[0].slug == "bach")
    #expect(composers[0].name == "Johann Sebastian Bach")
    #expect(composers[0].birthYear == 1685)
    #expect(composers[0].deathYear == 1750)
  }

  @Test("CatalogComposer lifespan formatting")
  func composerLifespan() throws {
    let both = CatalogComposer(slug: "bach", qid: "Q1339", name: "Bach",
      birth: "1685-03-21", death: "1750-07-28",
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      appleClassicalUrl: nil, era: nil, nationality: nil)
    #expect(both.lifespan == "1685 – 1750")

    let birthOnly = CatalogComposer(slug: "x", qid: "Q1", name: "X",
      birth: "1900-01-01", death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      appleClassicalUrl: nil, era: nil, nationality: nil)
    #expect(birthOnly.lifespan == "b. 1900")

    let neither = CatalogComposer(slug: "x", qid: "Q1", name: "X",
      birth: nil, death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      appleClassicalUrl: nil, era: nil, nationality: nil)
    #expect(neither.lifespan == "")
  }

  @Test("CatalogComposer lastName extraction")
  func composerLastName() throws {
    let bach = CatalogComposer(slug: "bach", qid: "Q1339", name: "Johann Sebastian Bach",
      birth: nil, death: nil,
      portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
      appleClassicalUrl: nil, era: nil, nationality: nil)
    #expect(bach.lastName == "Bach")
  }

  // MARK: - CatalogWork

  @Test("CatalogWork decodes from JSON")
  func workDecodes() throws {
    let json = """
    {"title":"Toccata and Fugue in D minor, BWV 565","qid":"Q392734",
     "catalog_numbers":{"BWV":"565"},"key":"D Minor",
     "sources":[{"origin":"kern.ccarh.org","license":"CC BY-NC-SA 4.0",
                  "midi_urls":["https://kern.humdrum.org/test.mid"]}]}
    """
    let work = try JSONDecoder().decode(CatalogWork.self, from: Data(json.utf8))
    #expect(work.title == "Toccata and Fugue in D minor, BWV 565")
    #expect(work.qid == "Q392734")
    #expect(work.catalogNumbers?["BWV"] == "565")
    #expect(work.catalogLabel == "BWV 565")
    #expect(work.sources?.count == 1)
    #expect(work.allMidiUrls.count == 1)
    #expect(work.hasDirectDownload == true)
  }

  @Test("CatalogWork without sources")
  func workWithoutSources() throws {
    let json = """
    {"title":"Some work"}
    """
    let work = try JSONDecoder().decode(CatalogWork.self, from: Data(json.utf8))
    #expect(work.sources == nil)
    #expect(work.allMidiUrls.isEmpty)
    #expect(work.hasDirectDownload == false)
  }

  // MARK: - MIDISource

  @Test("MIDISource requiresWebView for kunstderfuge")
  func midiSourceRequiresWebView() throws {
    let kdf = MIDISource(origin: "kunstderfuge.com", license: "personal use",
      licenseUrl: nil, midiUrls: ["https://example.com/test.mid"])
    #expect(kdf.requiresWebView == true)

    let kern = MIDISource(origin: "kern.ccarh.org", license: "CC",
      licenseUrl: nil, midiUrls: ["https://example.com/test.mid"])
    #expect(kern.requiresWebView == false)
  }

  // MARK: - MIDIDownloadManager filename extraction

  @Test("Filename extraction from Mutopia URL (path ends in .mid)")
  func filenameFromMutopiaURL() {
    let filename = MIDIDownloadManager.localFilename(
      from: "https://www.mutopiaproject.org/ftp/BachJS/BWV565/ToccataFugue/ToccataFugue.mid",
      existingIn: .temporaryDirectory.appending(path: "nonexistent_dir_\(UUID())")
    )
    #expect(filename == "ToccataFugue.mid")
  }

  @Test("Filename extraction from kern URL (file query param)")
  func filenameFromKernURL() {
    let filename = MIDIDownloadManager.localFilename(
      from: "https://kern.humdrum.org/cgi-bin/ksdata?file=partita1-6.krn&l=users/craig/classical/bach/violin&format=midi",
      existingIn: .temporaryDirectory.appending(path: "nonexistent_dir_\(UUID())")
    )
    #expect(filename == "partita1-6.mid")
  }

  @Test("Filename extraction from kdf URL (file query param with path)")
  func filenameFromKdfURL() {
    let filename = MIDIDownloadManager.localFilename(
      from: "https://www.kunstderfuge.com/-/midi.asp?file=bach/organ_major_works_bwv-565_(c)unknown1.mid",
      existingIn: .temporaryDirectory.appending(path: "nonexistent_dir_\(UUID())")
    )
    #expect(filename == "organ_major_works_bwv-565_(c)unknown1.mid")
  }

  // MARK: - ClassicsCatalogLibrary sorting

  @Test("sortedComposers by lastName ascending")
  @MainActor func sortedByLastName() {
    let lib = ClassicsCatalogLibrary()
    lib.sortOrder = .lastName
    lib.sortAscending = true

    let entries = [
      CatalogComposer(slug: "c", qid: "Q3", name: "Johann Chopin",
        birth: nil, death: nil, portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
        appleClassicalUrl: nil, era: nil, nationality: nil),
      CatalogComposer(slug: "a", qid: "Q1", name: "Johann Sebastian Bach",
        birth: nil, death: nil, portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
        appleClassicalUrl: nil, era: nil, nationality: nil),
      CatalogComposer(slug: "m", qid: "Q2", name: "Wolfgang Mozart",
        birth: nil, death: nil, portraitUrl: nil, wikipediaUrl: nil, wikipediaExtract: nil,
        appleClassicalUrl: nil, era: nil, nationality: nil)
    ]

    let sorted = entries.sorted { a, b in
      let asc = a.lastName.localizedCaseInsensitiveCompare(b.lastName) == .orderedAscending
      return lib.sortAscending ? asc : !asc
    }
    #expect(sorted[0].slug == "a") // Bach
    #expect(sorted[1].slug == "c") // Chopin
    #expect(sorted[2].slug == "m") // Mozart
  }

  // MARK: - Disk-based catalog validation

  @Test("All catalog_v2 works files decode without error")
  func allWorksFilesDecodeWithoutError() throws {
    let resourcesURL = URL(filePath: #filePath)
      .deletingLastPathComponent() // OrbitalTests/
      .deletingLastPathComponent() // Orbital/
      .appendingPathComponent("Resources")

    let composersURL = resourcesURL.appendingPathComponent("catalog_v2/composers.json")
    let composersData = try Data(contentsOf: composersURL)
    let composers = try JSONDecoder().decode([CatalogComposer].self, from: composersData)
    #expect(!composers.isEmpty, "composers.json is empty")

    var testedCount = 0
    var failures: [String] = []

    for composer in composers {
      let worksURL = resourcesURL
        .appendingPathComponent("catalog_v2/works")
        .appendingPathComponent("\(composer.slug).json")
      guard FileManager.default.fileExists(atPath: worksURL.path) else { continue }

      do {
        let data = try Data(contentsOf: worksURL)
        let file = try JSONDecoder().decode(ComposerWorksFile.self, from: data)
        if file.works.isEmpty {
          failures.append("\(composer.slug): works array is empty")
        }
        testedCount += 1
      } catch {
        failures.append("\(composer.slug): decode error – \(error)")
      }
    }

    #expect(testedCount > 0, "No catalog_v2 works files found — check Resources path")
    #expect(failures.isEmpty, "Catalog failures:\n\(failures.joined(separator: "\n"))")
  }
}
