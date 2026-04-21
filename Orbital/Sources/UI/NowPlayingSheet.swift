//
//  NowPlayingSheet.swift
//  Orbital
//

import SwiftUI

/// iPhone presentation of the Now Playing view. Wraps `NowPlayingView` in a
/// `NavigationStack` with a large-detent sheet and a drag indicator. A `Done`
/// button is offered as a fallback for users who don't discover the drag.
struct NowPlayingSheet: View {
  let state: SongDocument
  @Binding var isShowingVisualizer: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      NowPlayingView(state: state, isShowingVisualizer: $isShowingVisualizer)
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}
