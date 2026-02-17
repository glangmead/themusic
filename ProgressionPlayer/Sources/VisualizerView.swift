//
//  VisualizerView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/20/26.
//

import SwiftUI
import WebKit
import UIKit
import os

// Host a web view that displays the Butterchurn-ios visualizer.
// The visualizer index.html is modified from https://github.com/pxl-pshr/butterchurn-ios
// The two .js files it imported were copied from the CDN into the app bundle:
// https://cdn.jsdelivr.net/npm/butterchurn@3.0.0-beta.5/dist/butterchurn.min.js
// https://cdn.jsdelivr.net/npm/butterchurn-presets@3.0.0-beta.4/dist/all.min.js
// (which are the 3.0 versions, whereas butterchurn-ios was made with v2 in mind)
class VisualizerWebView: WKWebView {
  var onEscape: (() -> Void)?

  // Hide the input accessory view (the bar above the keyboard)
  override var inputAccessoryView: UIView? {
    return nil
  }
  
  // Also try to prevent it from becoming first responder if that's the issue
  override var canBecomeFirstResponder: Bool {
    return true // Needs to be true to receive key events, but we want to suppress the UI
  }
  
  override var keyCommands: [UIKeyCommand]? {
    return [
      UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
    ]
  }
  
  @objc func escapePressed() {
    onEscape?()
  }
  
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      let success = becomeFirstResponder()
      #if DEBUG
      if !success {
        print("VisualizerWebView: Could not become first responder")
      }
      #endif
    }
  }
}

struct VisualizerView: UIViewRepresentable {
  typealias UIViewType = VisualizerWebView
  
  var synth: SyntacticSynth
  @Binding var isPresented: Bool
  @AppStorage("lastVisualizerPreset") private var lastPreset: String = ""
  
  func makeUIView(context: Context) -> VisualizerWebView {
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = []
    config.allowsInlineMediaPlayback = true
    
    let userContentController = WKUserContentController()
    userContentController.add(context.coordinator, name: "keyHandler")
    userContentController.add(context.coordinator, name: "presetHandler")
    userContentController.add(context.coordinator, name: "closeViz")
    
    // Inject saved preset name before any scripts run to avoid race condition
    if !lastPreset.isEmpty, let data = lastPreset.data(using: .utf8) {
      let b64 = data.base64EncodedString()
      let script = WKUserScript(
        source: "window.initialPresetNameB64 = '\(b64)';",
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
      )
      userContentController.addUserScript(script)
    }
    
    config.userContentController = userContentController
    
    let webView = VisualizerWebView(frame: .zero, configuration: config)
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.scrollView.isScrollEnabled = false
    webView.isOpaque = false
    if #available(iOS 16.4, macOS 13.3, *) {
      webView.isInspectable = true
    }
    webView.backgroundColor = .black
    webView.navigationDelegate = context.coordinator
    
    // Wire up the Escape key handler for iPad/Catalyst
    let coordinator = context.coordinator
    webView.onEscape = { [weak coordinator] in
      coordinator?.handleEscape()
    }
    
    if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
      #if DEBUG
      print("Visualizer: loading index.html from \(indexURL)")
      #endif
      webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
    
    context.coordinator.setupAudioTap(webView: webView)
    context.coordinator.parent = self // Link back to update AppStorage
    
    return webView
  }
  
  // UIViewRepresentable
  func updateUIView(_ uiView: VisualizerWebView, context: Context) {
    context.coordinator.parent = self
  }
  
  // UIViewRepresentable
  static func dismantleUIView(_ uiView: VisualizerWebView, coordinator: Coordinator) {
    coordinator.stopAudioTap()
    uiView.configuration.userContentController.removeAllScriptMessageHandlers()
  }
  
  // UIViewRepresentable
  func makeCoordinator() -> Coordinator {
    Coordinator(synth: synth)
  }
  
  // UIViewRepresentable associated type
  class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let synth: SyntacticSynth
    weak var webView: WKWebView?
    var parent: VisualizerView?
    
    var pendingSamples: [Float] = []
    let sendThreshold = 1024 // Accumulate about 2 tap buffers before sending
    private let samplesLock = OSAllocatedUnfairLock()
    
    init(synth: SyntacticSynth) {
      self.synth = synth
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
        DispatchQueue.main.async {
          withAnimation(.easeInOut(duration: 0.4)) {
            self.parent?.isPresented = false
          }
        }
      }
    }
    
    func playKey(key: String, type: String) {
      let charToMidiNote: [String: Int] = [
        "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67, "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75
      ]
      
      if let noteValue = charToMidiNote[key] {
        if type == "keydown" {
          synth.noteHandler?.noteOn(MidiNote(note: UInt8(noteValue), velocity: 100))
        } else if type == "keyup" {
          synth.noteHandler?.noteOff(MidiNote(note: UInt8(noteValue), velocity: 100))
        }
      }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      #if DEBUG
      print("Visualizer webview finished loading index.html")
      #endif
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      #if DEBUG
      print("Visualizer webview failed loading: \(error.localizedDescription)")
      #endif
    }
    
    func setupAudioTap(webView: WKWebView) {
      self.webView = webView
      
      // provide this closure to the installTap method, which calls us back here with samples
      synth.engine.installTap { [weak self] samples in
        guard let self = self else { return }
        
        let samplesToSend: [Float]? = self.samplesLock.withLock {
          self.pendingSamples.append(contentsOf: samples)
          guard self.pendingSamples.count >= self.sendThreshold else { return nil }
          let batch = self.pendingSamples
          self.pendingSamples.removeAll(keepingCapacity: true)
          return batch
        }
        
        if let samplesToSend {
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
    
    func handleEscape() {
      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: 0.4)) {
          self.parent?.isPresented = false
        }
      }
    }
  }
}
