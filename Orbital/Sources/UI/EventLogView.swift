//
//  EventLogView.swift
//  Orbital
//
//  Scrolling log of event annotations from the playback engine.
//

import SwiftUI

struct EventLogView: View {
  let eventLog: [EventAnnotation]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(eventLog) { annotation in
              EventLogRowView(annotation: annotation)
                .id(annotation.id)
            }
          }
          .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .onChange(of: eventLog.count) {
          if let last = eventLog.last {
            withAnimation(.easeOut(duration: 0.15)) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
      }
      .navigationTitle("Event Log")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct EventLogRowView: View {
  let annotation: EventAnnotation

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(String(format: "%.1f", annotation.timestamp))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 48, alignment: .trailing)
        .font(.caption)

      Text(annotation.trackName)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(width: 80, alignment: .leading)
        .lineLimit(1)

      if let chord = annotation.chordSymbol {
        Text(chord)
          .bold()
          .foregroundStyle(Theme.colorHighlight)
          .frame(width: 52, alignment: .leading)
      }

      Text("\(annotation.notes.count) notes")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      HStack(spacing: 4) {
        Text("s:\(String(format: "%.1f", annotation.sustain))")
        Text("g:\(String(format: "%.1f", annotation.gap))")
      }
      .font(.caption2)
      .monospacedDigit()
      .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }
}
