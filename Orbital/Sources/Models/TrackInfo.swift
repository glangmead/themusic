//
//  TrackInfo.swift
//  Orbital
//
//  Extracted from SongDocument.swift (was SongPlaybackState.swift)
//

import Foundation

/// Per-track document data exposed to the UI: names and editable specs.
/// Does NOT hold live audio state — that lives in `RuntimeSong`.
/// `trackSpec` is nil for MIDI tracks (their note data comes from the file).
struct TrackInfo: Identifiable {
  let id: Int
  let patternName: String
  var trackSpec: ProceduralTrackSyntax?
  var presetSpec: PresetSyntax
}
