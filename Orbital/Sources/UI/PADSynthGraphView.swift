//
//  PADSynthGraphView.swift
//  Orbital
//

import Charts
import SwiftUI

struct PADSynthGraphView: View {
  var engine: PADSynthEngine
  var onEnvelopeChanged: (() -> Void)?
  @State private var touchPoints: [CGPoint] = []
  @State private var isDragging = false
  @State private var cachedImage: Image?
  @State private var cachedVersion: Int = -1
  @State private var chartSize: CGSize = .zero

  var body: some View {
    ZStack {
      // Cached chart image — only re-rendered when data changes
      if let cachedImage {
        cachedImage
          .resizable()
          .scaledToFit()
      }

      // Drawing overlay
      Rectangle()
        .fill(.clear)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              isDragging = true
              touchPoints.append(value.location)
            }
            .onEnded { value in
              isDragging = false
              fitEnvelopeFromTouchPoints(size: chartSize)
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
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { newSize in
      chartSize = newSize
    }
    .task(id: engine.displayVersion) {
      guard engine.displayVersion != cachedVersion else { return }
      renderChart()
    }
    .overlay(alignment: .topTrailing) {
      PADSynthLegend()
    }
  }

  @MainActor
  private func renderChart() {
    guard chartSize.width > 0 && chartSize.height > 0 else { return }
    let chartView = makeChart()
      .frame(width: chartSize.width, height: chartSize.height)
    let renderer = ImageRenderer(content: chartView)
    renderer.scale = 2.0
    if let uiImage = renderer.uiImage {
      cachedImage = Image(uiImage: uiImage)
      cachedVersion = engine.displayVersion
    }
  }

  @ViewBuilder
  private func makeChart() -> some View {
    Chart {
      if engine.envelopeCoefficients != nil {
        ForEach(engine.displayEnvelope) { point in
          LineMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(by: .value("Series", "Envelope"))
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
        }

        ForEach(engine.displayProduct) { point in
          LineMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(by: .value("Series", "Result"))
          .lineStyle(StrokeStyle(lineWidth: 1))
        }
      } else {
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
    .chartXScale(domain: 20.0...40_000.0, type: .log)
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
  }

  // MARK: - Envelope fitting

  /// Maps a screen x position to a log-frequency value using the same
  /// log scale the chart uses (20 Hz – 40 kHz).
  private func fitEnvelopeFromTouchPoints(size: CGSize) {
    let logMin = log2(PADSynthEngine.minFreq)
    let logMax = log2(PADSynthEngine.maxFreq)

    let points: [(x: CoreFloat, y: CoreFloat)] = touchPoints.compactMap { point
      -> (x: CoreFloat, y: CoreFloat)? in
      // Map x to frequency via log interpolation (matching the chart's log axis)
      let t = CoreFloat(point.x / size.width)
      guard t >= 0 && t <= 1 else { return nil }
      let logFreq = logMin + t * (logMax - logMin)
      let freq = pow(2.0, logFreq)
      guard freq >= PADSynthEngine.minFreq && freq <= PADSynthEngine.maxFreq else { return nil }

      let normalizedY = CoreFloat(1.0 - (point.y / size.height))
      let amplitude = max(0.0, min(1.0, normalizedY))

      let normalizedLogFreq = t * 10.0
      return (x: normalizedLogFreq, y: amplitude)
    }

    touchPoints.removeAll()

    guard points.count >= 2 else { return }
    engine.envelopeCoefficients = PADSynthEngine.fitPolynomial(points: points, degree: 20)
    onEnvelopeChanged?()

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
