//
//  LoadingSidebarRow.swift
//  Orbital
//

import SwiftUI

/// Sidebar row used by `RegularAppLayout`. Trailing `ProgressView` appears
/// while `isLoading` is true; the accessibility label folds the loading
/// state into the announcement so VoiceOver users don't miss it.
struct LoadingSidebarRow: View {
  let category: SidebarCategory
  let isLoading: Bool

  var body: some View {
    HStack {
      Label(category.rawValue, systemImage: category.systemImage)
      if isLoading {
        Spacer()
        ProgressView()
          .controlSize(.small)
      }
    }
    .accessibilityIdentifier("sidebar-\(category.rawValue)")
    .accessibilityLabel(isLoading ? "\(category.rawValue), loading" : category.rawValue)
    .accessibilityAddTraits(.isButton)
  }
}
