# VisualizerView Analysis

**Analysis performed on 2026-02-15.** Files examined:

- `Sources/VisualizerView.swift` (all code: VisualizerWarmer, VisualizerWebView, VisualizerView)
- `Sources/SongView.swift` (embedding site)
- `Sources/AppView.swift` (warmup call site)
- `Resources/index.html` (Butterchurn visualizer page)
- `Sources/AppleAudio/SpatialAudioEngine.swift` (audio tap)

---

## Issue 1: Fullscreen Safe Area -- "Chin/Forehead" Problem on iPhone

### Problem

On iPhones with a notch or Dynamic Island, the visualizer will show visible gaps at the top and bottom. There are three independent layers contributing to this:

**Layer A -- SwiftUI side (deprecated modifier):**

At `SongView.swift:168`:
```swift
VisualizerView(synth: synth, isPresented: $isShowingVisualizer)
    .edgesIgnoringSafeArea(.all)
```

This uses the **deprecated** `.edgesIgnoringSafeArea(.all)` (deprecated since iOS 14.0). The modern equivalent is `.ignoresSafeArea()`. While the old modifier still works, it has known edge-case issues with newer layout behaviors, especially inside `ZStack` compositions like this one.

**Layer B -- WKWebView side (missing inset adjustment):**

`VisualizerView.makeUIView()` at `VisualizerView.swift:87-136` does **not** configure the WKWebView's scroll view to ignore safe area insets. WKWebView automatically adjusts its scroll view content insets to respect the safe area. Missing from `makeUIView`:
```swift
webView.scrollView.contentInsetAdjustmentBehavior = .never
webView.scrollView.isScrollEnabled = false
```

Without this, the web content is pushed inward by the safe area insets even though the SwiftUI frame extends edge-to-edge.

**Layer C -- HTML side (missing viewport-fit=cover):**

At `index.html:5`, the viewport meta tag is:
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
```

This is missing `viewport-fit=cover`, which tells the web renderer to use the full display area including notch/rounded corners. The CSS also does not use `env(safe-area-inset-*)` to properly pad interactive controls while letting the canvas fill the full area.

### Suggested Fix

1. In `SongView.swift:168`, replace `.edgesIgnoringSafeArea(.all)` with `.ignoresSafeArea()`.

2. In `VisualizerView.swift` `makeUIView`, add after creating the webView:
   ```swift
   webView.scrollView.contentInsetAdjustmentBehavior = .never
   webView.scrollView.isScrollEnabled = false
   ```

3. In `index.html:5`, change the viewport meta tag to:
   ```html
   <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
   ```

4. In `index.html` CSS, update `.controls` bottom padding:
   ```css
   .controls {
       padding-bottom: calc(20px + env(safe-area-inset-bottom, 0px));
   }
   ```

---

## Issue 2: WKWebView Integration Problems

### Problem A: Private API usage via KVC (App Store risk)

At `VisualizerView.swift:20-21` and `VisualizerView.swift:89-90`:
```swift
config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
```

These use Key-Value Coding to set **private WebKit preferences**. This is undocumented API and may cause App Store rejection. Apple can change or remove these keys in any iOS release.

**Suggested Fix:** Since the HTML and JS files are loaded from the app bundle using `loadFileURL(_:allowingReadAccessTo:)`, and the `allowingReadAccessTo` parameter already grants access to the parent directory, these flags should not be necessary. Remove both lines and test. If cross-origin issues persist, use a `WKURLSchemeHandler` or `loadHTMLString` with inlined JS.

---

### Problem B: Audio data bridge uses string interpolation

At `VisualizerView.swift:233-236`:
```swift
let jsonString = samplesToSend.description
DispatchQueue.main.async {
    self.webView?.evaluateJavaScript(
        "if(window.pushSamples) window.pushSamples(\(jsonString))",
        completionHandler: nil)
}
```

`samplesToSend.description` generates a potentially ~8KB string of float literals every ~23ms. The JavaScript engine must parse this string and allocate a fresh array on every call. There is no error handling (completionHandler is nil), and if the main thread is busy, these calls queue up, creating memory pressure.

**Suggested Fix:** Pass Base64-encoded `Float32Array` data and decode in JavaScript. This avoids string formatting/parsing overhead entirely. Or use `WKWebView.callAsyncJavaScript` with a parameter dictionary (iOS 14+).

---

### Problem C: Data race on pendingSamples

At `VisualizerView.swift:219-238`:
```swift
synth.engine.installTap { [weak self] samples in
    guard let self = self else { return }
    self.pendingSamples.append(contentsOf: samples)  // audio thread
    if self.pendingSamples.count >= self.sendThreshold {
        let samplesToSend = self.pendingSamples
        self.pendingSamples.removeAll(keepingCapacity: true)
        DispatchQueue.main.async { ... }
    }
}
```

`installTap` (SpatialAudioEngine.swift:93) installs an `AVAudioNodeTapBlock` which is called on an internal **audio I/O thread**. The callback directly mutates `pendingSamples` (a Swift Array, which is **not thread-safe**) without any synchronization. This is a data race.

**Suggested Fix:** Use a lock (`os_unfair_lock`, `NSLock`) or a serial `DispatchQueue` to synchronize access to `pendingSamples`. Alternatively, use a thread-safe ring buffer.

---

### Problem D: Retain cycle from WKUserContentController message handlers

At `VisualizerView.swift:94-98`:
```swift
userContentController.add(context.coordinator, name: "keyHandler")
userContentController.add(context.coordinator, name: "presetHandler")
userContentController.add(context.coordinator, name: "closeViz")
```

`WKUserContentController.add(_:name:)` **strongly retains** the script message handler (the Coordinator). The `dismantleUIView` at line 144-146 calls `coordinator.stopAudioTap()` but does **not** call `removeAllScriptMessageHandlers()`, so the Coordinator is leaked.

**Suggested Fix:** Add cleanup in `dismantleUIView`:
```swift
static func dismantleUIView(_ uiView: VisualizerWebView, coordinator: Coordinator) {
    coordinator.stopAudioTap()
    uiView.configuration.userContentController.removeAllScriptMessageHandlers()
}
```

---

## Issue 3: VisualizerWarmer Design

### Problem A: Warmup provides no practical benefit, wastes resources

`VisualizerWarmer` (`VisualizerView.swift:13-38`) creates a hidden WKWebView at app launch (`AppView.swift:23`), loads the full `index.html`, and keeps it alive for 10 seconds.

This does not achieve its stated goal because:

1. **WKWebView processes are per-configuration, not shared.** The warmer and real VisualizerView use *different* `WKWebViewConfiguration` objects (the real one has userContentController handlers, media settings, etc.). They get separate web content processes. The warmer does not warm up the process the real view will use.

2. **JavaScript execution context is not shared.** The Butterchurn JS library, presets, and WebGL context created by the warmer are discarded when its webView is set to nil. The real VisualizerView reloads everything from scratch.

3. **The only possible benefit is OS-level file cache warming.** But the JS files are local bundle resources, already memory-mapped from the app image. The OS buffer cache handles this without help.

4. **Resource cost is non-trivial.** At app launch, it allocates a WKWebView, spins up a WebKit content process, parses and executes all Butterchurn JavaScript, and creates a WebGL context on a zero-sized canvas. On memory-constrained devices, this increases jetsam pressure right at launch.

5. **Duplicate private API usage** at lines 20-21 doubles the App Store risk surface.

### Problem B: Hardcoded 10-second timer

At `VisualizerView.swift:33-36`:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    self.webView = nil
}
```

This is arbitrary. On fast devices, it holds resources for ~9 unnecessary seconds. On slow devices, 10 seconds may not be enough. There is no `WKNavigationDelegate` to detect actual load completion.

**Suggested Fix:** Remove `VisualizerWarmer` entirely. If first-open latency is a real concern, either:
- Pre-create the *real* WKWebView (with correct configuration) eagerly and keep it hidden, ready to display.
- Show a brief loading animation over the black canvas while Butterchurn initializes.

If the warmer is kept despite the above, at minimum set a `WKNavigationDelegate` and release the webView in `webView(_:didFinish:)` instead of a fixed timer.

---

## Issue 4: Initial Preset Race Condition

### Problem

In `VisualizerView.swift:200-209`, the Coordinator injects `window.initialPresetNameB64` in the `webView(_:didFinish:)` callback (fires when the page finishes loading).

In `index.html:729-745`, the JavaScript checks this variable synchronously at module load time:
```javascript
if (window.initialPresetNameB64) { ... } else { pendingPresetName = random; }
```

There is a race: `<script type="module">` blocks execute before `didFinish` fires. So `window.initialPresetNameB64` will typically be undefined when the JS checks it. The saved preset may never be restored.

This may "work" accidentally because `pendingPresetName` is consumed in the render loop (via `requestAnimationFrame`), and the Swift `evaluateJavaScript` call may sometimes execute between the script finishing and the first render frame. But this is timing-dependent and unreliable.

**Suggested Fix:** Inject the preset name as a `WKUserScript` at `.atDocumentStart` injection time:
```swift
let script = WKUserScript(
    source: "window.initialPresetNameB64 = '\(b64)';",
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(script)
```

This guarantees the variable is set before any module scripts run. This must be done in `makeUIView` (where the config is constructed), not in `didFinish`.

---

## Issue 5: Debug Logging in Production Code

### Problem

Multiple `print()` statements throughout `VisualizerView.swift` (lines 18, 34, 74, 115-127, 201, 212) will emit to the console in production builds. The JS file existence checks at lines 118-127 run every time the view is created and serve no runtime purpose.

**Suggested Fix:** Wrap in `#if DEBUG` or use `os_log` / `Logger` at appropriate log levels. Remove the JS file existence checks entirely.

---

## Summary Table

| # | Issue | Severity | Location |
|---|-------|----------|----------|
| 1 | Safe area not properly ignored (chin/forehead) | **High** | SongView.swift:168, VisualizerView.swift:87-136, index.html:5 |
| 2A | Private API usage (KVC on WKWebViewConfiguration) | **High** | VisualizerView.swift:20-21, 89-90 |
| 2B | Audio data bridge uses string interpolation (~8KB/23ms) | Medium | VisualizerView.swift:229-237 |
| 2C | Data race on pendingSamples (audio thread vs main) | **High** | VisualizerView.swift:160, 219-238 |
| 2D | Retain cycle from message handlers not cleaned up | Medium | VisualizerView.swift:94-98, 144-146 |
| 3A | VisualizerWarmer provides no benefit, wastes resources | Medium | VisualizerView.swift:13-38, AppView.swift:23 |
| 3B | Hardcoded 10s warmup timer, no completion detection | Low | VisualizerView.swift:33-36 |
| 4 | Initial preset race condition (JS runs before Swift injects) | Medium | VisualizerView.swift:200-209, index.html:729-745 |
| 5 | Debug print statements in production code | Low | Throughout VisualizerView.swift |
