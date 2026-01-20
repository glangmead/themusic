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
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        
        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
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
    
    class Coordinator {
        let synth: SyntacticSynth
        weak var webView: WKWebView?
        
        var pendingSamples: [Float] = []
        let sendThreshold = 2048 // Accumulate about 2 tap buffers before sending
        
        init(synth: SyntacticSynth) {
            self.synth = synth
        }
        
        func setupAudioTap(webView: WKWebView) {
            self.webView = webView
            
            synth.engine.installTap { [weak self] samples in
                guard let self = self else { return }
                
                // Append to buffer
                self.pendingSamples.append(contentsOf: samples)
                
                // Only send if we have enough data to make the bridge call worth it
                if self.pendingSamples.count >= self.sendThreshold {
                    let samplesToSend = self.pendingSamples
                    self.pendingSamples.removeAll(keepingCapacity: true)
                    
                    // Debug: Calculate amplitude of what we are sending
                    var total: Float = 0
                    for sample in samplesToSend {
                        total += abs(sample)
                    }
                    let avg = total / Float(samplesToSend.count)
                    if avg > 0.001 {
                        // print("Visualizer sending \(samplesToSend.count) samples. Avg Amp: \(avg)")
                    }
                    
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
