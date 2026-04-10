//
//  AppView.swift
//  Orbital
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

/// Root view; picks the compact (iPhone) or regular (iPad / Mac-as-iPad)
/// layout based on the horizontal size class.
struct AppView: View {
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    if sizeClass == .compact {
      CompactAppLayout()
    } else {
      RegularAppLayout()
    }
  }
}

#Preview {
  let ledger = MIDIDownloadLedger(baseDirectory: .temporaryDirectory)
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
    .environment(ResourceManager())
    .environment(ClassicsCatalogLibrary())
    .environment(ledger)
    .environment(MIDIDownloadManager(ledger: ledger))
    .environment(PresetLibrary())
}
