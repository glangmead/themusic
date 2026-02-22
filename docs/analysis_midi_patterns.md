# Design: MIDI-File-Driven Patterns

## Problem Statement

The existing `Sequencer` wraps `AVAudioSequencer` and routes all tracks to a single `NoteHandler` (with per-track override via `setHandler(_:forTrack:)`). The existing `MusicPattern` system generates notes procedurally through iterator-based sequences. Neither system supports loading a MIDI file and mapping its tracks to different preset instruments in a declarative, JSON-configured way.

The goal: load a MIDI file, parse its tracks, map each track to a different `SpatialPreset` (each backed by a different `PresetSyntax`), and play the result through the existing spatial audio engine. The mapping is defined in a JSON configuration file that lives alongside the preset JSON files.

## Architecture Overview

```
                     JSON config file
                           |
                           v
                  MidiScoreSyntax (Codable)
                           |
                    .compile(engine:)
                           |
                           v
                      MidiScore
                     /    |    \
          SpatialPreset  ...  SpatialPreset   (one per mapped track)
                     \    |    /
                      Sequencer
                     (AVAudioSequencer with per-track routing)
```

The system introduces two layers:

1. **MidiScoreSyntax** -- a `Codable` struct decoded from a JSON file. It declares which MIDI file to use, the tempo/rate, and a list of track-to-preset mappings.
2. **MidiScore** -- the runtime object that owns the compiled `SpatialPreset` instances and the `Sequencer`, wiring them together. It is the thing you `play()` and `stop()`.

## Data Model

### MidiScoreSyntax (JSON-decodable configuration)

```swift
/// Declares how a MIDI file maps to presets.
/// Lives in Resources/scores/ as a JSON file.
struct MidiScoreSyntax: Codable {
  let name: String
  let midiFile: String              // e.g. "BachInvention1" (no extension)
  let rate: Double?                 // playback rate multiplier (default 1.0)
  let trackMappings: [TrackMapping]

  struct TrackMapping: Codable {
    let trackIndex: Int             // 0-based index into the MIDI file's tracks
    let presetFile: String          // e.g. "5th_cluedo.json"
    let transpose: Int?             // semitone offset (default 0)
    let velocityScale: Double?      // multiplier on velocity (default 1.0)
    let numVoices: Int?             // override SpatialPreset voice count (default 12)
  }
}
```

Design notes on `TrackMapping`:

- `trackIndex` refers to the track index *after* `AVAudioSequencer` loads the file. When using `.smf_ChannelsToTracks`, each MIDI channel becomes its own track, so the indices may differ from what a DAW shows as "Track 1, Track 2, ...". The `MidiInspectorView` already displays tracks by index, so the user can inspect a file and find the correct indices.
- `presetFile` is a filename in `Resources/presets/`. This reuses the existing `PresetSyntax` JSON format unchanged.
- `transpose` maps to the existing `NoteHandler.globalOffset` mechanism.
- `velocityScale` is a new per-track concept (not yet in `NoteHandler`). It can be applied in the MIDI callback before forwarding to the `NoteHandler`. If this is not worth the complexity initially, it can be deferred.

### MidiScore (runtime object)

```swift
/// Runtime object that owns compiled presets and the sequencer for MIDI file playback.
@Observable
class MidiScore {
  let syntax: MidiScoreSyntax
  let engine: SpatialAudioEngine
  private(set) var spatialPresets: [Int: SpatialPreset] = [:]  // trackIndex -> SpatialPreset
  private(set) var sequencer: Sequencer?

  init(syntax: MidiScoreSyntax, engine: SpatialAudioEngine) { ... }
  func compile() { ... }
  func play() { ... }
  func stop() { ... }
  func cleanup() { ... }
}
```

### How MidiScore.compile() works

```swift
func compile() {
  // 1. Load PresetSyntax for each mapping
  // 2. Create a SpatialPreset for each mapping
  // 3. Count MIDI tracks (use MidiParser to inspect, or just use max trackIndex + 1)
  // 4. Create a Sequencer with engine and a dummy default handler
  //    (or use the first mapping's SpatialPreset as default)
  // 5. Wire each track to its SpatialPreset via sequencer.setHandler(_:forTrack:)
  // 6. Apply transpose offsets

  let midiURL = Bundle.main.url(forResource: syntax.midiFile, withExtension: "mid")!

  // Determine track count from the MIDI file
  let parser = MidiParser(url: midiURL)!
  let trackCount = parser.tracks.count

  // Create a silent default handler for unmapped tracks
  let silentHandler = SilentNoteHandler()

  sequencer = Sequencer(
    engine: engine.audioEngine,
    numTracks: trackCount,
    defaultHandler: silentHandler
  )

  for mapping in syntax.trackMappings {
    let presetSpec = Bundle.main.decode(
      PresetSyntax.self,
      from: mapping.presetFile,
      subdirectory: "presets"
    )
    let numVoices = mapping.numVoices ?? 12
    let spatial = SpatialPreset(
      presetSpec: presetSpec,
      engine: engine,
      numVoices: numVoices
    )
    spatial.globalOffset = mapping.transpose ?? 0
    spatialPresets[mapping.trackIndex] = spatial
    sequencer?.setHandler(spatial, forTrack: mapping.trackIndex)
  }
}
```

### SilentNoteHandler

The existing `Sequencer` requires a `NoteHandler` as its default listener. For `MidiScore` usage, unmapped tracks should produce no sound. A trivial implementation:

```swift
class SilentNoteHandler: NoteHandler {
  var globalOffset: Int = 0
  func noteOn(_ note: MidiNote) {}
  func noteOff(_ note: MidiNote) {}
}
```

This avoids allocating a full `SpatialPreset` with audio nodes for tracks that are intentionally silent.

## Integration with Existing Sequencer

The `Sequencer` class already supports per-track `NoteHandler` routing via `setHandler(_:forTrack:)` and `MIDICallbackInstrument`. Each `MIDICallbackInstrument` creates its own virtual MIDI endpoint, and `play()` assigns each track's `destinationMIDIEndpoint` to the appropriate listener.

The flow for MIDI-file-driven playback:

```
MIDI file track 0  -->  MIDICallbackInstrument(handler: spatialPresetA)  -->  SpatialPresetA.noteOn/Off
MIDI file track 1  -->  MIDICallbackInstrument(handler: spatialPresetB)  -->  SpatialPresetB.noteOn/Off
MIDI file track 2  -->  MIDICallbackInstrument(handler: silentHandler)   -->  (nothing)
...
```

Each `SpatialPreset` manages its own pool of `Preset` instances (each with its own effects chain and spatial position), connected to the shared `SpatialAudioEngine`'s `AVAudioEnvironmentNode`.

**No changes to Sequencer are strictly required.** The existing `setHandler(_:forTrack:)` API is sufficient. Two small improvements would help:

1. **`SilentNoteHandler`** (described above) to avoid allocating a full `SpatialPreset` for unmapped tracks.
2. **Rate control**: `MidiScore` sets `sequencer.avSeq.rate` from `syntax.rate ?? 1.0`.

## Integration with SyntacticSynth

`SyntacticSynth` is a UI-bound wrapper around a single `SpatialPreset` with `@Observable` properties for knob bindings. For MIDI-file-driven playback, `SyntacticSynth` is **not** directly involved. Each track's `SpatialPreset` is created directly from `PresetSyntax.compile()`, bypassing `SyntacticSynth`.

If live editing of a track's preset parameters is desired later, a `SyntacticSynth` could wrap one of the `MidiScore`'s `SpatialPreset` instances. But this is a separate UI concern, not part of the core playback system.

## Relationship to MusicPattern / PatternSyntax

`MusicPattern` is the generative playback system: it uses iterator-based note/sustain/gap sequences to produce `MusicEvent` objects in an async loop. It operates at a higher abstraction level than MIDI file playback.

The two systems are complementary, not overlapping:

| Concern | MusicPattern | MidiScore |
|---------|-------------|-----------|
| Note source | Iterator sequences (generative) | MIDI file (pre-composed) |
| Timing | `Task.sleep` based on gap iterators | `AVAudioSequencer` tempo-synced |
| Preset routing | Single `SpatialPreset` per pattern | Multiple `SpatialPreset`s via track mapping |
| Modulation | Per-event modulators via `handles` | Not applicable (static preset params) |
| Tempo | Implicit in gap values | From MIDI file + rate multiplier |

A future `PatternSyntax` (JSON-declarable pattern configurations) would serialize the parameters that currently live in `SongView`'s inline `MusicPattern` construction. That is orthogonal to MIDI file playback and would not share a data model with `MidiScoreSyntax`.

The two could coexist in a "song" configuration that layers generative patterns over MIDI file playback, each with their own `SpatialPreset` instances connected to the same `SpatialAudioEngine`.

## Tempo and Time Signature

`AVAudioSequencer` respects tempo events embedded in the MIDI file. The existing `MidiParser` already extracts tempo (from `ExtendedTempoEvent`) and time signature (from meta event `0x58`).

For `MidiScore` playback:
- Tempo is handled automatically by `AVAudioSequencer` from the MIDI file's tempo track.
- `MidiScoreSyntax.rate` acts as a multiplier on top of the file's native tempo (via `avSeq.rate`).
- Time signature is informational (for display in `MidiInspectorView`), not needed for playback.

No additional tempo handling code is needed.

## New Files

| File | Purpose |
|------|---------|
| `Sources/Generators/MidiScore.swift` | `MidiScoreSyntax`, `MidiScore`, `SilentNoteHandler` |
| `Resources/scores/` | Directory for score JSON files |

Only one new Swift file is needed. The existing `MidiParser` (in `MidiInspectorView.swift`) could be extracted to its own file for reuse, but that is a minor refactor, not a requirement.

## JSON Configuration Format

### Score configuration file (e.g. `Resources/scores/bach_invention1_score.json`)

```json
{
  "name": "Bach Invention No. 1",
  "midiFile": "BachInvention1",
  "rate": 0.8,
  "trackMappings": [
    {
      "trackIndex": 0,
      "presetFile": "5th_cluedo.json",
      "transpose": 0,
      "numVoices": 12
    },
    {
      "trackIndex": 1,
      "presetFile": "GeneralUser00Piano.json",
      "transpose": -12,
      "numVoices": 8
    }
  ]
}
```

### Example: Sanctus with three instruments

```json
{
  "name": "Sanctus (MSLF)",
  "midiFile": "MSLFSanctus",
  "rate": 1.0,
  "trackMappings": [
    {
      "trackIndex": 0,
      "presetFile": "saw.json",
      "transpose": 0,
      "numVoices": 12
    },
    {
      "trackIndex": 1,
      "presetFile": "GeneralUser06Harpsichord.json",
      "transpose": 0,
      "numVoices": 8
    },
    {
      "trackIndex": 2,
      "presetFile": "triangle.json",
      "transpose": 12,
      "numVoices": 6
    },
    {
      "trackIndex": 3,
      "presetFile": "GeneralUser09Glock.json",
      "transpose": 0,
      "numVoices": 4
    }
  ]
}
```

### Example: All My Loving with sampler + synth layering

```json
{
  "name": "All My Loving",
  "midiFile": "All-My-Loving",
  "rate": 1.0,
  "trackMappings": [
    {
      "trackIndex": 0,
      "presetFile": "GeneralUser00Piano.json",
      "transpose": 0
    },
    {
      "trackIndex": 1,
      "presetFile": "5th_cluedo.json",
      "transpose": 0
    }
  ]
}
```

### Example: Minimal (single track, using defaults)

```json
{
  "name": "D Loop",
  "midiFile": "D_Loop_01",
  "trackMappings": [
    {
      "trackIndex": 0,
      "presetFile": "auroraBorealis.json"
    }
  ]
}
```

## Integration Points with Existing Code

### Files that need changes

1. **`Sources/Generators/MidiScore.swift`** (new file)
   - `MidiScoreSyntax` struct
   - `MidiScore` class
   - `SilentNoteHandler` class

2. **`Sources/SongView.swift`** (modified)
   - Add a "Scores" button or list to load score JSON files (similar to how preset JSON files are listed in `PresetListView`)
   - Add `MidiScore` state management (compile, play, stop, cleanup)

3. **`Sources/MidiInspectorView.swift`** (optional refactor)
   - Extract `MidiParser` to a shared file if reuse is desired
   - Or just use `AVAudioSequencer`'s track count directly in `MidiScore`

### Files that remain unchanged

- `AppleAudio/Sequencer.swift` -- already supports per-track handler routing
- `AppleAudio/SpatialPreset.swift` -- already conforms to `NoteHandler`
- `AppleAudio/Preset.swift` -- `PresetSyntax.compile()` already works
- `AppleAudio/SpatialAudioEngine.swift` -- shared engine, no changes
- `Synths/SyntacticSynth.swift` -- not involved in MIDI score playback
- `Generators/Pattern.swift` -- independent system, no changes
- All existing preset JSON files -- reused as-is

### Existing code reused directly

| Component | How it is reused |
|-----------|-----------------|
| `PresetSyntax` | Decoded from JSON, compiled via `.compile(numVoices:)` |
| `SpatialPreset` | Created per mapped track, receives `noteOn`/`noteOff` from `Sequencer` |
| `Sequencer` | Loads MIDI file, routes tracks via `setHandler(_:forTrack:)` |
| `MIDICallbackInstrument` (AudioKit) | Created internally by `Sequencer.createListener(for:)` |
| `VoiceLedger` | Used internally by `SpatialPreset` and `Preset` for voice allocation |
| `Bundle.decode(_:from:subdirectory:)` | Loads score JSON and preset JSON files |
| `SpatialAudioEngine` | Shared engine, all `SpatialPreset` mixer nodes connect to its `envNode` |

## UI Sketch (SongView integration)

```swift
// In SongView, alongside existing "Play Pattern" button:

@State private var midiScore: MidiScore? = nil

// ... in body:
Button("Play Score") {
  let scoreSyntax = Bundle.main.decode(
    MidiScoreSyntax.self,
    from: "bach_invention1_score.json",
    subdirectory: "scores"
  )
  let score = MidiScore(syntax: scoreSyntax, engine: synth.engine)
  score.compile()
  score.play()
  midiScore = score
}

Button("Stop Score") {
  midiScore?.stop()
  midiScore?.cleanup()
  midiScore = nil
}
```

A `ScoreListView` (analogous to `PresetListView`) could enumerate `Resources/scores/*.json` and let the user pick a score to play.

## CPU Budget Considerations

Each mapped track creates a `SpatialPreset` with N voices. For Arrow-based presets, each voice compiles a full DSP graph. A 4-track MIDI file with 12 voices per track means 48 Arrow DSP graphs running simultaneously, plus effects chains.

Mitigations already in place:
- `AudioGate` on each `Preset` returns silence when no notes are active (the `isSilence = true` optimization).
- `VoiceLedger` limits active voices to the pool size.
- Sampler-based presets use `AVAudioUnitSampler` which is hardware-optimized.

Additional mitigations for the score system:
- `numVoices` in `TrackMapping` lets the user reduce voice count per track.
- Tracks that play single-note melodies can use `numVoices: 4` instead of the default 12.
- Sampler presets (`GeneralUser*.json`) are much cheaper than Arrow presets for polyphonic parts.

## Summary

The design adds one new concept (`MidiScoreSyntax` / `MidiScore`) that composes existing primitives (`PresetSyntax`, `SpatialPreset`, `Sequencer`). No changes to the audio pipeline or existing classes are required. The JSON configuration format is minimal and reuses existing preset files by reference. The `AVAudioSequencer` handles tempo, timing, and MIDI event dispatch; the new code wires tracks to the appropriate `NoteHandler` instances.
