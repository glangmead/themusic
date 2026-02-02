//
//  VisualizerView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/20/26.
//

import SwiftUI
import WebKit

// Pre-loads the visualizer resources to avoid a hitch on first open
class VisualizerWarmer {
  static let shared = VisualizerWarmer()
  private var webView: WKWebView?
  
  func warmup() {
    print("VisualizerWarmer: Warming up...")
    let config = WKWebViewConfiguration()
    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
    config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    
    // Create a hidden webview to trigger the process creation and file loading
    let webView = VisualizerWebView(frame: .zero, configuration: config)
    self.webView = webView
    
    if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
      webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
    
    // Keep it alive for a moment to ensure loading starts.
    // We'll keep it for 10 seconds which should be plenty for the "first time" initialization to happen.
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
      print("VisualizerWarmer: Warmup complete, releasing temporary webview.")
      self.webView = nil
    }
  }
}

// Host a web view that displays the Butterchurn-ios visualizer.
// The visualizer index.html is modified from https://github.com/pxl-pshr/butterchurn-ios
// The two .js files it imported were copied from the CDN into the app bundle:
// https://cdn.jsdelivr.net/npm/butterchurn@3.0.0-beta.5/dist/butterchurn.min.js
// https://cdn.jsdelivr.net/npm/butterchurn-presets@3.0.0-beta.4/dist/all.min.js
// (which are the 3.0 versions, whereas butterchurn-ios was made with v2 in mind)
class VisualizerWebView: WKWebView {
  // Hide the input accessory view (the bar above the keyboard)
  override var inputAccessoryView: UIView? {
    return nil
  }
  
  // Also try to prevent it from becoming first responder if that's the issue
  override var canBecomeFirstResponder: Bool {
    return true // Needs to be true to receive key events, but we want to suppress the UI
  }
}

struct VisualizerView: UIViewRepresentable {
  var synth: SyntacticSynth
  @AppStorage("lastVisualizerPreset") private var lastPreset: String = ""
  @Environment(\.dismiss) var dismiss
  
  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
    config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    config.mediaTypesRequiringUserActionForPlayback = []
    config.allowsInlineMediaPlayback = true
    
    let userContentController = WKUserContentController()
    userContentController.add(context.coordinator, name: "keyHandler")
    userContentController.add(context.coordinator, name: "presetHandler")
    userContentController.add(context.coordinator, name: "closeViz")
    config.userContentController = userContentController
    
    let webView = VisualizerWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.isInspectable = true // allows watching its console.log messages from Safari
    webView.backgroundColor = .black
    webView.navigationDelegate = context.coordinator
    
    if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
      print("Visualizer: loading index.html from \(indexURL)")
      
      // Debug: Check for JS files
      if let jsURL = Bundle.main.url(forResource: "butterchurn", withExtension: "js") {
        print("Visualizer: Found butterchurn.js at \(jsURL)")
      } else {
        print("ERROR: butterchurn.js NOT found in bundle")
      }
      if let presetsURL = Bundle.main.url(forResource: "butterchurn-presets", withExtension: "js") {
        print("Visualizer: Found butterchurn-presets.js at \(presetsURL)")
      } else {
        print("ERROR: butterchurn-presets.js NOT found in bundle")
      }
      
      webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
    
    context.coordinator.setupAudioTap(webView: webView)
    context.coordinator.parent = self // Link back to update AppStorage
    
    return webView
  }
  
  // UIViewRepresentable
  func updateUIView(_ uiView: WKWebView, context: Context) {
  }
  
  // UIViewRepresentable
  static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
    coordinator.stopAudioTap()
  }
  
  // UIViewRepresentable
  func makeCoordinator() -> Coordinator {
    Coordinator(synth: synth, initialPreset: lastPreset)
  }
  
  // UIViewRepresentable associated type
  class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let synth: SyntacticSynth
    weak var webView: WKWebView?
    var parent: VisualizerView?
    var initialPreset: String
    
    var pendingSamples: [Float] = []
    let sendThreshold = 1024 // Accumulate about 2 tap buffers before sending
    
    init(synth: SyntacticSynth, initialPreset: String) {
      self.synth = synth
      self.initialPreset = initialPreset
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "keyHandler", let dict = message.body as? [String: String],
         let key = dict["key"], let type = dict["type"] {
        playKey(key: key, type: type)
      } else if message.name == "presetHandler", let presetName = message.body as? String {
        // Save preset to AppStorage via parent
        DispatchQueue.main.async {
          self.parent?.lastPreset = presetName
        }
      } else if message.name == "closeViz" {
        self.parent?.dismiss()
      }
    }
    
    func playKey(key: String, type: String) {
      let charToMidiNote: [String: Int] = [
        "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67, "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75
      ]
      
      if let noteValue = charToMidiNote[key] {
        if type == "keydown" {
          synth.voicePool?.noteOn(MidiNote(note: UInt8(noteValue), velocity: 100))
        } else if type == "keyup" {
          synth.voicePool?.noteOff(MidiNote(note: UInt8(noteValue), velocity: 100))
        }
      }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      print("Visualizer webview finished loading index.html")
      // Inject the initial preset name safely using Base64
      if !initialPreset.isEmpty {
        if let data = initialPreset.data(using: .utf8) {
          let b64 = data.base64EncodedString()
          let script = "window.initialPresetNameB64 = '\(b64)';"
          webView.evaluateJavaScript(script, completionHandler: nil)
        }
      }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      print("Visualizer webview failed loading: \(error.localizedDescription)")
    }
    
    func setupAudioTap(webView: WKWebView) {
      self.webView = webView
      
      // provide this closure to the installTap method, which calls us back here with samples
      synth.engine.installTap { [weak self] samples in
        guard let self = self else { return }
        
        // Append to buffer
        // Data is Interleaved Stereo [L, R, L, R...]
        self.pendingSamples.append(contentsOf: samples)
        
        // Only send if we have enough data to make the bridge call worth it
        // Threshold 1024 floats = 512 stereo frames
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
