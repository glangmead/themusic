//
//  ResourceManager.swift
//  Orbital
//
//  Manages the iCloud Documents container: copies bundled patterns and presets
//  on first launch, creates an empty samples/ directory for user additions,
//  and publishes the base URL for all resource loading.
//

import Foundation

@MainActor @Observable
class ResourceManager {
  /// Base URL for all resource loading (iCloud Documents or local fallback).
  /// Nil until setup completes.
  private(set) var resourceBaseURL: URL?

  /// True once the iCloud container is ready and bundle resources have been copied.
  var isReady = false

  /// True if the app is using the iCloud ubiquity container.
  private(set) var isUsingICloud = false

  /// Resolve the iCloud container, create subdirectories, and copy bundle resources.
  func setup() async {
    // Apple requires this call on a background thread — it may block.
    let containerURL = await Task.detached {
      FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }.value

    let baseURL: URL
    if let containerURL {
      baseURL = containerURL.appendingPathComponent("Documents")
      isUsingICloud = true
    } else {
      // iCloud unavailable (not signed in, disabled, etc.) — fall back to local Documents.
      baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    let fm = FileManager.default
    for subdir in ["patterns/midi", "patterns/score", "patterns/table", "presets", "samples"] {
      try? fm.createDirectory(
        at: baseURL.appendingPathComponent(subdir),
        withIntermediateDirectories: true
      )
    }

    copyBundleResources(to: baseURL, subdirectory: "patterns/midi", extensions: ["json", "mid"])
    copyBundleResources(to: baseURL, subdirectory: "patterns/score", extensions: ["json"])
    copyBundleResources(to: baseURL, subdirectory: "patterns/table", extensions: ["json"])
    copyBundleResources(to: baseURL, subdirectory: "presets", extensions: ["json"])
    // samples/ left empty — user can add their own via Files.app

    migrateOldPatternFilenames(in: baseURL)

    resourceBaseURL = baseURL
    isReady = true
  }

  // MARK: - Private

  private func migrateOldPatternFilenames(in baseURL: URL) {
    let fm = FileManager.default
    let patternsDir = baseURL.appendingPathComponent("patterns")
    let renames: [(old: String, new: String)] = [
      ("midi/All-My-Loving.json", "midi/All My Loving.json"),
      ("midi/Bach_Fugue_in_C_major_BWV_870.json", "midi/Bach Fugue in C major BWV 870.json"),
      ("midi/bach_invention.json", "midi/Bach Invention 1.json"),
      ("midi/debussy-la-cathedrale-engloutie.json", "midi/Debussy La Cathedrale Engloutie.json"),
      ("midi/scriabin_12_etudes_op8.json", "midi/Scriabin 12 Etudes Op. 8.json"),
      ("score/a_hard_days_night_orbital.json", "score/The Beatles \u{2013} A Hard Days Night.json"),
      ("score/guitar_rift.json", "score/Guitar Rift.json"),
      ("score/macm1_orbital.json", "score/Palestrina.json"),
      ("score/op053-1_orbital.json", "score/op053-1.json"),
      ("score/score_bach_chorale_181.json", "score/J. S. Bach \u{2013} Gott hat das Evangelium.json"),
      ("score/score_baroque_two_voice.json", "score/Baroque Two-Voice (D minor).json"),
      ("score/score_c_major_progression.json", "score/C Major Progression.json"),
      ("score/score_mozart_k545.json", "score/Mozart \u{2013} K545.json"),
      ("score/score_mozart_minuet.json", "score/Mozart Minuet (after K282 II).json"),
      ("score/score_yesterday.json", "score/The Beatles \u{2013} Yesterday.json"),
      ("table/airports.json", "table/Airports.json"),
      ("table/aurora_arpeggio.json", "table/Aurora Arpeggio.json"),
      ("table/baroque_chords.json", "table/Baroque Chords.json"),
      ("table/minimal_pulse.json", "table/Minimal Pulse.json"),
      ("table/table_aurora.json", "table/Table Aurora.json")
    ]
    for (old, new) in renames {
      let oldURL = patternsDir.appendingPathComponent(old)
      let newURL = patternsDir.appendingPathComponent(new)
      guard fm.fileExists(atPath: oldURL.path),
            !fm.fileExists(atPath: newURL.path)
      else { continue }
      try? fm.moveItem(at: oldURL, to: newURL)
    }
  }

  private func copyBundleResources(to baseURL: URL, subdirectory: String, extensions: [String]) {
    let fm = FileManager.default
    let destDir = baseURL.appendingPathComponent(subdirectory)
    for ext in extensions {
      for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: subdirectory) ?? [] {
        let dest = destDir.appendingPathComponent(url.lastPathComponent)
        if !fm.fileExists(atPath: dest.path) {
          try? fm.copyItem(at: url, to: dest)
        }
      }
    }
  }
}
