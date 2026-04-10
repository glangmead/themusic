//
//  TakeEntry.swift
//  Orbital
//
//  Single entry in the takes registry: one playthrough of a song with a
//  specific seed. See TakesStore.swift for the persistence wrapper.
//

import Foundation

struct TakeEntry: Codable, Identifiable, Sendable, Equatable {
  let id: UUID
  let songId: String          // PatternSyntax filename, e.g. "score/Baroque Two-Voice (D minor).json"
  let seed: String            // 10-char Crockford base32
  let startedAt: Date
  var playedSeconds: Double
  var favorite: Bool
  var label: String?          // future use
  /// App version that captured the take, e.g. "1.4.2". Optional for
  /// backward compatibility with older ledger files. Surfaced as a UI
  /// warning when replaying a take from a different version, since
  /// generation pipeline changes can shift what a given seed produces.
  var appVersion: String?
}

extension TakeEntry {
  /// Reads CFBundleShortVersionString from the main bundle. Falls back to
  /// "unknown" if absent (test environments). Cached so repeated calls don't
  /// hit the bundle dictionary.
  static let currentAppVersion: String = {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }()
}

struct TakesLedger: Codable, Sendable, Equatable {
  var entries: [TakeEntry]
}
