//
//  EventLogView.swift
//  Orbital
//
//  Scrolling log of event annotations from the playback engine. Rendered as a
//  sequence of rows suitable for placement inside a List or Form Section.
//

import SwiftUI

struct EventLogView: View {
  let eventLog: [EventAnnotation]

  var body: some View {
    ForEach(eventLog) { annotation in
      EventLogRowView(annotation: annotation)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
    }
  }
}

private struct EventLogRowView: View {
  let annotation: EventAnnotation

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(annotation.timestamp, format: .number.precision(.fractionLength(1)))
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
          .frame(width: 52, alignment: .leading)
      }

      Text("\(annotation.notes.count) notes")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("[\(annotation.notes.map { String($0.note) }.joined(separator: ","))]")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      HStack(spacing: 4) {
        Text("s:")
        Text(annotation.sustain, format: .number.precision(.fractionLength(1)))
        Text("g:")
        Text(annotation.gap, format: .number.precision(.fractionLength(1)))
      }
      .font(.caption2)
      .monospacedDigit()
      .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }
}
