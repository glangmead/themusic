//
//  ComposerListView.swift
//  Orbital
//

import SwiftUI

struct ComposerListView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  @Binding var selectedComposerID: CatalogComposer.ID?

  var body: some View {
    @Bindable var catalog = catalog
    List(catalog.sortedComposers, selection: $selectedComposerID) { composer in
      ComposerRow(composer: composer)
        .tag(composer.id)
    }
    .task {
      await catalog.preloadAllWorkGroups()
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

struct ComposerRow: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  @Environment(MIDIDownloadLedger.self) private var ledger
  let composer: CatalogComposer
  @ScaledMetric(relativeTo: .headline) private var imageSize: CGFloat = 50

  var body: some View {
    HStack(spacing: 12) {
      if let urlString = composer.portraitUrl, let url = URL(string: urlString) {
        FaceAwarePortraitView(url: url, frameHeight: imageSize)
          .frame(width: imageSize, height: imageSize)
          .clipShape(.rect(cornerRadius: 8))
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.secondary.opacity(0.2))
          .frame(width: imageSize, height: imageSize)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(composer.name)
        HStack(spacing: 6) {
          if !composer.lifespan.isEmpty {
            Text(composer.lifespan)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let counts = catalog.counts(for: composer.slug) {
            Text("\u{00B7}")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(counts.worksWithMidi) works")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          let dlCount = ledger.downloadCount(for: composer.slug)
          if dlCount > 0 {
            Text("\u{00B7}")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(dlCount) downloaded")
              .font(.caption)
              .foregroundStyle(.green)
          }
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    ComposerListView(selectedComposerID: .constant(nil))
  }
  .environment(ClassicsCatalogLibrary())
  .environment(SpatialAudioEngine())
  .environment(SongLibrary())
  .environment(ResourceManager())
  .environment(MIDIDownloadManager(ledger: MIDIDownloadLedger(baseDirectory: .temporaryDirectory)))
  .environment(MIDIDownloadLedger(baseDirectory: .temporaryDirectory))
}
