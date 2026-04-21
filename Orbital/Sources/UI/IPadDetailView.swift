//
//  IPadDetailView.swift
//  Orbital
//

import SwiftUI

/// Dispatches the iPad detail pane based on the selected sidebar category.
struct IPadDetailView: View {
  @Environment(SongLibrary.self) private var library
  let selectedCategory: SidebarCategory?
  let createDocument: SongDocument?
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    switch selectedCategory {
    case .nowPlaying:
      NavigationStack {
        if let state = library.currentPlaybackState ?? createDocument {
          NowPlayingView(state: state, isShowingVisualizer: $isShowingVisualizer)
            .navigationTitle("Now Playing")
        } else {
          ContentUnavailableView(
            "Nothing Playing",
            systemImage: "play.circle",
            description: Text("Start a song from the Library to see it here.")
          )
        }
      }
    case .songs:
      IPadSongsView()
    case .classics:
      IPadClassicsView()
    case .create:
      IPadCreateView(createDocument: createDocument)
    case .soundDesign:
      SoundDesignView()
    case nil:
      ContentUnavailableView(
        "Select a Category",
        systemImage: "sidebar.left",
        description: Text("Choose a category from the sidebar.")
      )
    }
  }
}

/// Wraps the generator form so the Create category has its own dedicated view.
struct IPadCreateView: View {
  let createDocument: SongDocument?

  var body: some View {
    NavigationStack {
      if let createDocument {
        GeneratorFormView(params: createDocument.generatorPattern ?? GeneratorSyntax())
          .environment(createDocument)
      } else {
        ProgressView()
      }
    }
  }
}
