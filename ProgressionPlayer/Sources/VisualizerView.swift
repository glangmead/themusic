//
//  VisualizerView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/20/26.
//

import SwiftUI
import WebKit

struct VisualizerView: UIViewRepresentable {
  var synth: SyntacticSynth
  
  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
    config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    config.mediaTypesRequiringUserActionForPlayback = []
    config.allowsInlineMediaPlayback = true
    
    let userContentController = WKUserContentController()
    userContentController.add(context.coordinator, name: "keyHandler")
    config.userContentController = userContentController
    
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.isInspectable = true
    webView.backgroundColor = .black
    webView.navigationDelegate = context.coordinator
    
    if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
      print("Visualizer loading index.html from \(indexURL)")
      
      // Debug: Check for JS files
      if let jsURL = Bundle.main.url(forResource: "butterchurn", withExtension: "js") {
        print("Found butterchurn.js at \(jsURL)")
      } else {
        print("ERROR: butterchurn.js NOT found in bundle")
      }
      if let presetsURL = Bundle.main.url(forResource: "butterchurn-presets", withExtension: "js") {
        print("Found butterchurn-presets.js at \(presetsURL)")
      } else {
        print("ERROR: butterchurn-presets.js NOT found in bundle")
      }
      
      webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
    context.coordinator.setupAudioTap(webView: webView)
    
    return webView
  }
  
  func updateUIView(_ uiView: WKWebView, context: Context) {
  }
  
  static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
    coordinator.stopAudioTap()
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(synth: synth)
  }
  
  class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let synth: SyntacticSynth
    weak var webView: WKWebView?
    
    var pendingSamples: [Float] = []
    let sendThreshold = 1024 // Accumulate about 2 tap buffers before sending
    
    init(synth: SyntacticSynth) {
      self.synth = synth
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "keyHandler", let dict = message.body as? [String: String],
         let key = dict["key"], let type = dict["type"] {
        playKey(key: key, type: type)
      }
    }
    
    func playKey(key: String, type: String) {
      let charToMidiNote: [String: Int] = [
        "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67, "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75
      ]
      
      if let noteValue = charToMidiNote[key] {
        // Handle repeated keydowns (auto-repeat) by ignoring them if we wanted,
        // but for now let's just re-trigger or rely on synth logic.
        // Actually, SwiftUI's onKeyPress handles phases nicely. JS gives us repeated "keydowns".
        // We should track state or just let noteOn fire repeatedly (might re-trigger envelope).
        // Ideally we only fire noteOn if it wasn't already pressed.
        
        if type == "keydown" {
          synth.voicePool?.noteOn(MidiNote(note: UInt8(noteValue), velocity: 100))
        } else if type == "keyup" {
          synth.voicePool?.noteOff(MidiNote(note: UInt8(noteValue), velocity: 100))
        }
      }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      print("Visualizer webview finished loading index.html")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      print("Visualizer webview failed loading: \(error.localizedDescription)")
    }
    
    func setupAudioTap(webView: WKWebView) {
      self.webView = webView
      
      synth.engine.installTap { [weak self] samples in
        guard let self = self else { return }
        
        // Append to buffer
        // Data is Interleaved Stereo [L, R, L, R...]
        self.pendingSamples.append(contentsOf: samples)
        
        // Only send if we have enough data to make the bridge call worth it
        // Threshold 2048 floats = 1024 stereo frames
        if self.pendingSamples.count >= self.sendThreshold {
          let samplesToSend = self.pendingSamples
          self.pendingSamples.removeAll(keepingCapacity: true)
          
          // Convert array to JSON string
          let jsonString = samplesToSend.description
          
          DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("if(window.pushSamples) window.pushSamples(\(jsonString))", completionHandler: nil)
          }
        }
      }
    }
    
    func stopAudioTap() {
      synth.engine.removeTap()
    }
  }
}
