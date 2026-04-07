//
//  ClassicsBrowserView.swift
//  Orbital
//

import SwiftUI

struct ClassicsBrowserView: View {
  @Environment(ClassicsCatalogLibrary.self) private var catalog
  @State private var selectedComposerID: CatalogComposer.ID?

  var body: some View {
    NavigationStack {
      ComposerListView(selectedComposerID: $selectedComposerID)
        .navigationDestination(item: $selectedComposerID) { composerID in
          if let composer = catalog.sortedComposers.first(where: { $0.id == composerID }) {
            ComposerDetailView(composer: composer)
          }
        }
    }
  }
}

#Preview {
  ClassicsBrowserView()
    .environment(ClassicsCatalogLibrary())
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
    .environment(ResourceManager())
    .environment(MIDIDownloadManager(ledger: MIDIDownloadLedger(baseDirectory: .temporaryDirectory)))
    .environment(MIDIDownloadLedger(baseDirectory: .temporaryDirectory))
}
