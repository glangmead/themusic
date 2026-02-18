//
//  AppView.swift
//  Orbital
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI

struct AppView: View {
  var body: some View {
    OrbitalView()
  }
}

#Preview {
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
}
