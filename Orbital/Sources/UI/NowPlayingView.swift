//
//  NowPlayingView.swift
//  Orbital
//

import SwiftUI

/// Reusable body shared by the iPhone sheet (`NowPlayingSheet`) and the iPad
/// detail pane (`IPadDetailView.nowPlaying`). Renders a Form with four
/// sections: header, transport, takes (when the song has randomness), and the
/// event log.
struct NowPlayingView: View {
  let state: SongDocument
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    Form {
      Section {
        NowPlayingHeaderView(state: state)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))
      }

      if !state.isLoading {
        Section("Transport") {
          TransportControls(isShowingVisualizer: $isShowingVisualizer, style: .expanded)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .center)
        }

        SongTakesSection(songDocument: state)

        Section("Event Log") {
          EventLogView(eventLog: state.eventLog)
        }
      } else {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .padding(.vertical, 20)
        }
      }
    }
  }
}
