//
//  TrackInfo.swift
//  Orbital
//
//  Extracted from SongPlaybackState.swift
//

import Foundation

/// Per-track info exposed to the UI: the track name, its spec, and its compiled preset.
/// `trackSpec` is nil for MIDI tracks (their note data comes from the file).
struct TrackInfo: Identifiable {
  let id: Int
  let patternName: String
  var trackSpec: ProceduralTrackSyntax?
  var presetSpec: PresetSyntax
  let spatialPreset: SpatialPreset
}
