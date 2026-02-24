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

  /// Resolve the iCloud container, create subdirectories, and copy bundle resources.
  func setup() async {
    // Apple requires this call on a background thread — it may block.
    let containerURL = await Task.detached {
      FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }.value

    let baseURL: URL
    if let containerURL {
      baseURL = containerURL.appendingPathComponent("Documents")
    } else {
      // iCloud unavailable (not signed in, disabled, etc.) — fall back to local Documents.
      baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    let fm = FileManager.default
    for subdir in ["patterns", "presets", "samples"] {
      try? fm.createDirectory(
        at: baseURL.appendingPathComponent(subdir),
        withIntermediateDirectories: true
      )
    }

    copyBundleResources(to: baseURL, subdirectory: "patterns", extensions: ["json", "mid"])
    copyBundleResources(to: baseURL, subdirectory: "presets", extensions: ["json"])
    // samples/ left empty — user can add their own via Files.app

    resourceBaseURL = baseURL
    isReady = true
  }

  // MARK: - Private

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
