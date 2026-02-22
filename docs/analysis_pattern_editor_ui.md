# Pattern Editor UI Design -- Liquid Glass

## Overview

This document describes the UI design for a **Pattern Editor** in ProgressionPlayer, styled
with Apple's **Liquid Glass** design language (iOS 26 / macOS 26). The Pattern Editor lets the
user compose, view, and tweak `MusicPattern` instances -- the generative music objects that
drive playback in the app.

A `MusicPattern` (defined in `Sources/Generators/Pattern.swift`) is an actor that holds:

| Field            | Type                                | Purpose                                      |
|------------------|-------------------------------------|----------------------------------------------|
| `spatialPreset`  | `SpatialPreset`                     | The instrument/voice pool that plays events   |
| `modulators`     | `[String: Arrow11]`                 | Named parameter-automation arrows             |
| `notes`          | `any IteratorProtocol<[MidiNote]>`  | A sequence of chords (note generators)        |
| `sustains`       | `any IteratorProtocol<CoreFloat>`   | How long each event sustains                  |
| `gaps`           | `any IteratorProtocol<CoreFloat>`   | How long to wait between events               |

Each `MusicEvent` produced by a pattern has: `notes`, `sustain`, `gap`, and `modulators`.

---

## Design Principles

1. **Liquid Glass everywhere** -- panels, transport controls, toolbars, and floating overlays
   all use `.glassEffect()` or `.buttonStyle(.glass)` to get the translucent, light-refracting
   material.
2. **Dark canvas, bright glass** -- the piano roll and timeline sit on a dark background
   (consistent with the existing `Theme.gradientMain()` / black), letting the glass UI elements
   float above the content and refract the underlying note colors.
3. **GlassEffectContainer** -- groups of related controls (transport bar, modulator knobs) are
   wrapped in `GlassEffectContainer` so nearby glass shapes blend and morph into each other.
4. **Interactive glass** -- all tappable elements use `.glassEffect(.regular.interactive())` or
   `.buttonStyle(.glass)` to get the press/hover fluid response.
5. **Tinted glass for state** -- playing state uses `.tint(.green)`, recording uses
   `.tint(.red)`, selected patterns use `.tint(Theme.colorHighlight)`.

---

## Screen Architecture

The Pattern Editor is a full-screen view presented as a sheet or navigation destination
from `SongView`. It contains four vertically-stacked zones:

```
+============================================================+
|  [1] TOOLBAR BAR (glass)                                    |
|  Pattern name | Preset picker | Time sig | Tempo            |
+============================================================+
|                                                              |
|  [2] PIANO ROLL / TIMELINE                                  |
|  (scrollable canvas, dark background)                       |
|                                                              |
|  C5 |----[====]----------[==]------|                         |
|  B4 |------------------------------|                         |
|  A4 |------[========]--------------|                         |
|  G4 |---[====]----[====]-----------|                         |
|     0    1    2    3    4    5   bars                        |
|                                                              |
+============================================================+
|  [3] MODULATION LANE (collapsible, glass panel)             |
|  Parameter: overallAmp   [curve visualization]               |
|  Parameter: vibratoFreq  [curve visualization]               |
+============================================================+
|  [4] TRANSPORT BAR (glass, bottom-pinned)                   |
|  [|<] [>] [||] [Stop] [Loop]    0:00 / 0:32                |
+============================================================+
```

---

## Zone 1: Toolbar Bar

### ASCII Mockup

```
+------------------------------------------------------------------+
|  [< Back]   "Pattern 1"   [Preset: Aurora v]  4/4  BPM [120___] |
+------------------------------------------------------------------+
```

### Layout and Components

- **Container**: `HStack` inside a `.toolbar` or custom bar, wrapped in
  `GlassEffectContainer(spacing: 12)`.
- **Back button**: `Button` with `.buttonStyle(.glass)`.
- **Pattern name**: Editable `TextField`, styled with `.glassEffect(in: .rect(cornerRadius: 8))`.
- **Preset picker**: `Menu` (or `Picker(.menu)`) styled with `.buttonStyle(.glass)`. Lists all
  presets from the bundle `presets/` directory, reusing the logic from `PresetListView`.
- **Time signature picker**: `Picker(.segmented)` with options like 4/4, 3/4, 6/8, 5/4.
  Segmented pickers on iOS 26 get glass treatment automatically.
- **Tempo**: `KnobbyKnob` (existing component) or a compact `TextField` with stepper,
  wrapped in `.glassEffect(in: .capsule)`.

### Liquid Glass Application

```swift
GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        Button(action: dismiss) {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.glass)

        TextField("Pattern Name", text: $patternName)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(in: .rect(cornerRadius: 8))

        Menu {
            ForEach(presets) { preset in
                Button(preset.spec.name) { selectPreset(preset) }
            }
        } label: {
            Label(selectedPresetName, systemImage: "pianokeys")
        }
        .buttonStyle(.glass)

        Picker("Time Sig", selection: $timeSignature) {
            Text("4/4").tag(TimeSignature.fourFour)
            Text("3/4").tag(TimeSignature.threeFour)
            Text("6/8").tag(TimeSignature.sixEight)
        }
        .pickerStyle(.segmented)

        HStack(spacing: 4) {
            Text("BPM")
                .font(.caption)
            TextField("", value: $tempo, format: .number)
                .frame(width: 50)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
    }
}
```

---

## Zone 2: Piano Roll / Timeline

### ASCII Mockup (landscape orientation, scrollable)

```
      Bar 1         Bar 2         Bar 3         Bar 4
      |             |             |             |
  C5  |  [====]     |             |  [==]       |
  B4  |             |             |             |
  Bb4 |             |  [=====]    |             |
  A4  |      [==========]        |             |
  Ab4 |             |             |             |
  G4  |  [===]      |  [===]     |             |
  F#4 |             |             |             |
  F4  |             |             |  [======]   |
  E4  |             |             |             |
  Eb4 |             |             |             |
  D4  |             |             |             |
  C#4 |             |             |             |
  C4  |             |             |             |
      +-------------+-------------+-------------+----->
      |<- beat markers (vertical lines, subtle) ->|
```

### Layout and Components

- **Container**: A `ScrollView([.horizontal, .vertical])` containing a `Canvas` or `ZStack`
  of positioned rectangles.
- **Piano keys (left gutter)**: A vertical column of note labels (`Text("C5")`, etc.) that
  scrolls vertically in sync with the roll. Black keys have a darker background.
  The key column is pinned to the leading edge using a `LazyHStack` with a pinned header,
  or a `GeometryReader` overlay.
- **Note blocks**: Each `MusicEvent` is drawn as a rounded rectangle. Width = sustain duration
  scaled to the time axis. Vertical position = MIDI note number mapped to a row.
  Color encodes velocity (brighter = louder), using `Theme.colorHighlight` as base hue.
- **Beat grid**: Vertical lines at each beat, with heavier lines at bar boundaries.
  Drawn in the `Canvas` or as `Divider()`-like shapes.
- **Playhead**: A vertical line (`.foregroundStyle(Theme.colorHighlight)`) that animates
  across the timeline during playback. Rendered as an overlay.
- **Background**: `Theme.gradientDarkScreen()` or solid `Color.black`.

### Interaction

- **Tap to add note**: Tap an empty cell to insert a note at that pitch/time.
- **Drag note**: Move horizontally to change timing, vertically to change pitch.
- **Drag right edge**: Resize sustain duration.
- **Long press**: Delete note or open context menu.
- **Pinch**: Zoom time axis (horizontal) or pitch axis (vertical).
- **Two-finger scroll**: Pan the viewport.

### Liquid Glass Application

The piano roll itself is NOT glass (it is a dark canvas for contrast). But:

- **Floating toolbar overlays** on the roll (zoom controls, snap settings) use
  `.glassEffect(in: .rect(cornerRadius: 12))`.
- **The playhead** could have a subtle glass glow at its base.
- **Selected notes** gain a `.glassEffect(.regular.tint(Theme.colorHighlight))` highlight.

```swift
// Zoom / snap overlay floating above the piano roll
VStack {
    Spacer()
    HStack {
        Spacer()
        HStack(spacing: 8) {
            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            Picker("Snap", selection: $snapDivision) {
                Text("1/4").tag(4)
                Text("1/8").tag(8)
                Text("1/16").tag(16)
            }
            .pickerStyle(.segmented)
        }
        .padding(8)
        .glassEffect(in: .rect(cornerRadius: 12))
        .padding()
    }
}
```

---

## Zone 3: Modulation Lanes

### ASCII Mockup

```
+------------------------------------------------------------------+
| Modulator: [overallAmp    v]                                      |
|                                                                    |
|  1.0 |          /\                                                |
|      |         /  \       /\                                      |
|      |        /    \_____/  \                                     |
|  0.0 |_______/               \__________________________________ |
|      0    1    2    3    4    5   bars                            |
+------------------------------------------------------------------+
| Modulator: [vibratoFreq   v]                                      |
|                                                                    |
|  30  |                    ____                                    |
|      |                   /    \                                   |
|      |    ____          /      \                                  |
|  0   |___/    \________/        \_______________________________ |
|      0    1    2    3    4    5   bars                            |
+------------------------------------------------------------------+
```

### Layout and Components

- **Container**: `VStack` of modulation lane views, each in a `DisclosureGroup` for
  collapse/expand. The entire zone is a collapsible section.
- **Parameter selector**: `Picker(.menu)` listing the keys of the pattern's `modulators`
  dictionary (e.g. `"overallAmp"`, `"vibratoFreq"`, `"overallCentDetune"`).
- **Curve display**: Reuses `ArrowChart` (the existing `Chart`-based arrow visualizer from
  `Sources/UI/ArrowChart.swift`) but adapted to align its x-axis with the piano roll's
  time axis.
- **Curve editing**: Drag control points to reshape. For `ArrowConst`-based modulators,
  this is a horizontal line the user drags up/down. For `ArrowRandom`-based modulators,
  the user edits `min`/`max` as a shaded band.

### Liquid Glass Application

Each lane's header and controls are glass. The chart body remains dark for readability.

```swift
GlassEffectContainer(spacing: 8) {
    VStack(spacing: 8) {
        ForEach(modulatorKeys, id: \.self) { key in
            DisclosureGroup(key) {
                ModulationLaneView(
                    arrow: modulators[key]!,
                    timeRange: timeRange
                )
                .frame(height: 100)
                .background(Theme.gradientDarkScreen())
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
    }
}
```

---

## Zone 4: Transport Bar

### ASCII Mockup

```
+------------------------------------------------------------------+
|  [|<]  [>]  [||]  [Stop]  [Loop: On]     0:05.2 / 0:32.0       |
+------------------------------------------------------------------+
```

Or with more detail:

```
+------------------------------------------------------------------+
|                                                                    |
|  ( |< )   ( > )   ( || )   ( [] )   ( repeat )                   |
|                                                                    |
|  =========[====]============================================  time |
|                                                                    |
|  00:05.2 / 00:32.0                 Sustain: 5-10s  Gap: 5-10s   |
+------------------------------------------------------------------+
```

### Layout and Components

- **Container**: Bottom-pinned `HStack` inside a `GlassEffectContainer`.
- **Transport buttons**: Using SF Symbols and `.buttonStyle(.glass)`:
  - Rewind: `backward.end.fill`
  - Play: `play.fill` (toggles to `pause.fill`)
  - Stop: `stop.fill`
  - Loop: `repeat` (toggle, tinted green when on)
- **Progress bar**: A custom `Slider` or `ProgressView` showing elapsed time vs total
  pattern duration. Styled with a glass track.
- **Time display**: `Text` formatted as `MM:SS.s` in monospaced font.
- **Pattern parameters**: Compact display of sustain range and gap range, editable
  via `KnobbyKnob` popover or inline controls.

### Liquid Glass Application

The entire transport bar is a single merged glass panel. Buttons within it morph
together when they are close.

```swift
GlassEffectContainer(spacing: 8) {
    HStack(spacing: 16) {
        // Transport buttons
        HStack(spacing: 8) {
            Button(action: rewind) {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.glass)

            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.glassProminent)

            Button(action: stop) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.glass)

            Button(action: toggleLoop) {
                Image(systemName: "repeat")
            }
            .buttonStyle(.glass(isLooping ? .regular.tint(.green) : .regular))
        }

        Spacer()

        // Time display
        Text(timeString)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(in: .capsule)

        Spacer()

        // Sustain/Gap range display
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("Sustain").font(.caption2)
                Text("\(sustainMin, specifier: "%.1f")-\(sustainMax, specifier: "%.1f")s")
                    .font(.caption)
            }
            VStack(spacing: 2) {
                Text("Gap").font(.caption2)
                Text("\(gapMin, specifier: "%.1f")-\(gapMax, specifier: "%.1f")s")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .rect(cornerRadius: 10))
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
}
```

---

## Preset Selector Detail

### ASCII Mockup (popover or sheet)

```
+--------------------------------------+
|  Select Instrument Preset            |
|                                      |
|  [x] Aurora Borealis                 |
|  [ ] 5th Cluedo                      |
|  [ ] GeneralUser Piano               |
|  [ ] GeneralUser Harpsichord         |
|  [ ] GeneralUser Glockenspiel        |
|  [ ] Saw                             |
|  [ ] Sine                            |
|  [ ] Square                          |
|  [ ] Triangle                        |
|                                      |
|  [Edit Synth Parameters...]          |
+--------------------------------------+
```

### Implementation

Reuses the existing `PresetListView` component, presented as a `.popover()` from the
toolbar's preset button. Add an "Edit Synth Parameters" button at the bottom that
presents `SyntacticSynthView` as a sheet, giving full access to oscillator shapes,
ADSR envelopes, effects, etc.

### Liquid Glass Application

The popover itself gets glass treatment automatically on iOS 26. The "Edit Synth
Parameters" button uses `.buttonStyle(.glassProminent)`.

---

## Note Generator Configuration

Since `MusicPattern.notes` is an `IteratorProtocol<[MidiNote]>`, and the project has
several generator types (`Midi1700sChordGenerator`, `MidiPitchAsChordGenerator`,
`ScaleSampler`), the editor needs a way to choose and configure the generator.

### ASCII Mockup (sheet or section)

```
+----------------------------------------------+
|  Note Generator                               |
|                                               |
|  Type: [Baroque Chord Progression  v]         |
|                                               |
|  Scale: [Major     v]                         |
|  Root:  [A   v]                               |
|                                               |
|  -- or for "Pitch in Scale" type --           |
|                                               |
|  Scale:   [Lydian   v]                        |
|  Root:    [C   v]                             |
|  Octaves: [2, 3, 4, 5]  (multi-select)       |
|  Degrees: [0-6] (shuffle)                     |
|  Root Change Interval: 10-25s                 |
+----------------------------------------------+
```

### Liquid Glass Application

Each configuration group is a glass-backed section:

```swift
VStack(spacing: 12) {
    Picker("Generator Type", selection: $generatorType) {
        Text("Baroque Chord Progression").tag(GeneratorType.baroque)
        Text("Pitch in Scale").tag(GeneratorType.pitchInScale)
        Text("Scale Sampler").tag(GeneratorType.scaleSampler)
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12))

    // Conditional config UI based on generatorType
    if generatorType == .baroque {
        HStack {
            Picker("Scale", selection: $scale) { ... }
            Picker("Root", selection: $rootNote) { ... }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 12))
    }
}
```

---

## Responsive Layout

| Screen Size          | Adaptation                                              |
|----------------------|---------------------------------------------------------|
| iPhone portrait      | Piano roll takes full width. Modulation lanes collapse. Transport bar compact (icons only). |
| iPhone landscape     | Piano roll + narrow modulation lane side-by-side.       |
| iPad                 | Full layout as described above.                         |
| Mac Catalyst         | Uses `WindowGroup(id: "pattern-editor")` for dedicated window. Toolbar uses native macOS glass. |

---

## Navigation Flow

```
AppView
  |-- TabView
       |-- TheoryView
       |-- SongView
            |-- "Play Pattern" button (existing)
            |-- NEW: "Edit Pattern" button
                 |-- PatternEditorView (sheet or navigation destination)
                      |-- Toolbar Bar [Zone 1]
                      |-- Piano Roll [Zone 2]
                      |-- Modulation Lanes [Zone 3]
                      |-- Transport Bar [Zone 4]
```

---

## Color Palette (extending Theme.swift)

| Element               | Color                                        |
|-----------------------|----------------------------------------------|
| Piano roll background | `Color.black` / `Theme.gradientDarkScreen()` |
| Note blocks           | `Theme.colorHighlight` with velocity alpha    |
| Selected note         | Glass tinted `Theme.colorHighlight`           |
| Beat grid lines       | `Theme.colorGray3` (subtle)                  |
| Bar grid lines        | `Theme.colorGray4` (brighter)                |
| Playhead              | `Theme.colorHighlight` with glow             |
| Glass panels          | System Liquid Glass (auto tint from content)  |
| Playing indicator     | Glass tinted `.green`                         |
| Recording indicator   | Glass tinted `.red`                           |

---

## Key SwiftUI APIs Used

| API                                            | Where                                |
|------------------------------------------------|--------------------------------------|
| `.glassEffect()`                               | All panels, overlays, display fields |
| `.glassEffect(in: .rect(cornerRadius: N))`     | Rectangular panels                   |
| `.glassEffect(.regular.tint(color))`           | State-indicating elements            |
| `.glassEffect(.regular.interactive())`         | Custom tappable controls             |
| `.buttonStyle(.glass)`                         | All transport and toolbar buttons    |
| `.buttonStyle(.glassProminent)`                | Primary action buttons (Play)        |
| `GlassEffectContainer(spacing:)`               | Groups of related controls           |
| `.glassEffectID(_:in:)`                        | Morphing transitions                 |
| `Canvas` / `Chart`                             | Piano roll, modulation curves        |
| `ScrollView` with `GeometryReader`             | Scrollable piano roll                |
| `KnobbyKnob` (existing)                       | Tempo, parameter adjustment          |
| `ArrowChart` (existing, adapted)               | Modulation lane visualization        |

---

## File Organization

```
Sources/
  PatternEditor/
    PatternEditorView.swift         -- Main container (zones 1-4)
    PianoRollView.swift             -- Zone 2: the scrollable note grid
    PianoRollNoteView.swift         -- Individual note rectangle
    ModulationLaneView.swift        -- Zone 3: one parameter lane
    TransportBarView.swift          -- Zone 4: playback controls
    NoteGeneratorConfigView.swift   -- Generator type picker + config
    PatternEditorPreview.swift      -- Preview file with all components
```

---

## Data Flow

```
PatternEditorView
  @State var pattern: EditablePattern    // A mutable, non-actor wrapper
  @Environment(SyntacticSynth.self)      // For preset access

EditablePattern (new struct or class)
  var name: String
  var tempo: Double
  var timeSignature: TimeSignature
  var notes: [EditableNote]              // Concrete array for editing
  var modulators: [String: ModulatorConfig]
  var sustainRange: ClosedRange<CoreFloat>
  var gapRange: ClosedRange<CoreFloat>
  var presetSpec: PresetSyntax

  func toMusicPattern(engine:) -> MusicPattern  // Convert back for playback
```

The editor works on an `EditablePattern` -- a mutable, concrete representation. When the
user hits Play, it converts to a `MusicPattern` actor for real-time playback.

---

## Summary

The Pattern Editor brings together the existing musical building blocks (`MusicPattern`,
`MusicEvent`, `Arrow11` modulators, `PresetSyntax`) with a DAW-inspired editing interface.
Liquid Glass is applied strategically:

- **Structural glass**: Toolbar, transport bar, modulation lane headers form the UI skeleton
  as luminous glass panels floating over the dark canvas.
- **Interactive glass**: All buttons and tappable controls react to touch with the fluid
  Liquid Glass press animation.
- **Tinted glass for state**: Playing, looping, and selection states are communicated through
  tinted glass variants.
- **GlassEffectContainer morphing**: Related controls blend and morph when they are close,
  creating a cohesive, organic toolbar that feels alive.
- **Dark content canvas**: The piano roll and modulation curves remain on dark backgrounds
  for contrast and readability, with glass used only for overlays and controls floating above.
