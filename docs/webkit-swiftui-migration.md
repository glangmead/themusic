# WebKit for SwiftUI: Migration Plan for Butterchurn Visualizer

## Summary

iOS 26 introduces `WebView` (a native SwiftUI view) and `WebPage` (an `@Observable` class) as first-class replacements for the `UIViewRepresentable` + `WKWebView` pattern. This report evaluates how to migrate `VisualizerView.swift` and what new capabilities become available.

## Current Architecture

`VisualizerView` is a `UIViewRepresentable` wrapping a custom `VisualizerWebView` (subclass of `WKWebView`). It hosts `index.html`, which bundles the Butterchurn WebGL visualizer and all its preset data in a single 3.6 MB file.

### Current Communication Channels

| Direction | Mechanism | Usage |
|---|---|---|
| Swift -> JS | `evaluateJavaScript()` | `pushSamples()`, `setSpeed()`, `resumeAudio()`, safe-area injection |
| Swift -> JS | `WKUserScript` at document start | `window.initialPresetNameB64`, `window.initialSpeed` |
| JS -> Swift | `window.webkit.messageHandlers.presetHandler.postMessage()` | Preset name changed |
| JS -> Swift | `window.webkit.messageHandlers.speedHandler.postMessage()` | Speed slider moved |
| JS -> Swift | `window.webkit.messageHandlers.closeViz.postMessage()` | Close button tapped |
| JS -> Swift | `window.webkit.messageHandlers.keyHandler.postMessage()` | Keyboard notes (a-p) |

### Current UI Controls (rendered in HTML)

1. **Preset menu button** (`#presetMenuBtn`) — opens a scrollable overlay listing all presets
2. **Speed slider** (`#speedSlider`) — range 0.1..1.0, step 0.05
3. **Random button** (`#randomBtn`) — picks a random preset
4. **Cycle button** (`#cycleBtn`) — auto-cycles through presets on a timer
5. **Hide button** (`#hideBtn`) — hides the controls overlay, leaving just the canvas
6. **Close button** (`#closeBtn`) — sends `closeViz` message to dismiss the visualizer

### Current Persistence

- `@AppStorage("lastVisualizerPreset")` — remembers the preset name
- `@AppStorage("lastVisualizerSpeed")` — remembers the speed value

These are injected into the page at load time via `WKUserScript` and kept in sync via the `presetHandler` and `speedHandler` message handlers.

---

## New API: WebView and WebPage (iOS 26+)

### WebView

A native SwiftUI `View`. Minimal usage:

```swift
import WebKit

WebView(url: URL(string: "https://example.com"))
```

Or bound to a `WebPage` instance for full control:

```swift
WebView(page)
```

View modifiers include `.webViewBackForwardNavigationGestures()`, `.webViewMagnificationGestures()`, `.webViewLinkPreviews()`, `.webViewScrollPosition()`, `.findNavigator()`.

### WebPage

An `@Observable` class. Observable properties include `title`, `url`, `estimatedProgress`, `themeColor`, `currentNavigationEvent`, and more. These drive SwiftUI updates automatically.

Configuration is done via `WebPage.Configuration`:

```swift
let config = WebPage.Configuration()
config.urlSchemeHandlers[scheme] = handler
config.mediaPlaybackBehavior = ...
config.allowsAirPlayForMediaPlayback = ...
let page = WebPage(configuration: config)
```

### JavaScript Communication

**Swift -> JS** uses async/await:

```swift
let result = try await page.callJavaScript("document.title")

// With arguments (keys become JS local variables):
try await page.callJavaScript(
  "window.setSpeed(speed)",
  arguments: ["speed": 0.5]
)
```

**JS -> Swift** uses a `messageHandler` closure on `WebView`:

```swift
WebView(html: html, messageHandler: { message in
  // message is the JS value passed from postMessage
})
```

The exact details of the JS -> Swift bridge are still emerging in the beta documentation. It may still use `window.webkit.messageHandlers` on the JS side, or there may be a new protocol. The WWDC session and beta headers should be consulted when implementation begins.

### Loading Local Files

The old `loadFileURL(_:allowingReadAccessTo:)` is replaced by `URLSchemeHandler`:

```swift
let scheme = URLScheme("visualizer")!
let handler = VisualizerSchemeHandler()
config.urlSchemeHandlers[scheme] = handler
```

The handler conforms to `URLSchemeHandler` and returns an `AsyncSequence` of response data.

### NavigationDeciding

A protocol for controlling whether navigations are allowed. Not directly relevant to our use case since the visualizer page does not navigate.

---

## Migration Assessment

### What Maps Directly

| Current | New Equivalent | Notes |
|---|---|---|
| `UIViewRepresentable` wrapping `WKWebView` | `WebView(page)` | Eliminates ~80 lines of coordinator/representable boilerplate |
| `evaluateJavaScript("if(window.pushSamples)...")` | `try await page.callJavaScript("window.pushSamples(samples)", arguments: ["samples": jsonString])` | Async/await, type-safe arguments |
| `WKUserScript` injection at document start | `try await page.callJavaScript(...)` after load, or a custom `URLSchemeHandler` that injects config | The `callJavaScript` arguments dict is cleaner than base64-encoding preset names |
| `WKScriptMessageHandler` for 4 message handlers | `messageHandler` closure on `WebView`, or polling via `callJavaScript` | Needs beta testing to confirm full parity |
| `WKWebViewConfiguration` media settings | `WebPage.Configuration.mediaPlaybackBehavior` | Direct equivalent exists |
| `loadFileURL` for local `index.html` | `URLSchemeHandler` returning bundle data | More work upfront, but cleaner |

### What Requires Careful Handling

1. **Audio tap throughput.** We call `pushSamples` ~44 times/second with 1024-sample batches. `callJavaScript` is async/await, which is fine for the main actor, but we need to confirm the overhead of the new bridge is not worse than the raw `evaluateJavaScript` fire-and-forget. The current code dispatches to `DispatchQueue.main` and does not await a result — the new API should be called the same way (fire-and-forget via `Task`).

2. **WebGL context survival.** The current architecture uses a persistent `VisualizerHolder` to keep the `WKWebView` alive across show/hide cycles, avoiding WebGL context exhaustion. With the new `WebPage`, we would similarly need to keep the `WebPage` instance alive as a static or externally-owned reference. `WebPage` is `@Observable`, so it could live in an `@Observable` model class.

3. **Safe area override.** The current `VisualizerWebView` subclass overrides `safeAreaInsets` to return `.zero` so the canvas fills the entire screen. There is no documented equivalent on `WebView`. We may need to use `.ignoresSafeArea()` on the SwiftUI `WebView`, but it is unknown whether this propagates into the web content's `env(safe-area-inset-top)` CSS value. The current workaround (injecting the real top inset via JS) would still work.

4. **Escape key handling.** The current subclass overrides `keyCommands` to catch the Escape key. With SwiftUI `WebView`, we would use `.onKeyPress(.escape) { ... }` on the enclosing view.

5. **`isInspectable`.** The current code sets `wv.isInspectable = true` for debug builds. Unknown whether `WebPage.Configuration` exposes this.

6. **JS -> Swift message handler parity.** We currently use 4 named message handlers (`keyHandler`, `presetHandler`, `speedHandler`, `closeViz`). The new `messageHandler` closure on `WebView` appears to be a single handler. The JS side would need to send structured messages with a `type` field, and the Swift side would dispatch by type. Alternatively, the new API may support multiple named handlers — this needs beta verification.

---

## New Capability: Native SwiftUI Controls

The most interesting opportunity is replacing the 6 HTML controls with native SwiftUI views. The butterchurn canvas stays in `WebView`, but the controls overlay becomes pure SwiftUI layered on top.

### Benefits

- **Native look and feel.** SwiftUI `Slider`, `Button`, `Menu` automatically adapt to Dynamic Type, dark mode, accessibility features, and the iOS design language.
- **No safe-area hacks.** SwiftUI views respect safe areas natively. The preset overlay title would not need JS-injected top padding.
- **Simpler state management.** `@AppStorage` values drive both SwiftUI controls and JS calls directly, with no message-handler round trips.
- **Haptic feedback.** Buttons and slider can use `.sensoryFeedback()`.
- **Better preset list.** A SwiftUI `List` or `ScrollView` with `LazyVStack` and `.searchable()` replaces the HTML preset overlay, giving native pull-to-scroll, momentum scrolling, and a search bar for filtering presets by name (using `localizedStandardContains`).
- **Accessibility.** All native controls get VoiceOver support for free.

### Proposed Layout

```
ZStack {
  // Full-bleed butterchurn canvas
  WebView(page)
    .ignoresSafeArea()

  // Native SwiftUI overlay (conditionally shown)
  VStack {
    Spacer()
    controlsOverlay
  }
}
```

Where `controlsOverlay` contains:

1. **Preset button** — a SwiftUI `Button` that presents a `.sheet` containing a searchable `List` of preset names. Tapping a preset calls `page.callJavaScript("loadPreset(name)", arguments: ["name": presetName])`.
2. **Speed slider** — a SwiftUI `Slider(value: $speed, in: 0.1...1.0, step: 0.05)` that calls `page.callJavaScript("window.setSpeed(s)", arguments: ["s": speed])` via `.onChange(of: speed)`.
3. **Random button** — a SwiftUI `Button` that calls `page.callJavaScript("loadRandomPreset()")`.
4. **Cycle toggle** — a SwiftUI `Toggle` or `Button` with an `.active` state that calls `page.callJavaScript("toggleCycle()")`.
5. **Hide button** — a SwiftUI `Button` toggling a `@State var controlsVisible` bool with animation.
6. **Close button** — a SwiftUI `Button` that sets `isPresented = false`.

### What Changes in index.html

- Remove the entire `<div class="controls">` block and its CSS.
- Remove the `<div class="preset-overlay">` block and its CSS.
- Remove the `speedHandler`, `closeViz` message handlers (Swift controls handle these directly).
- Keep `presetHandler` for cases where Butterchurn itself changes the preset (e.g., during auto-cycle), or rework cycle logic to live entirely in Swift.
- Keep `pushSamples`, `setSpeed`, `resumeAudio`, and add a `loadPresetByName(name)` function callable from Swift.
- Expose the preset name list to Swift: add a `window.getPresetNames()` function returning `Object.keys(presets)` so the SwiftUI list can be populated at load time.

### What Stays in index.html

- The `<canvas>` element and all WebGL/Butterchurn rendering logic.
- The `pushSamples` / `resumeAudio` audio injection functions.
- The `setSpeed` function.
- All preset data and the Butterchurn library code.

---

## Migration Phases

### Phase 0: Minimum viable (no behavior change)

Replace `UIViewRepresentable` with `WebView(page)`. Keep all HTML controls. Confirm WebGL works, audio tap works, preferences round-trip. This is a pure plumbing change.

**Risk:** JS -> Swift messaging parity. If the new `messageHandler` API does not support the 4 named handlers, we may need to restructure the JS to send typed messages through a single channel.

### Phase 1: Native controls overlay

Add SwiftUI controls on top of the `WebView`. Remove HTML controls from `index.html`. The preset list becomes a SwiftUI sheet with search. Speed slider becomes native. Close/hide/random/cycle become native buttons.

**Prerequisite:** Expose `getPresetNames()` from JS so Swift can populate the list.

### Phase 2: Simplify audio bridge

Evaluate whether `callJavaScript` with arguments is faster or slower than the current `evaluateJavaScript` string-interpolation approach for the high-frequency `pushSamples` path. If slower, keep the current approach or investigate passing typed arrays.

---

## Open Questions for Beta Testing

1. Does `WebView` support `.ignoresSafeArea()` propagating to full-bleed WebGL canvas?
2. Does `WebPage` expose `isInspectable` or equivalent for debug builds?
3. What is the exact JS -> Swift messaging API? Is it `window.webkit.messageHandlers` or something new?
4. Can `WebPage` load a local file from the bundle, or is `URLSchemeHandler` the only path?
5. What is the overhead of `callJavaScript` vs `evaluateJavaScript` for high-frequency calls (~44/sec)?
6. Does the `WebPage` instance survive when the `WebView` is removed from the view hierarchy (for our show/hide pattern)?
7. Does `WebPage.Configuration` expose `mediaTypesRequiringUserActionForPlayback` equivalent?

---

## Sources

- [Meet WebKit for SwiftUI — WWDC25 Session 231](https://developer.apple.com/videos/play/wwdc2025/231/)
- [WebKit for SwiftUI — Apple Developer Documentation](https://developer.apple.com/documentation/webkit/webkit-for-swiftui)
- [WebView struct — Apple Developer Documentation](https://developer.apple.com/documentation/webkit/webview-swift.struct)
- [callJavaScript(_:arguments:in:contentWorld:) — Apple Developer Documentation](https://developer.apple.com/documentation/webkit/webpage/calljavascript(_:arguments:in:contentworld:))
- [News from WWDC25: WebKit in Safari 26 beta — WebKit Blog](https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/)
- [Exploring WebView and WebPage in SwiftUI — AppCoda](https://www.appcoda.com/swiftui-webview/)
- [SwiftUI Custom URL Schemes — Use Your Loaf](https://useyourloaf.com/blog/swiftui-custom-url-schemes/)
- [Apple Developer Forums — WebKit](https://developer.apple.com/forums/tags/webkit/?sortBy=newest)
