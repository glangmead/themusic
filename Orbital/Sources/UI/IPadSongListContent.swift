//
//  IPadSongListContent.swift
//  Orbital
//

import SwiftUI

/// iPad song list with swipe actions, shown inside the Songs category detail.
struct IPadSongListContent: View {
  @Environment(SpatialAudioEngine.self) private var engine
  @Environment(SongLibrary.self) private var library
  @Environment(ResourceManager.self) private var resourceManager
  @State private var songToDelete: SongRef?
  @State private var isShowingDeleteConfirmation = false

  var body: some View {
    List {
      ForEach(library.songs) { song in
        NavigationLink(value: song.id) {
          SongCell(song: song)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button("Delete", systemImage: "trash", role: .destructive) {
            songToDelete = song
          }
          .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          Button("Duplicate", systemImage: "doc.on.doc") {
            library.duplicateSong(song, resourceBaseURL: resourceManager.resourceBaseURL)
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
    .navigationDestination(for: SongRef.ID.self) { songID in
      if let song = library.songs.first(where: { $0.id == songID }) {
        let state = library.playbackState(for: song, engine: engine, resourceBaseURL: resourceManager.resourceBaseURL)
        SongSettingsView(song: song)
          .environment(state)
      }
    }
  }
}
