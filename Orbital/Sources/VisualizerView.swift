//
//  VisualizerView.swift
//  Orbital
//
//  Created by Greg Langmead on 1/20/26.
//

import SwiftUI
import WebKit
import os

// MARK: - VisualizerPageHolder

/// Owns a persistent WebPage instance so the WebGL context and Butterchurn
/// visualizer survive across show/hide cycles. All state that was previously
/// split between VisualizerHolder, VisualizerWebView, and WKScriptMessageHandler
/// now lives here.
@MainActor @Observable
class VisualizerPageHolder {
  let engine: SpatialAudioEngine
  let page: WebPage

  // Page / preset state
  var presetNames: [String] = []
  var currentPreset: String = ""
  var speed: Double = 1.0
  var isCycling: Bool = false
  private(set) var isPageLoaded: Bool = false

  // Audio tap state
  private let pendingSamples = OSAllocatedUnfairLock(initialState: [Float]())
  private let sendThreshold = 1024
  private var callbackInstalled = false
  private let sendingEnabled = OSAllocatedUnfairLock(initialState: false)

  // Cycle task
  private var cycleTask: Task<Void, Never>?

  init(engine: SpatialAudioEngine) {
    self.engine = engine

    var config = WebPage.Configuration()
    config.mediaPlaybackBehavior = .allowsInlinePlayback
    self.page = WebPage(configuration: config)
  }

  // MARK: Page loading

  func loadPageIfNeeded(presetName: String, speed: Double) {
    guard !isPageLoaded else { return }
    self.speed = speed

    guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
      #if DEBUG
      print("Visualizer: index.html not found in bundle")
      #endif
      return
    }

    let baseURL = indexURL.deletingLastPathComponent()

    #if DEBUG
    print("Visualizer: loading index.html from \(indexURL)")
    page.isInspectable = true
    #endif

    Task {
      do {
        let html = try String(contentsOf: indexURL, encoding: .utf8)
        for try await _ in page.load(html: html, baseURL: baseURL) {
          // Wait for navigation to complete
        }
        await onPageLoaded(savedPreset: presetName, savedSpeed: speed)
      } catch {
        #if DEBUG
        print("Visualizer: failed to load page: \(error.localizedDescription)")
        #endif
      }
    }
  }

  private func onPageLoaded(savedPreset: String, savedSpeed: Double) async {
    isPageLoaded = true

    // Suspend the Web AudioContext — we inject waveform data directly via
    // pushSamples, so the web audio pipeline is unnecessary.
    _ = try? await page.callJavaScript("""
      if (window.audioContext) {
        window.audioContext.suspend();
        window.audioContext.resume = function() { return Promise.resolve(); };
      }
      """)

    // Fetch the preset name list from JS
    if let names = try? await page.callJavaScript(
      "return window.getPresetNames()") as? [String] {
      presetNames = names
    }

    // Inject saved preset, or discover the one Butterchurn picked
    if !savedPreset.isEmpty, presetNames.contains(savedPreset) {
      _ = try? await page.callJavaScript(
        "window.loadPresetByName(n)",
        arguments: ["n": savedPreset])
      currentPreset = savedPreset
    } else if let name = try? await page.callJavaScript(
      "return window.getCurrentPreset()") as? String, !name.isEmpty {
      currentPreset = name
    }

    // Inject saved speed
    _ = try? await page.callJavaScript(
      "window.setSpeed(s)",
      arguments: ["s": savedSpeed])

    #if DEBUG
    print("Visualizer: page loaded, \(presetNames.count) presets available")
    #endif
  }

  // MARK: JS calls

  func setSpeed(_ newSpeed: Double) {
    speed = newSpeed
    guard isPageLoaded else { return }
    Task {
      _ = try? await page.callJavaScript(
        "window.setSpeed(s)",
        arguments: ["s": newSpeed])
    }
  }

  func loadPreset(_ name: String) {
    currentPreset = name
    guard isPageLoaded else { return }
    Task {
      _ = try? await page.callJavaScript(
        "window.loadPresetByName(n)",
        arguments: ["n": name])
    }
  }

  func randomPreset() {
    guard !presetNames.isEmpty else { return }
    let name = presetNames.randomElement()!
    loadPreset(name)
  }

  // MARK: Cycling

  func startCycling() {
    isCycling = true
    cycleTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled else { break }
        randomPreset()
      }
    }
  }

  func stopCycling() {
    isCycling = false
    cycleTask?.cancel()
    cycleTask = nil
  }

  // MARK: Audio tap

  func installTapIfNeeded() {
    guard isPageLoaded else { return }

    Task {
      _ = try? await page.callJavaScript("if (window.resumeAudio) window.resumeAudio()")
    }
    sendingEnabled.withLock { $0 = true }

    guard !callbackInstalled else { return }
    callbackInstalled = true

    // The audio tap was already installed during engine.start(). We only
    // set the callback here so we don't reconfigure the audio graph.
    engine.setTapCallback { [weak self] samples in
      guard let self, self.sendingEnabled.withLock({ $0 }) else { return }

      let samplesToSend: [Float]? = self.pendingSamples.withLock { pending in
        pending.append(contentsOf: samples)
        guard pending.count >= self.sendThreshold else { return nil }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        return batch
      }

      if let samplesToSend {
        let jsonString = samplesToSend.description
        Task { @MainActor in
          _ = try? await self.page.callJavaScript(
            "if (window.pushSamples) window.pushSamples(JSON.parse(s))",
            arguments: ["s": jsonString])
        }
      }
    }
  }

  func removeTap() {
    sendingEnabled.withLock { $0 = false }
  }
}

// MARK: - VisualizerView

struct VisualizerView: View {
  var engine: SpatialAudioEngine
  @Binding var isPresented: Bool

  @AppStorage("lastVisualizerPreset") private var lastPreset: String = ""
  @AppStorage("lastVisualizerSpeed") private var lastSpeed: Double = 1.0
  @State private var controlsVisible = true
  @State private var holder: VisualizerPageHolder?

  /// Single persistent holder — survives show/hide cycles.
  private static var persistentHolder: VisualizerPageHolder?

  private func getOrCreateHolder() -> VisualizerPageHolder {
    if let existing = Self.persistentHolder, existing.engine === engine {
      return existing
    }
    let h = VisualizerPageHolder(engine: engine)
    Self.persistentHolder = h
    return h
  }

  var body: some View {
    ZStack {
      if let holder {
        WebView(holder.page)
          .ignoresSafeArea()

        // Tap anywhere on the web view to toggle controls
        Color.clear
          .contentShape(.rect)
          .onTapGesture {
            withAnimation { controlsVisible.toggle() }
          }

        if controlsVisible {
          VStack {
            Spacer()
            VisualizerControlsView(
              holder: holder,
              controlsVisible: $controlsVisible,
              isPresented: $isPresented,
              lastPreset: $lastPreset,
              lastSpeed: $lastSpeed
            )
          }
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
    }
    .onAppear {
      let h = getOrCreateHolder()
      holder = h
      h.loadPageIfNeeded(presetName: lastPreset, speed: lastSpeed)
      h.installTapIfNeeded()
      h.setSpeed(lastSpeed)
    }
    .onChange(of: isPresented) {
      guard let holder else { return }
      if isPresented {
        holder.installTapIfNeeded()
      } else {
        holder.removeTap()
        holder.stopCycling()
      }
    }
    .onKeyPress(.escape) {
      withAnimation(.easeInOut(duration: 0.4)) {
        isPresented = false
      }
      return .handled
    }
  }
}

// MARK: - VisualizerControlsView

struct VisualizerControlsView: View {
  var holder: VisualizerPageHolder
  @Binding var controlsVisible: Bool
  @Binding var isPresented: Bool
  @Binding var lastPreset: String
  @Binding var lastSpeed: Double

  @State private var showingPresetList = false
  @State private var speed: Double = 1.0

  var body: some View {
    VStack(spacing: 12) {
      // Preset button
      Button {
        showingPresetList = true
      } label: {
        Text(holder.currentPreset.isEmpty ? "Presets" : holder.currentPreset)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.bordered)

      // Speed slider
      HStack {
        Text(String(format: "Speed %.1f%%", speed * 100))
          .monospacedDigit()
        Slider(value: $speed, in: 0.0...1.0, step: 0.05)
          .onChange(of: speed) {
            holder.setSpeed(speed)
            lastSpeed = speed
          }
      }

      // Action buttons
      HStack {
        Button("Random", systemImage: "shuffle") {
          holder.randomPreset()
          lastPreset = holder.currentPreset
        }

        Button(
          holder.isCycling ? "Stop Cycle" : "Cycle",
          systemImage: holder.isCycling ? "stop.circle" : "arrow.trianglehead.2.clockwise.rotate.90"
        ) {
          if holder.isCycling {
            holder.stopCycling()
          } else {
            holder.startCycling()
          }
        }

        Spacer()

        Button("Hide", systemImage: "eye.slash") {
          withAnimation { controlsVisible = false }
        }

        Button("Close", systemImage: "xmark") {
          withAnimation(.easeInOut(duration: 0.4)) {
            isPresented = false
          }
        }
      }
      Text("Visualizations by Milkdrop by Ryan Geiss,\nvia Butterchurn by Jordan Berg,\nvia https://github.com/pxl-pshr/butterchurn-ios")
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
    }
    .padding()
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
    .padding()
    .onAppear {
      speed = lastSpeed
    }
    .sheet(isPresented: $showingPresetList) {
      VisualizerPresetListView(
        holder: holder,
        lastPreset: $lastPreset,
        isPresented: $showingPresetList
      )
    }
  }
}

// MARK: - VisualizerPresetListView

struct VisualizerPresetListView: View {
  var holder: VisualizerPageHolder
  @Binding var lastPreset: String
  @Binding var isPresented: Bool

  @State private var searchText = ""

  private var filteredPresets: [String] {
    if searchText.isEmpty {
      return holder.presetNames
    }
    return holder.presetNames.filter {
      $0.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List(filteredPresets, id: \.self) { name in
          Button {
            holder.loadPreset(name)
            lastPreset = name
            isPresented = false
          } label: {
            HStack {
              Text(name)
              Spacer()
              if name == holder.currentPreset {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
          }
          .id(name)
        }
        .searchable(text: $searchText, prompt: "Filter presets")
        .navigationTitle("Presets")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
              isPresented = false
            }
          }
        }
        .onAppear {
          if !holder.currentPreset.isEmpty {
            proxy.scrollTo(holder.currentPreset, anchor: .center)
          }
        }
      }
    }
  }
}

#Preview {
  @Previewable @State var controlsVisible = true
  @Previewable @State var isPresented = true
  @Previewable @State var lastPreset = "foo"
  @Previewable @State var lastSpeed = 1.0
  VisualizerControlsView(
    holder: VisualizerPageHolder(engine: SpatialAudioEngine()),
    controlsVisible: $controlsVisible,
    isPresented: $isPresented,
    lastPreset: $lastPreset,
    lastSpeed: $lastSpeed
  )
}
