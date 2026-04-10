//
//  PresetLibrary.swift
//  Orbital
//
//  Single source of truth for the user's preset JSONs. Reads them from
//  the resolved resource directory (iCloud Documents or local fallback)
//  using a coordinated, off-main load so that iCloud has a chance to
//  bring files local before we touch them.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.langmead.Orbital", category: "PresetLibrary")

@MainActor @Observable
final class PresetLibrary {
  /// All known presets, sorted by display name.
  private(set) var presets: [PresetRef] = []

  /// True while a load is in flight. Drives loading indicators in the UI.
  private(set) var isLoading = false

  /// Loads (or reloads) presets from `directory`. Safe to call from any
  /// MainActor context — the blocking IO runs on the cooperative pool via
  /// the nonisolated helper.
  func load(from directory: URL) async {
    isLoading = true
    defer { isLoading = false }
    presets = await loadPresetsFromDirectory(directory)
    logger.info("Loaded \(self.presets.count) presets from \(directory.path(percentEncoded: false))")
  }
}
