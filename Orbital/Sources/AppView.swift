//
//  AppView.swift
//  Orbital
//
//  Created by Greg Langmead on 12/1/25.
//

import SwiftUI
import WebKit

/// Root view; picks the compact (iPhone) or regular (iPad / Mac-as-iPad)
/// layout based on the horizontal size class.
struct AppView: View {
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    ZStack {
      // Pre-warm WebKit at launch so the first real open of the visualizer
      // doesn't stall the main thread long enough to underrun the audio
      // render callback. First WKWebView instantiation in a process loads
      // WebKit and spins up the WebContent service (~100 ms on iOS);
      // subsequent instantiations are cheap.
      WebKitPrewarm()
        .frame(width: 0, height: 0)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)

      if sizeClass == .compact {
        CompactAppLayout()
      } else {
        RegularAppLayout()
      }
    }
  }
}

/// Invisible WKWebView kept alive to hold WebKit warm through the app's
/// lifetime.
private struct WebKitPrewarm: UIViewRepresentable {
  func makeUIView(context: Context) -> WKWebView {
    let view = WKWebView(frame: .zero)
    view.loadHTMLString("<html></html>", baseURL: nil)
    return view
  }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#Preview {
  let ledger = MIDIDownloadLedger(baseDirectory: .temporaryDirectory)
  AppView()
    .environment(SpatialAudioEngine())
    .environment(SongLibrary())
    .environment(ResourceManager())
    .environment(ClassicsCatalogLibrary())
    .environment(ledger)
    .environment(MIDIDownloadManager(ledger: ledger))
    .environment(PresetLibrary())
}
