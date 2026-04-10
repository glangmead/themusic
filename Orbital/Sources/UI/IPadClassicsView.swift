//
//  IPadClassicsView.swift
//  Orbital
//

import SwiftUI

/// iPad Classics detail view: shows the composer list with sort controls.
struct IPadClassicsView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog

  var body: some View {
    NavigationStack {
      IPadComposerList()
    }
  }
}

/// The list of composers shown inside `IPadClassicsView`.
struct IPadComposerList: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog

  var body: some View {
    @Bindable var catalog = catalog
    List(catalog.sortedComposers) { composer in
      NavigationLink(value: composer.id) {
        ComposerRow(composer: composer)
      }
    }
    .navigationTitle("Composers")
    .navigationDestination(for: CatalogComposer.ID.self) { composerID in
      if let composer = catalog.sortedComposers.first(where: { $0.id == composerID }) {
        ComposerDetailView(composer: composer)
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Sort by", selection: $catalog.sortOrder) {
            ForEach(ClassicsCatalogLibrary.SortOrder.allCases) { order in
              Text(order.rawValue).tag(order)
            }
          }
          Divider()
          Toggle("Ascending", isOn: $catalog.sortAscending)
        } label: {
          Label("Sort", systemImage: "arrow.up.arrow.down")
        }
      }
    }
  }
}
