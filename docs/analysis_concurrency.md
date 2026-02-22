# Concurrency Bug Analysis: ProgressionPlayer Test Suite

Static analysis performed 2026-02-15. No tests were executed.

## Files Analyzed

### Test files (4 unit test files + 2 UI test files)
- `ProgressionPlayerTests/ArrowDSPPipelineTests.swift` -- Arrow combinator, oscillator, ADSR, preset compilation, sound fingerprint tests; also contains shared test utilities (`renderArrow`, `rms`, `zeroCrossings`, `loadPresetSyntax`, `makeOscArrow`)
- `ProgressionPlayerTests/NoteHandlingTests.swift` -- VoiceLedger, Preset noteOn/noteOff, handle duplication tests
- `ProgressionPlayerTests/PatternGenerationTests.swift` -- Iterator, MusicEvent modulation, MusicPattern event generation tests
- `ProgressionPlayerTests/UIKnobPropagationTests.swift` -- Knob-to-handle propagation, knob-to-sound verification tests
- `ProgressionPlayerUITests/ProgressionPlayerUITests.swift` -- Boilerplate UI tests
- `ProgressionPlayerUITests/ProgressionPlayerUITestsLaunchTests.swift` -- Launch screenshot test

### Source files read
- `Sources/AppleAudio/Preset.swift`
- `Sources/AppleAudio/SpatialPreset.swift`
- `Sources/AppleAudio/SpatialAudioEngine.swift`
- `Sources/AppleAudio/Sequencer.swift`
- `Sources/AppleAudio/AVAudioSourceNode+withSource.swift`
- `Sources/Tones/Arrow.swift`
- `Sources/Tones/ToneGenerator.swift`
- `Sources/Tones/Envelope.swift`
- `Sources/Tones/Performer.swift`
- `Sources/Generators/Pattern.swift`
- `Sources/Synths/SyntacticSynth.swift`
- `AGENTS.md`

---

## Summary of Findings

The test suite has **one high-severity issue** that is the most likely cause of hangs, **two medium-severity issues** that could contribute to flakiness or intermittent hangs, and **several low-severity observations**.

The AGENTS.md file itself documents: `RunAllTests may hang in the test host environment; run suites individually via RunSomeTests instead.` This analysis identifies the probable root causes.

---

## HIGH SEVERITY -- Likely Cause of Test Hangs

### H1. `MusicEvent.play()` uses real `Task.sleep` in tests, creating timing-dependent async tests

**Files:**
- `PatternGenerationTests.swift` lines 194, 224, 250, 280, 419
- `Pattern.swift` lines 36-59

**The problem:**

Five test functions call `event.play()`, which is an `async` method on `MusicEvent`. The implementation of `play()` does:

```swift
mutating func play() async throws {
    // ... modulation ...
    noteHandler.notesOn(notes)
    do {
        try await Task.sleep(for: .seconds(TimeInterval(sustain)))
    } catch {
        // silently swallowed
    }
    noteHandler.notesOff(notes)
}
```

The tests pass `sustain: 0.01` and `gap: 0.01`, which means each `event.play()` call sleeps for at least 10ms of real wall-clock time. While 10ms seems short, in the Swift Testing framework's serialized async test runner, these sleeps accumulate and interact with the concurrency runtime in ways that can cause problems:

1. **Cancellation errors are silently swallowed.** The `catch` block on line 56 of Pattern.swift is empty. If the Task running the test is cancelled (e.g., by a test timeout), `Task.sleep` throws `CancellationError`, the catch block eats it, and `notesOff` runs -- but the test framework may be in an inconsistent state. More critically, if the test runner's task is cancelled while awaiting `event.play()`, the test function itself never resumes to check its `#expect` assertions, which can leave the test in a permanently suspended state.

2. **`.serialized` suites with async tests run sequentially on the cooperative thread pool.** The Swift Testing framework's `.serialized` trait means tests within a suite run one at a time, but when combined with `async` test functions, the test runner must await each test's completion. If `Task.sleep` is delayed (e.g., due to thread pool saturation from other suites running concurrently across the process), the sleep can take much longer than 10ms.

3. **Cross-suite parallelism is still possible.** Even though each suite is `.serialized` internally, the Swift Testing framework can run *different* suites in parallel by default. This means multiple suites could be competing for cooperative thread pool threads simultaneously. If one suite's `Task.sleep` starves another suite's continuation, the test runner can appear to hang.

**Why this causes hangs when running all tests but not individual suites:**

When `RunAllTests` is invoked, the framework runs suites concurrently. The 5 async tests in `PatternGenerationTests.swift` (MusicEvent Modulation + MusicPattern Event Generation suites) each hold a cooperative thread while sleeping. If the thread pool becomes saturated -- especially in a test host environment that may have reduced resources -- other suites waiting for thread pool time can stall indefinitely. This matches the documented behavior in AGENTS.md that `RunAllTests` hangs but individual suite runs succeed.

**Recommendation:**

Replace real `Task.sleep` with a test-injectable delay mechanism. Options:
- Add a `Clock` parameter to `MusicEvent` (or an injectable sleep closure) so tests can pass `ImmediateClock` or a zero-duration sleep.
- Create a test-specific `MusicEvent` variant that skips the sleep entirely.
- Alternatively, set `sustain: 0` and `gap: 0` in tests and modify `play()` to skip the sleep when `sustain == 0`.

---

## MEDIUM SEVERITY -- Could Contribute to Hangs or Flakiness

### M1. `@Observable` classes lack `@MainActor` isolation, creating potential data races with the test runner

**Files:**
- `Preset.swift` line 67: `@Observable class Preset: NoteHandler`
- `SpatialPreset.swift` line 22: `@Observable class SpatialPreset: NoteHandler`
- `SyntacticSynth.swift` line 22: `@Observable class SyntacticSynth`
- `Sequencer.swift` line 13: `@Observable class Sequencer`

**The problem:**

The project's own AGENTS.md (line 29) says: "Always mark `@Observable` classes with `@MainActor`." None of the four `@Observable` classes follow this rule. Under Swift 6's strict concurrency checking, `@Observable` generates property access tracking that is not thread-safe without actor isolation.

In the test suite, tests create `Preset` instances and call `noteOn`/`noteOff` on them. These tests are `struct`-based Swift Testing suites, which run on the cooperative thread pool (not the main actor). If the `@Observable` macro's internal tracking state is accessed from multiple threads simultaneously (which can happen when suites run in parallel and share no explicit synchronization), the observation tracking could corrupt its internal state.

In practice, the tests create independent `Preset` instances per test, so cross-test data races are unlikely *within* a single suite. But if the `@Observable` machinery triggers any main-actor-bound work internally (e.g., SwiftUI observation callbacks), the test could deadlock waiting for the main actor while the main actor is blocked.

**Specific risk in tests:**

The `Preset.setupLifecycleCallbacks()` method (Preset.swift lines 118-135) installs closures on ADSR envelopes that call `self.activate()` and `self.deactivate()`. These closures capture `[weak self]` and access `self.audioGate?.isOpen` and iterate `ampEnvs`. If the `@Observable` property wrapper generates main-actor-isolated setters for `audioGate`, calling `activate()` from a non-main-actor test thread could trigger a runtime assertion or deadlock.

**Recommendation:**

Either add `@MainActor` to all `@Observable` classes (and update tests to run on `@MainActor`), or confirm that the current code compiles with strict concurrency checking enabled (Swift 6 mode). The test `noteOnProducesSound` in NoteHandlingTests.swift directly calls `preset.audioGate!.process(...)` and `preset.audioGate!.isOpen`, which would be flagged under strict concurrency if `Preset` were `@MainActor`.

### M2. `VoiceLedger` is a `final class` with no thread safety, accessed from multiple contexts

**Files:**
- `Performer.swift` lines 57-103
- `Preset.swift` lines 243-288 (noteOn/noteOff access the ledger)
- `SpatialPreset.swift` lines 104-123 (noteOn/noteOff access the spatial ledger)

**The problem:**

`VoiceLedger` uses mutable `Set` and `Dictionary` state (`noteOnnedVoiceIdxs`, `availableVoiceIdxs`, `noteToVoiceIdx`, `indexQueue`) with no synchronization. In production, this is accessed from:
- The main thread (UI-driven noteOn/noteOff via SyntacticSynth)
- MIDI callback threads (via Sequencer's MIDICallbackInstrument)
- The cooperative thread pool (via MusicPattern.play())

In the test suite specifically, this is lower risk because tests create isolated `Preset` instances. However, the `MusicEvent Modulation` tests call `event.play()` which is `async`, and the async context means the continuation after `Task.sleep` could resume on a different thread than the one that called `noteOn`. If `noteOn` and `noteOff` end up on different threads for the same `Preset` instance, the `VoiceLedger`'s unsynchronized state could be corrupted.

**Recommendation:**

Make `VoiceLedger` either an `actor` or protect its state with a lock. For the test suite, this is unlikely to be the hang cause, but it is a latent data race.

---

## LOW SEVERITY -- Observations and Minor Risks

### L1. Arrow `scratchBuffer` fields are mutable shared state (documented, mitigated by `.serialized`)

**Files:**
- `Arrow.swift` -- `ArrowSum.scratchBuffer`, `ArrowProd.scratchBuffer`, `ControlArrow11.scratchBuffer`
- `ToneGenerator.swift` -- `Sine.scratch`, `Triangle.scratch`, `Sawtooth.scratch`, `BasicOscillator.innerVals`, `Choruser.innerVals`, `LowPassFilter2.innerVals`, etc.

**The problem:**

Every Arrow subclass has pre-allocated `[CoreFloat]` scratch buffers as instance properties. These are mutated during `process()`. If two tests were to share an Arrow instance and call `process()` concurrently, the buffers would be corrupted.

**Mitigation:**

The AGENTS.md documents this: "All suites use `.serialized` because Arrow objects have mutable scratch buffers." The `.serialized` trait ensures tests within each suite run sequentially. Since tests create independent Arrow instances, and the serialization prevents concurrent execution within a suite, this is not a problem in practice. Cross-suite parallelism is safe because different suites create different object graphs.

### L2. `Preset.initEffects()` creates AVFoundation objects even in test helper code paths

**Files:**
- `Preset.swift` lines 317-326
- Test files consistently use `initEffects: false`

**Mitigation:**

All test code consistently passes `initEffects: false` when constructing `Preset` instances. The `AVAudioUnitReverb`, `AVAudioUnitDelay`, and `AVAudioMixerNode` are not created in test paths. This is correct and prevents AVFoundation resource leaks.

### L3. `ADSR.finishCallback` fires from within `env()` which is called from `process()` on the audio render thread

**Files:**
- `Envelope.swift` lines 65-68
- `Preset.swift` lines 118-135

**The problem:**

When `ADSR.env()` detects the release phase has completed, it synchronously invokes `finishCallback` (line 68). In `Preset`, this callback checks `ampEnvs.allSatisfy { $0.state == .closed }` and conditionally calls `self.deactivate()` which sets `audioGate?.isOpen = false`.

In production, `env()` is called from the audio render callback (real-time thread). The `finishCallback` therefore runs on the real-time audio thread, which:
- Reads `.state` from multiple ADSR objects (potential data race with noteOn from another thread)
- Sets `audioGate?.isOpen` (a `Bool` property on `AudioGate`, which is also read by the render callback and written by `activate()`/`deactivate()`)

In tests, this is triggered when `preset.audioGate!.process(inputs:outputs:)` is called directly (e.g., `noteOnProducesSound` test in NoteHandlingTests.swift). Since tests are single-threaded within a serialized suite, the data race does not manifest. But it is a production bug.

### L4. Tests do not cancel Tasks, but no Tasks are spawned in tests

**Observation:**

None of the unit tests spawn any `Task` objects. The `async` test functions use `try await event.play()` directly, which is structured concurrency. No `Task.detached` or `Task { }` calls exist in test code. The `positionTask` in `Preset.wrapInAppleNodes()` is never called in tests because tests use `initEffects: false` and never call `wrapInAppleNodes`.

This is correct -- there are no leaked Tasks from the test suite.

### L5. `loadPresetSyntax` uses `Bundle.main` which may behave differently in test host

**Files:**
- `ArrowDSPPipelineTests.swift` lines 63-69

**The problem:**

```swift
func loadPresetSyntax(_ filename: String) throws -> PresetSyntax {
    guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "presets") else {
        throw PresetLoadError.fileNotFound(filename)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(PresetSyntax.self, from: data)
}
```

`Bundle.main` in a test target resolves to the test host app's bundle. If the test host is not the ProgressionPlayer app (e.g., if tests are run as a standalone XCTest bundle), the preset JSON files may not be found, causing `PresetLoadError.fileNotFound` to be thrown. This would cause test failures, not hangs.

### L6. No `setUp`/`tearDown` in Swift Testing struct-based suites

**Observation:**

The test suites use Swift Testing's `@Suite` structs, not XCTest classes. There is no `setUp`/`tearDown` machinery. Each test creates its own `Preset`/`VoiceLedger`/`ArrowWithHandles` instances locally. This is actually a strength -- there is no shared mutable state between tests within a suite, eliminating an entire class of test-ordering bugs.

### L7. The `MusicEvent` struct is `mutating` in `play()` but the tests use `var`

**Files:**
- `Pattern.swift` line 36: `mutating func play() async throws`
- `PatternGenerationTests.swift` lines 201, 228, 258, 289, 423: all declare `var event = MusicEvent(...)`

**Observation:**

This is correct usage. The `mutating` keyword on a struct method requires a `var` binding. Since each test creates its own local `var event`, there is no shared state. The mutation is contained within each test.

---

## Root Cause Assessment for `RunAllTests` Hanging

The most probable cause of `RunAllTests` hanging is **H1**: the combination of:

1. Five `async` test functions that call `Task.sleep(for: .seconds(0.01))` via `event.play()`
2. All 14 test suites marked `.serialized` (intra-suite serialization)
3. Cross-suite parallelism enabled by default in Swift Testing
4. A cooperative thread pool with limited threads in the test host environment

When all suites run simultaneously, the cooperative thread pool must service:
- The 5 sleeping async tests (each holding a thread while suspended)
- All the synchronous tests across other suites (which need threads to execute)

If the thread pool becomes saturated, the framework's internal coordination (which also runs on the cooperative pool) can deadlock. The `.serialized` trait exacerbates this because it uses internal synchronization primitives that themselves need cooperative pool threads to resume.

**Proposed fix priority:**
1. **H1** -- Replace `Task.sleep` in `MusicEvent.play()` with an injectable mechanism; use zero-duration or immediate sleep in tests
2. **M1** -- Add `@MainActor` to `@Observable` classes (requires updating test functions accordingly)
3. **M2** -- Add thread safety to `VoiceLedger` (production correctness fix)
