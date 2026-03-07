//
//  ClassicsBrowserView.swift
//  Orbital
//

import SwiftUI

struct ClassicsBrowserView: View {
  var body: some View {
    NavigationStack {
      ComposerListView()
    }
  }
}

#Preview {
  ClassicsBrowserView()
    .environment(ClassicsCatalogLibrary())
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
    .environment(ResourceManager())
}
