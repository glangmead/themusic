//
//  OrbitalView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct OrbitalView: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @State private var selectedSongID: SongRef.ID?

  var body: some View {
    NavigationStack {
      List {
        ForEach(library.songs) { song in
          SongCell(song: song, selectedSongID: $selectedSongID)
        }
      }
      .navigationTitle("Orbital")
      .navigationDestination(item: $selectedSongID) { songID in
        if let song = library.songs.first(where: { $0.id == songID }) {
          let state = library.playbackState(for: song, engine: engine)
          SongSettingsView(song: song)
            .environment(state)
        }
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let library = SongLibrary()
  library.songs = [
    SongRef(
      name: "Aurora Borealis",
      patternFileName: "aurora_arpeggio.json"
    ),
    SongRef(
      name: "Baroque Chords",
      patternFileName: "baroque_chords.json"
    ),
  ]
  // Pre-create playback states so navigating to SongSettingsView works in Preview
  for song in library.songs {
    _ = library.playbackState(for: song, engine: engine)
  }
  return OrbitalView()
    .environment(engine)
    .environment(library)
}

