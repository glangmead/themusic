//
//  VisualizerOverlay.swift
//  Orbital
//

import SwiftUI

/// The full-screen visualizer pane shared between compact and regular layouts.
struct VisualizerOverlay: View {
  let engine: SpatialAudioEngine
  @Binding var isShowingVisualizer: Bool

  var body: some View {
    VisualizerView(engine: engine, isPresented: $isShowingVisualizer)
      .ignoresSafeArea()
      .opacity(isShowingVisualizer ? 1 : 0)
      .allowsHitTesting(isShowingVisualizer)
      .animation(.easeInOut(duration: 0.4), value: isShowingVisualizer)
  }
}
