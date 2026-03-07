//
//  ComposerListView.swift
//  Orbital
//

import SwiftUI

struct ComposerListView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog

  var body: some View {
    @Bindable var catalog = catalog
    List(catalog.sortedComposers) { composer in
      NavigationLink {
        ComposerDetailView(composer: composer)
      } label: {
        ComposerRow(composer: composer)
      }
      .task {
        await catalog.loadWorkGroupsIfNeeded(for: composer)
      }
    }
    .navigationTitle("Composers")
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

// MARK: - ComposerRow

private struct ComposerRow: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  let composer: ComposerEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(composer.name)
      HStack(spacing: 6) {
        if !composer.lifespan.isEmpty {
          Text(composer.lifespan)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let counts = catalog.counts(for: composer.slug) {
          Text("·")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("\(counts.playableGroups) works · \(counts.totalRenditions) renditions")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    ComposerListView()
  }
  .environment(ClassicsCatalogLibrary())
  .environment(SpatialAudioEngine())
  .environment(SongLibrary())
  .environment(ResourceManager())
}
