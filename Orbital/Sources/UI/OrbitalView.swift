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
  @Environment(ResourceManager.self) private var resourceManager
  @State private var selectedSongID: SongRef.ID?
  @State private var songToDelete: SongRef?
  @State private var isShowingDeleteConfirmation = false

  var body: some View {
    NavigationStack {
      Group {
        if resourceManager.isReady {
          List {
            ForEach(library.songs) { song in
              SongCell(song: song, selectedSongID: $selectedSongID)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  Button(role: .destructive) {
                    songToDelete = song
                  } label: {
                    Label("Delete", systemImage: "trash")
                  }
                  .tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                  Button {
                    library.duplicateSong(song, resourceBaseURL: resourceManager.resourceBaseURL)
                  } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                  }
                  .tint(.blue)
                }
            }
          }
          .confirmationDialog(
            "Delete \(songToDelete?.name ?? "")?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
          ) {
            Button("Delete", role: .destructive) {
              if let song = songToDelete {
                library.deleteSong(song)
              }
            }
          } message: {
            Text("This will permanently delete the pattern from iCloud. This cannot be undone.")
          }
          .onChange(of: songToDelete) {
            isShowingDeleteConfirmation = songToDelete != nil
          }
        } else {
          ProgressView("Loading songs…")
        }
      }
      .navigationTitle("Orbital")
      .navigationDestination(item: $selectedSongID) { songID in
        if let song = library.songs.first(where: { $0.id == songID }) {
          let state = library.playbackState(for: song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
          SongSettingsView(song: song)
            .environment(state)
        }
      }
    }

  }
}

#Preview {
  let engine = SpatialAudioEngine()
  let library = SongLibrary()
  let resourceManager = ResourceManager()
  library.songs = [
    SongRef(
      name: "Aurora Borealis",
      patternFileName: "table/aurora_arpeggio.json"
    ),
    SongRef(
      name: "Baroque Chords",
      patternFileName: "table/baroque_chords.json"
    )
  ]
  resourceManager.isReady = true
  // Pre-create playback states so navigating to SongSettingsView works in Preview
  for song in library.songs {
    _ = library.playbackState(for: song, engine: engine)
  }
  return OrbitalView()
    .environment(engine)
    .environment(library)
    .environment(resourceManager)
}
