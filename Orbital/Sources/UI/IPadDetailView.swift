//
//  IPadDetailView.swift
//  Orbital
//

import SwiftUI

/// Dispatches the iPad detail pane based on the selected sidebar category.
struct IPadDetailView: View {
  let selectedCategory: SidebarCategory?
  let createDocument: SongDocument?

  var body: some View {
    switch selectedCategory {
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
