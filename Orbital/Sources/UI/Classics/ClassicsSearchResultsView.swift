//
//  ClassicsSearchResultsView.swift
//  Orbital
//
//  Displays works matching a search query across every preloaded composer.
//  Used by the top-level Classics search. Only works that have at least
//  one MIDI source are shown, since non-MIDI works have no detail page.
//

import SwiftUI

struct ClassicsSearchResultsView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  let query: String

  private var results: [ClassicsSearchItem] {
    let tokens = ClassicsSearch.tokens(for: query)
    guard !tokens.isEmpty else { return [] }
    return catalog.allWorksByComposer()
      .lazy
      .filter { !($0.1.sources?.isEmpty ?? true) }
      .filter { ClassicsSearch.matches(composer: $0.0, work: $0.1, tokens: tokens) }
      .map { ClassicsSearchItem(composer: $0.0, work: $0.1) }
  }

  var body: some View {
    let items = results
    List(items) { item in
      NavigationLink {
        WorkDetailView(composer: item.composer, work: item.work)
      } label: {
        WorkSearchRow(composer: item.composer, work: item.work)
      }
    }
    .overlay {
      if items.isEmpty {
        ContentUnavailableView.search(text: query)
      }
    }
    .navigationTitle("Search")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct WorkSearchRow: View {
  let composer: CatalogComposer
  let work: CatalogWork

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(work.title)
        .lineLimit(2)
      HStack(spacing: 6) {
        Text(composer.name)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let label = work.catalogLabel {
          Text("\u{00B7}")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let key = work.key {
          Text("\u{00B7}")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
