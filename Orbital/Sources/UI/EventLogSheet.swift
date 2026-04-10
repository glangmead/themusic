//
//  EventLogSheet.swift
//  Orbital
//

import SwiftUI

/// Full event log presented as a sheet with a grab bar.
struct EventLogSheet: View {
  let state: SongDocument
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      EventLogView(eventLog: state.eventLog)
        .navigationTitle("Event Log")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done", action: dismissSheet)
          }
        }
    }
    .presentationDragIndicator(.visible)
  }

  private func dismissSheet() {
    dismiss()
  }
}
