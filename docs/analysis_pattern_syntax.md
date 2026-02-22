# PatternSyntax Design Document

## Overview

PatternSyntax is a Codable serialization layer for MusicPattern, following the same compile() paradigm as PresetSyntax -> Preset. A PatternSyntax struct is decoded from JSON and compiled into a live MusicPattern (plus its backing SpatialPreset) ready for playback.

## Existing Architecture Summary

The compilation chain for sounds:
- JSON file -> `PresetSyntax` (Codable) -> `PresetSyntax.compile()` -> `Preset`
- `ArrowSyntax` (Codable enum) -> `ArrowSyntax.compile()` -> `ArrowWithHandles`

The runtime playback chain:
- `MusicPattern` is an actor that owns: a `SpatialPreset`, modulators (`[String: Arrow11]`), and three iterators for notes, sustains, and gaps.
- `MusicPattern.play()` loops: calls `next()` to get a `MusicEvent`, then plays it asynchronously while sleeping for the gap duration.
- `MusicEvent` applies modulators to the preset's named constants, calls `notesOn`, sleeps for sustain, calls `notesOff`.

## Design

### PatternSyntax (top-level Codable struct)

```
PatternSyntax
  name: String
  presetName: String              -- references a preset JSON by name (not embedded)
  numVoices: Int?                 -- optional, defaults to 12
  noteGenerator: NoteGeneratorSyntax
  sustain: TimingSyntax
  gap: TimingSyntax
  modulators: [ModulatorSyntax]?  -- optional parameter modulation
```

### NoteGeneratorSyntax (Codable enum)

Represents different ways to generate sequences of `[MidiNote]`:

```
NoteGeneratorSyntax
  case fixed(events: [ChordSyntax])           -- explicit list of chords, cycled
  case scaleSampler(scale: String, root: String, octaves: [Int])
  case chordProgression(scale: String, root: String, style: String)
  case melodic(scale: String, root: String, octaves: [Int], degrees: [Int], ordering: String)
```

- `fixed`: A literal list of chords/notes. Each `ChordSyntax` is `{ notes: [NoteSyntax] }` where `NoteSyntax` is `{ midi: UInt8, velocity: UInt8 }`. The list cycles.
- `scaleSampler`: Random notes from a scale. Maps to `ScaleSampler` but with configurable scale/root.
- `chordProgression`: Maps to `Midi1700sChordGenerator` (style: "baroque") or future progression styles.
- `melodic`: Maps to `MidiPitchAsChordGenerator` wrapping `MidiPitchGenerator` with configurable ordering ("cyclic", "random", "shuffled").

### ChordSyntax / NoteSyntax

```
ChordSyntax
  notes: [NoteSyntax]

NoteSyntax
  midi: UInt8
  velocity: UInt8?    -- defaults to 127
```

### TimingSyntax (Codable enum)

Controls sustain and gap durations:

```
TimingSyntax
  case fixed(value: CoreFloat)                    -- constant duration
  case random(min: CoreFloat, max: CoreFloat)     -- uniform random
  case list(values: [CoreFloat])                  -- cycled list
```

- `fixed` compiles to `[value].cyclicIterator()`
- `random` compiles to `FloatSampler(min:max:)`
- `list` compiles to `values.cyclicIterator()`

### ModulatorSyntax (Codable struct)

```
ModulatorSyntax
  target: String          -- named constant in the preset (e.g., "overallAmp", "vibratoFreq")
  arrow: ArrowSyntax      -- reuses the existing ArrowSyntax enum
```

This reuses the existing `ArrowSyntax` Codable enum for the modulating arrow, which already supports `const`, `rand`, `exponentialRand`, `noiseSmoothStep`, `prod`, `sum`, `compose`, etc.

### Compilation

`PatternSyntax.compile(spatialPreset:)` takes an already-constructed `SpatialPreset` (the caller is responsible for loading the preset by name and creating the SpatialPreset with the engine) and returns a `MusicPattern`.

Alternatively, a higher-level convenience:
`PatternSyntax.compile(presetSpec:engine:)` loads the PresetSyntax, creates the SpatialPreset, and returns `(MusicPattern, SpatialPreset)`.

### Preset Resolution

Patterns reference presets by name (the `name` field in a preset JSON file). The caller resolves the name to a `PresetSyntax` before calling compile. This separation keeps PatternSyntax independent of bundle loading and audio engine setup.

## File Layout

- `Sources/Generators/PatternSyntax.swift` -- all PatternSyntax types and compile()
- `Resources/patterns/aurora_arpeggio.json` -- melodic pattern example
- `Resources/patterns/baroque_chords.json` -- chord progression example
- `Resources/patterns/minimal_pulse.json` -- fixed note sequence example

## JSON Examples

### baroque_chords.json
```json
{
  "name": "Baroque Chords",
  "presetName": "5th_cluedo",
  "noteGenerator": {
    "chordProgression": {
      "scale": "major",
      "root": "C",
      "style": "baroque"
    }
  },
  "sustain": { "random": { "min": 3.0, "max": 8.0 } },
  "gap":     { "random": { "min": 4.0, "max": 10.0 } },
  "modulators": [
    {
      "target": "overallAmp",
      "arrow": { "exponentialRand": { "min": 0.3, "max": 0.6 } }
    }
  ]
}
```

### aurora_arpeggio.json
```json
{
  "name": "Aurora Arpeggio",
  "presetName": "auroraBorealis",
  "numVoices": 20,
  "noteGenerator": {
    "melodic": {
      "scale": "lydian",
      "root": "C",
      "octaves": [2, 2, 2, 3, 3, 3, 3, 4, 4, 5],
      "degrees": [0, 1, 2, 3, 4, 5, 6],
      "ordering": "shuffled"
    }
  },
  "sustain": { "random": { "min": 5.0, "max": 10.0 } },
  "gap":     { "random": { "min": 5.0, "max": 10.0 } },
  "modulators": [
    {
      "target": "overallAmp",
      "arrow": { "exponentialRand": { "min": 0.3, "max": 0.6 } }
    },
    {
      "target": "vibratoAmp",
      "arrow": { "exponentialRand": { "min": 0.002, "max": 0.1 } }
    },
    {
      "target": "vibratoFreq",
      "arrow": { "rand": { "min": 1.0, "max": 25.0 } }
    }
  ]
}
```

### minimal_pulse.json
```json
{
  "name": "Minimal Pulse",
  "presetName": "sine",
  "noteGenerator": {
    "fixed": {
      "events": [
        { "notes": [{ "midi": 60, "velocity": 100 }] },
        { "notes": [{ "midi": 64, "velocity": 90 }] },
        { "notes": [{ "midi": 67, "velocity": 80 }] },
        { "notes": [{ "midi": 60, "velocity": 100 }, { "midi": 64, "velocity": 90 }, { "midi": 67, "velocity": 80 }] }
      ]
    }
  },
  "sustain": { "fixed": { "value": 0.8 } },
  "gap":     { "list": { "values": [1.0, 1.0, 1.0, 2.0] } }
}
```

## Scale and Root Name Mapping

Scale names map to Tonic's `Scale` type:
- "major" -> Scale.major
- "minor" / "aeolian" -> Scale.aeolian
- "lydian" -> Scale.lydian
- "dorian" -> Scale.dorian
- "mixolydian" -> Scale.mixolydian
- "phrygian" -> Scale.phrygian
- "locrian" -> Scale.locrian
- "harmonicMinor" -> Scale.harmonicMinor
- "melodicMinor" -> Scale.melodicMinor
- "pentatonicMajor" -> Scale.pentatonicMajor
- "pentatonicMinor" -> Scale.pentatonicMinor
- "chromatic" -> Scale.chromatic

Root names map to Tonic's `NoteClass`:
- "C" -> NoteClass.C, "D" -> NoteClass.D, etc.
- "Cs" / "C#" -> NoteClass.Cs, "Eb" -> NoteClass.Eb, etc.

## Relationship to Existing Code

- PatternSyntax does NOT replace the existing MusicPattern. It is a serialization layer that compiles to MusicPattern, parallel to how PresetSyntax compiles to Preset.
- The existing hardcoded pattern in SongView.swift's "Play Pattern" button could eventually be replaced with a PatternSyntax loaded from JSON.
- The existing iterator infrastructure (cyclicIterator, randomIterator, shuffledIterator, FloatSampler, Midi1700sChordGenerator, MidiPitchGenerator, ScaleSampler) is reused by PatternSyntax.compile().
- ModulatorSyntax.arrow reuses the existing ArrowSyntax Codable enum and its compile() method.
