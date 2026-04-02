//
//  PADSynthGraphView.swift
//  Orbital
//

import Charts
import SwiftUI

struct PADSynthGraphView: View {
  var engine: PADSynthEngine
  @State private var touchPoints: [CGPoint] = []
  @State private var isDragging = false

  private static let freqDomain: ClosedRange<Double> = 20...40_000

  var body: some View {
    Chart {
      if engine.envelopeCoefficients != nil {
        // Orange dashed: drawn envelope
        ForEach(engine.displayEnvelope) { point in
          LineMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(by: .value("Series", "Envelope"))
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
        }

        // Green: enveloped spectrum (what will be heard)
        ForEach(engine.displayProduct) { point in
          LineMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(by: .value("Series", "Result"))
          .lineStyle(StrokeStyle(lineWidth: 1))
        }
      } else {
        // Blue: raw PADsynth freq_amp (only when no envelope)
        ForEach(engine.displayFreqAmp) { point in
          LineMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(by: .value("Series", "PADsynth"))
          .lineStyle(StrokeStyle(lineWidth: 1))
        }
      }
    }
    .chartForegroundStyleScale([
      "PADsynth": Color.blue,
      "Envelope": Color.orange,
      "Result": Color.green
    ])
    .chartXScale(domain: Self.freqDomain, type: .log)
    .chartXAxis {
      AxisMarks(values: [20, 50, 200, 1000, 5000, 20_000, 40_000]) { value in
        AxisGridLine()
        AxisValueLabel {
          if let freq = value.as(Double.self) {
            Text(Self.formatFrequency(freq))
              .font(.caption2)
          }
        }
      }
    }
    .chartYScale(domain: .automatic(includesZero: true))
    .chartYAxis {
      AxisMarks(position: .leading) { _ in
        AxisGridLine()
      }
    }
    .chartLegend(.hidden)
    .overlay(alignment: .topTrailing) {
      PADSynthLegend()
    }
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                isDragging = true
                touchPoints.append(value.location)
              }
              .onEnded { _ in
                isDragging = false
                fitEnvelopeFromTouchPoints(proxy: proxy, geometry: geometry)
              }
          )
          .overlay {
            if isDragging {
              ForEach(touchPoints.indices, id: \.self) { idx in
                Circle()
                  .fill(.orange)
                  .frame(width: 4, height: 4)
                  .position(touchPoints[idx])
              }
            }
          }
      }
    }
  }

  private func fitEnvelopeFromTouchPoints(proxy: ChartProxy, geometry: GeometryProxy) {
    guard let plotFrame = proxy.plotFrame else {
      touchPoints.removeAll()
      return
    }
    let plotRect = geometry[plotFrame]
    let logMin = log2(PADSynthEngine.minFreq)
    let logMax = log2(PADSynthEngine.maxFreq)

    let points: [(x: CoreFloat, y: CoreFloat)] = touchPoints.compactMap { point
      -> (x: CoreFloat, y: CoreFloat)? in
      guard let freq: Double = proxy.value(atX: point.x - plotRect.minX) else { return nil }
      guard freq >= PADSynthEngine.minFreq && freq <= PADSynthEngine.maxFreq else { return nil }

      let normalizedY = CoreFloat(1.0 - ((point.y - plotRect.minY) / plotRect.height))
      let amplitude = max(0.0, min(1.0, normalizedY))

      let logFreq = log2(freq)
      let normalizedLogFreq = (logFreq - logMin) / (logMax - logMin) * 10.0

      return (x: normalizedLogFreq, y: amplitude)
    }

    touchPoints.removeAll()

    guard points.count >= 2 else { return }
    engine.envelopeCoefficients = PADSynthEngine.fitPolynomial(points: points, degree: 20)

    Task {
      await engine.recomputeDisplay()
    }
  }

  private static func formatFrequency(_ freq: Double) -> String {
    if freq >= 1000 {
      return "\(Int(freq / 1000))k"
    }
    return "\(Int(freq))"
  }
}

// MARK: - Legend

private struct PADSynthLegend: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label("PADsynth", systemImage: "minus")
        .foregroundStyle(.blue)
      Label("Envelope", systemImage: "minus")
        .foregroundStyle(.orange)
      Label("Result", systemImage: "minus")
        .foregroundStyle(.green)
    }
    .font(.caption2)
    .padding(8)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 6))
    .padding(8)
  }
}
