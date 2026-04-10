//
//  IPadSongsView.swift
//  Orbital
//

import SwiftUI

/// iPad Songs detail view: shows the song list once the resource manager
/// has resolved its base URL, otherwise a loading indicator.
struct IPadSongsView: View {
  @Environment(ResourceManager.self) private var resourceManager

  var body: some View {
    NavigationStack {
      Group {
        if resourceManager.isReady {
          IPadSongListContent()
        } else {
          ProgressView("Loading songs…")
        }
      }
      .navigationTitle("Songs")
    }
  }
}
