//
//  LoadingTabLabel.swift
//  Orbital
//

import SwiftUI

/// A `Label` whose icon is replaced with a `ProgressView` while `isLoading`
/// is true. Combines the text and progress state into a single VoiceOver
/// announcement so the loading status isn't dropped.
struct LoadingTabLabel: View {
  let text: String
  let systemImage: String
  let isLoading: Bool

  var body: some View {
    Label {
      Text(text)
    } icon: {
      if isLoading {
        ProgressView()
      } else {
        Image(systemName: systemImage)
      }
    }
    .accessibilityLabel(isLoading ? "\(text), loading" : text)
  }
}
