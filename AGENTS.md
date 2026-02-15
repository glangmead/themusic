# Agent guide for Swift app development

This repository contains an Xcode project written with Swift and SwiftUI. Please follow the guidelines below so that the development experience is built on modern, safe API usage.

## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SwiftData, AVFoundation and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.

## How to talk to me

- Don't speak as if you should validate what I'm saying, or the code you see. Don't say "You're right to ask about this," or "Good point," or "That's a thoughtful design," or "Linking to the paper is a nice touch." I want you to be dry, terse, and skeptical.
- I hate the word "key" as in "the key point is."
- I especially hate the phrase "key insight." Insight is very rare, don't make it sound like the facile work we're doing is sophisticated or insightful.
- Use logic or mathematics words instead. For example, replace "the key insight is that X, so we'll do Y" with "Given X then the implementation should be Y."

## Core iOS instructions

- Target iOS 26.1 or later.
- Swift 6.2 or later, using modern Swift concurrency.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- Indentation is two spaces
- If installed, make sure swiftlint returns no warnings or errors
- If you see something stupid, tell me. You can be blunt.

## Swift instructions

- Always mark `@Observable` classes with `@MainActor`.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.

## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.

## Workflow preferences

- When given a design proposal or architectural plan, ask clarifying questions before writing any code. Do not assume ambiguous requirements.
- When the user proposes architecture changes, assume existing class names are kept unless the user explicitly says to rename them.
- For large refactors, write a detailed plan to a file first, then implement step by step. Each step should leave the project in a compilable state.
- Build after each logical step of a multi-step change to catch compilation errors early.
- Do not remove commented-out print statements. The user keeps them as debugging landmarks.
- The user uses Instruments.app for profiling and exports call tree data to text files for analysis. When optimizing, always target the top CPU consumers and verify improvements with before/after data.

## Layered audio architecture

The project has a strict layered architecture. Lower layers must not reference or import higher layers. Polyphony and spatial allocation are orthogonal concerns, separated across layers.

1. **Sound Sources**: `Arrow11` (composable DSP graph, processes `[CoreFloat]` buffers via `process(inputs:outputs:)`) and `Sampler` (thin wrapper around `AVAudioUnitSampler`)
2. **NoteHandler protocol**: `noteOn`/`noteOff` for single notes, `notesOn`/`notesOff` for chords (default implementations loop), `globalOffset`/`applyOffset` for transposition, `handles` for parameter access
3. **VoiceLedger**: Note-to-voice-index allocator using Set-based availability tracking and queue-based reuse ordering. Used at both the Preset level (polyphony) and SpatialPreset level (spatial routing)
4. **Preset** (`NoteHandler`): A polyphonic sound source plus effects chain (reverb, delay, distortion, mixer). For Arrow presets: compiles N copies of an `ArrowSyntax`, sums via `ArrowSum`, wraps in `AudioGate`, owns a `VoiceLedger` for voice allocation. For Sampler presets: wraps one `AVAudioUnitSampler` with a 1-voice `VoiceLedger` for note tracking. Exposes merged `handles` from all internal voices. Created from JSON via `PresetSyntax.compile(numVoices:)`
5. **SpatialPreset** (`NoteHandler`): Spatial audio distributor. Owns N Presets (typically 12), each at a different spatial position. Routes notes to Presets via a spatial-level `VoiceLedger`. Aggregates `handles` from all Presets. `notesOn`/`notesOff` chord API with `independentSpatial` parameter for per-note spatial ownership. For Arrow presets: 12 Presets x 1 voice each. For Sampler presets: 12 Presets x 1 sampler each (one note per spatial position)
6. **Music Generation**: `Sequencer` (wraps `AVAudioSequencer`, per-track `NoteHandler` routing via `setHandler(_:forTrack:)`), `MusicPattern`/`MusicPatterns` (generative playback using `SpatialPreset`)

## Key file map

- `Tones/Arrow.swift` — `Arrow11` base class, combinators (`ArrowSum`, `ArrowProd`, `ArrowConst`, `ArrowIdentity`), `AudioGate`, `LowPassFilter2`
- `Tones/ToneGenerator.swift` — Oscillators (`Sine`, `Triangle`, `Sawtooth`, `Square`), `ArrowWithHandles`, `NoiseSmoothStep`, `Choruser`
- `Tones/Envelope.swift` — `ADSR` envelope generator (states: closed, attack, decay, sustain, release)
- `Tones/Performer.swift` — `NoteHandler` protocol (with `handles`), `VoiceLedger`, `MidiNote`, `MidiValue`
- `AppleAudio/Preset.swift` — `Preset` class (`NoteHandler`, polyphonic voice management, effects chain), `PresetSyntax` (Codable JSON spec, `compile(numVoices:)`)
- `AppleAudio/SpatialPreset.swift` — `SpatialPreset` (`NoteHandler`, spatial routing of notes to Presets via `VoiceLedger`)
- `AppleAudio/Sampler.swift` — `Sampler` class (thin `AVAudioUnitSampler` wrapper with file loading)
- `AppleAudio/AVAudioSourceNode+withSource.swift` — Real-time audio render callback bridging Arrow11 output to `AVAudioSourceNode`
- `AppleAudio/SpatialAudioEngine.swift` — Audio engine with `AVAudioEnvironmentNode` for HRTF spatial audio
- `AppleAudio/Sequencer.swift` — MIDI file playback via `AVAudioSequencer`
- `Generators/Pattern.swift` — `MusicEvent`, `MusicPattern`, `MusicPatterns` (generative playback)
- `Synths/SyntacticSynth.swift` — Main synth class with `@Observable` properties and UI bindings, owns a `SpatialPreset`

## Domain knowledge

- `CoreFloat` is a typealias for `Double`. All audio processing is double-precision.
- `MAX_BUFFER_SIZE = 4096`. Scratch buffers are pre-allocated to this size. Actual render frame count is typically up to 512.
- `ArrowWithHandles` wraps an `Arrow11` and adds string-keyed dictionaries (`namedConsts["freq"]`, `namedADSREnvelopes["ampEnv"]`, `namedBasicOscs["osc1"]`, etc.) for parameter access. Keys come from the JSON preset definition.
- `AVAudioUnitSampler` is inherently polyphonic but has a limited (undocumented) voice count. In practice, each sampler Preset is assigned one note at a time by the spatial `VoiceLedger`, so the limit is not an issue. Retrigger (same note repeated) does stop+start via the inner `VoiceLedger`.
- `AudioGate` wraps an Arrow graph and gates output. When `isOpen == false`, the render callback returns silence immediately with `isSilence = true`, saving all downstream processing.
- Each `Preset` can have a `positionLFO` (a `Rose` Lissajous curve) that moves its spatial position over time. `activeNoteCount` on Preset gates whether the LFO updates run.
- `PresetSyntax.compile(numVoices:)` creates a runtime `Preset` from a declarative JSON specification. The `numVoices` parameter controls how many Arrow voice copies are compiled internally (default 12 for standalone use, typically 1 when created by `SpatialPreset` for independent spatial routing).

## Tests

The project has over 100 unit tests across files in `ProgressionPlayerTests/`, using the Swift Testing framework (`@Suite`, `@Test`, `#expect`). All suites use `.serialized` because Arrow objects have mutable scratch buffers.

Tests avoid AVFoundation by using `Preset(arrowSyntax:numVoices:initEffects: false)` and working directly with `ArrowSyntax.compile()`. The `initEffects` parameter (defaults to `true`) skips creation of `AVAudioUnitReverb`/`AVAudioUnitDelay`/`AVAudioMixerNode`. Shared test utilities (`renderArrow`, `rms`, `zeroCrossings`, `loadPresetSyntax`, `makeOscArrow`) live in `ArrowDSPPipelineTests.swift`.

`RunAllTests` may hang in the test host environment; run suites individually via `RunSomeTests` instead.

## Audio performance rules

The render callback in `AVAudioSourceNode+withSource.swift` runs on a real-time audio thread. CPU budget matters — the user actively profiles with Instruments.

- Never allocate memory in `process()` methods or the render callback.
- Use C-level vDSP functions (`vDSP_vaddD`, `vDSP_vmulD`, `vDSP_mmovD`) not the Swift overlay (`vDSP.add`, `vDSP.multiply`). The Swift overlay creates `ArraySlice` objects.
- Use `withUnsafeBufferPointer` / `withUnsafeMutableBufferPointer` in all per-sample loops to eliminate Swift bounds checking.
- Use the `AudioGate` + `isSilence` pattern: when a voice is idle, the render callback returns immediately with zeroed buffers and `isSilence = true`.
- Prefer `x - floor(x)` over `fmod(x, 1)` for positive values in DSP code.

