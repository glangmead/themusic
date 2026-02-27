//
//  TrackInfo.swift
//  Orbital
//
//  Extracted from SongDocument.swift (was SongPlaybackState.swift)
//

import Foundation

/// Per-track document data exposed to the UI: names and editable preset spec.
struct TrackInfo: Identifiable {
  let id: Int
  let patternName: String
  var presetSpec: PresetSyntax
}
