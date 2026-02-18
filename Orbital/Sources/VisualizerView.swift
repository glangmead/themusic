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
// The JS files are inlined into index.html to avoid cross-origin issues in WKWebView.
class VisualizerWebView: WKWebView {
  var onEscape: (() -> Void)?
  var onDidMoveToWindow: (() -> Void)?

  // Force the web view to ignore safe area insets so it fills the entire screen
  override var safeAreaInsets: UIEdgeInsets { .zero }

  // Hide the input accessory view (the bar above the keyboard)
  override var inputAccessoryView: UIView? {
    return nil
  }
  
  override var canBecomeFirstResponder: Bool {
    return true // Needs to be true to receive key events
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
      onDidMoveToWindow?()
    }
  }
}

/// Holds a single persistent WKWebView instance so the WebGL context and Butterchurn
/// visualizer survive across show/hide cycles. Recreating WKWebView each time causes
/// WebGL context exhaustion on iOS.
class VisualizerHolder: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  let engine: SpatialAudioEngine
  var noteHandler: NoteHandler?
  private(set) var webView: VisualizerWebView!
  private var isLoaded = false
  
  // Audio tap state
  private var pendingSamples: [Float] = []
  private let sendThreshold = 1024
  private let samplesLock = OSAllocatedUnfairLock()
  private var callbackInstalled = false
  private let sendingEnabled = OSAllocatedUnfairLock(initialState: false)
  
  // Callbacks wired by the SwiftUI layer
  var onPresetChange: ((String) -> Void)?
  var onSpeedChange: ((Double) -> Void)?
  var onCloseRequested: (() -> Void)?
  
  init(engine: SpatialAudioEngine, noteHandler: NoteHandler? = nil) {
    self.engine = engine
    self.noteHandler = noteHandler
    super.init()
    
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = []
    config.allowsInlineMediaPlayback = true
    
    let ucc = WKUserContentController()
    ucc.add(self, name: "keyHandler")
    ucc.add(self, name: "presetHandler")
    ucc.add(self, name: "closeViz")
    ucc.add(self, name: "speedHandler")
    config.userContentController = ucc
    
    let wv = VisualizerWebView(frame: .zero, configuration: config)
    wv.scrollView.contentInsetAdjustmentBehavior = .never
    wv.scrollView.isScrollEnabled = false
    wv.scrollView.backgroundColor = .clear
    wv.isOpaque = false
    wv.underPageBackgroundColor = .black
    if #available(iOS 16.4, macOS 13.3, *) {
      wv.isInspectable = true
    }
    wv.backgroundColor = .black
    wv.navigationDelegate = self
    wv.onEscape = { [weak self] in self?.onCloseRequested?() }
    wv.onDidMoveToWindow = { [weak self] in self?.injectSafeAreaTop() }
    
    self.webView = wv
    loadPage()
  }
  
  /// Inject the saved preset/speed and load index.html (only done once).
  func loadPage(presetName: String = "", speed: Double = 1.0) {
    guard !isLoaded else { return }
    
    var initJS = ""
    if !presetName.isEmpty, let data = presetName.data(using: .utf8) {
      let b64 = data.base64EncodedString()
      initJS += "window.initialPresetNameB64 = '\(b64)';\n"
    }
    initJS += "window.initialSpeed = \(speed);"
    
    let script = WKUserScript(
      source: initJS,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
    )
    webView.configuration.userContentController.addUserScript(script)
    
    if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
      #if DEBUG
      print("Visualizer: loading index.html from \(indexURL)")
      #endif
      webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
  }
  
  /// Update speed on an already-loaded page.
  func setSpeed(_ speed: Double) {
    webView.evaluateJavaScript("if(window.setSpeed) window.setSpeed(\(speed))", completionHandler: nil)
  }
  
  /// Inject the real safe-area-inset-top so the preset overlay can avoid the status bar.
  /// (Our WKWebView subclass returns .zero for safeAreaInsets so the canvas fills the screen,
  /// which means env(safe-area-inset-top) is always 0 in CSS.)
  func injectSafeAreaTop() {
    let window = webView.window ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first
    let top = window?.safeAreaInsets.top ?? 0
    
    let js = """
    (function() {
      var el = document.getElementById('presetOverlay');
      if (el) { el.style.top = '\(Int(top))px'; }
      window._safeAreaTop = \(Int(top));
    })()
    """
    webView.evaluateJavaScript(js, completionHandler: nil)
  }
  
  func installTapIfNeeded() {
    webView.evaluateJavaScript("if(window.resumeAudio) window.resumeAudio()", completionHandler: nil)
    sendingEnabled.withLock { $0 = true }
    injectSafeAreaTop()
    
    guard !callbackInstalled else { return }
    callbackInstalled = true
    
    // Set the tap callback on the engine. The actual audio tap was already
    // installed during engine.start(), so this won't reconfigure the audio
    // graph and won't cause a glitch. We gate JS calls with sendingEnabled
    // so we don't waste CPU while hidden.
    engine.setTapCallback { [weak self] samples in
      guard let self = self, self.sendingEnabled.withLock({ $0 }) else { return }
      
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
          self.webView.evaluateJavaScript("if(window.pushSamples) window.pushSamples(\(jsonString))", completionHandler: nil)
        }
      }
    }
  }
  
  func removeTap() {
    sendingEnabled.withLock { $0 = false }
  }
  
  // MARK: - WKNavigationDelegate
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isLoaded = true
    injectSafeAreaTop()
    
    // Suspend the Web AudioContext that Butterchurn creates and disable the
    // watchdog that would resume it. The visualizer doesn't need Web Audio —
    // waveform data is injected directly via pushSamples(). This saves
    // resources and avoids any audio session interference.
    let suspendJS = """
    (function() {
      if (window.audioContext) {
        window.audioContext.suspend();
        window.audioContext.resume = function() { return Promise.resolve(); };
      }
    })()
    """
    webView.evaluateJavaScript(suspendJS, completionHandler: nil)
    
    #if DEBUG
    print("Visualizer webview finished loading index.html")
    #endif
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    #if DEBUG
    print("Visualizer webview failed navigation: \(error.localizedDescription)")
    #endif
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    #if DEBUG
    print("Visualizer webview failed provisional navigation: \(error.localizedDescription)")
    #endif
  }
  
  // MARK: - WKScriptMessageHandler
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    if message.name == "keyHandler", let dict = message.body as? [String: String],
       let key = dict["key"], let type = dict["type"] {
      playKey(key: key, type: type)
    } else if message.name == "presetHandler", let presetName = message.body as? String {
      onPresetChange?(presetName)
    } else if message.name == "speedHandler", let speed = message.body as? Double {
      onSpeedChange?(speed)
    } else if message.name == "closeViz" {
      DispatchQueue.main.async { self.onCloseRequested?() }
    }
  }
  
  private func playKey(key: String, type: String) {
    let charToMidiNote: [String: Int] = [
      "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67, "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75
    ]
    if let noteValue = charToMidiNote[key] {
      if type == "keydown" {
        noteHandler?.noteOn(MidiNote(note: UInt8(noteValue), velocity: 100))
      } else if type == "keyup" {
        noteHandler?.noteOff(MidiNote(note: UInt8(noteValue), velocity: 100))
      }
    }
  }
}

struct VisualizerView: UIViewRepresentable {
  typealias UIViewType = VisualizerWebView
  
  var engine: SpatialAudioEngine
  var noteHandler: NoteHandler?
  @Binding var isPresented: Bool
  @AppStorage("lastVisualizerPreset") private var lastPreset: String = ""
  @AppStorage("lastVisualizerSpeed") private var lastSpeed: Double = 1.0
  
  /// Single persistent holder - survives fullScreenCover dismiss/re-present cycles.
  private static var persistentHolder: VisualizerHolder?
  
  private func getOrCreateHolder() -> VisualizerHolder {
    if let existing = Self.persistentHolder, existing.engine === engine {
      existing.noteHandler = noteHandler
      return existing
    }
    // Engine changed or first use — create fresh holder
    let h = VisualizerHolder(engine: engine, noteHandler: noteHandler)
    h.loadPage(presetName: lastPreset, speed: lastSpeed)
    Self.persistentHolder = h
    return h
  }
  
  func makeUIView(context: Context) -> VisualizerWebView {
    let h = getOrCreateHolder()
    context.coordinator.holder = h
    
    h.onPresetChange = { [self] name in
      DispatchQueue.main.async { self.lastPreset = name }
    }
    h.onSpeedChange = { [self] speed in
      DispatchQueue.main.async { self.lastSpeed = speed }
    }
    h.onCloseRequested = { [self] in
      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: 0.4)) {
          self.isPresented = false
        }
      }
    }
    
    // Don't install the tap here — updateUIView will handle it when
    // isPresented becomes true. This avoids doing work at app startup.
    return h.webView
  }
  
  func updateUIView(_ uiView: VisualizerWebView, context: Context) {
    let h = context.coordinator.holder
    h?.onPresetChange = { [self] name in
      DispatchQueue.main.async { self.lastPreset = name }
    }
    h?.onSpeedChange = { [self] speed in
      DispatchQueue.main.async { self.lastSpeed = speed }
    }
    h?.onCloseRequested = { [self] in
      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: 0.4)) {
          self.isPresented = false
        }
      }
    }
    
    // Toggle the audio tap based on visibility.
    if isPresented {
      h?.installTapIfNeeded()
      h?.setSpeed(lastSpeed)
    } else {
      h?.removeTap()
    }
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }
  
  class Coordinator {
    var holder: VisualizerHolder?
  }
}
