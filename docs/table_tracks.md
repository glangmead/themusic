# tableTracks — Stochastic Generative Sequencing

`tableTracks` is one of three pattern types in Orbital (alongside `midiTracks` and `scoreTracks`). It is designed for patterns that evolve continuously and unpredictably — the music is never the same twice. Instead of writing out exact notes, you define named generators (*emitters*) and connect them to tracks. At runtime, each emitter produces a fresh value every time it is called.

The system is organized as four sections, each building on the previous: **Emitters** define value generators; **Note Materials** combine emitters with musical theory to produce pitches; **Preset Modulators** feed emitter values into instrument parameters; **Tracks** wire everything together into a playing voice.

---

## Top-Level Structure

```json
{
  "name": "My Pattern",
  "tableTracks": {
    "name": "My Pattern",
    "hierarchy": { ... },
    "emitters": [ ... ],
    "hierarchyModulators": [ ... ],
    "noteMaterials": [ ... ],
    "presetModulators": [ ... ],
    "tracks": [ ... ]
  }
}
```

| Field | Required | Description |
|---|---|---|
| `name` | yes | Name of this table pattern |
| `hierarchy` | no | Shared musical context (key + chord); required for `hierarchyMelody`/`hierarchyChord` note materials |
| `emitters` | yes | Named value generators |
| `hierarchyModulators` | no | Timed events that mutate the shared hierarchy |
| `noteMaterials` | yes | Named note producers, each backed by a hierarchy query |
| `presetModulators` | yes | Named connections from emitters to instrument parameter handles |
| `tracks` | yes | Instrument tracks, each wiring a preset, note material, sustain emitter, and gap emitter |

---

## Section 1: Emitters

Emitters are named value generators. Each one produces a single float or integer on demand. Emitters are referenced by name throughout the other sections.

```json
"emitters": [
  {
    "name": "gap",
    "outputType": "float",
    "function": "randFloat",
    "arg1": 0.2,
    "arg2": 0.5
  },
  {
    "name": "degreePicker",
    "outputType": "int",
    "function": "shuffle",
    "candidates": ["0", "1", "2", "3", "4", "5", "6"]
  }
]
```

### Output Types

| `outputType` | Swift type | Used for |
|---|---|---|
| `float` | `CoreFloat` | Sustain times, gap times, modulator values |
| `int` | `Int` | Degree indices, interval indices |
| `octave` | `Int` | Octave numbers (treated as int, but semantically an octave) |

### Emitter Functions

#### `randFloat`
Generates a uniformly random float between `arg1` and `arg2`.

```json
{ "name": "sustain", "outputType": "float", "function": "randFloat", "arg1": 3, "arg2": 8 }
```

#### `exponentialRandFloat`
Generates a random float with an exponential distribution, biased toward `arg1`, with `arg2` as the upper bound. Useful for amplitude values that feel more natural when spending more time near the quieter end.

```json
{ "name": "ampVal", "outputType": "float", "function": "exponentialRandFloat", "arg1": 0.3, "arg2": 0.6 }
```

#### `randInt`
Generates a uniformly random integer between `arg1` and `arg2` (inclusive).

```json
{ "name": "picker", "outputType": "int", "function": "randInt", "arg1": 0, "arg2": 6 }
```

#### `random`
Picks uniformly at random from the `candidates` array. Unlike `randInt`, this lets you weight outcomes by repeating values.

```json
{
  "name": "octaves",
  "outputType": "octave",
  "function": "random",
  "candidates": ["2", "2", "3", "3", "3", "4", "4"]
}
```

Here octave 3 is three times more likely than octave 2 or 4.

#### `shuffle`
Works through the `candidates` array in a shuffled (random permutation) order, then reshuffles and repeats. Every value appears exactly once per cycle — a balanced but still random feel.

```json
{
  "name": "degreePicker",
  "outputType": "int",
  "function": "shuffle",
  "candidates": ["0", "1", "2", "3", "4", "5", "6"]
}
```

#### `cyclic`
Steps through the `candidates` array in order, looping from the end back to the start. Deterministic and metronomic.

```json
{
  "name": "gap",
  "outputType": "float",
  "function": "cyclic",
  "candidates": ["1.0", "1.0", "1.0", "2.0"]
}
```

This produces three notes of gap 1.0 seconds, then one of 2.0 seconds, then repeats.

#### `sum`
Takes two `inputEmitters` by name and adds their values. Useful for combining octave shifts or amplitude offsets.

```json
{
  "name": "octavePlus",
  "outputType": "float",
  "function": "sum",
  "inputEmitters": ["baseOctave", "octaveShift"]
}
```

#### `reciprocal`
Takes one `inputEmitters` entry and computes `1 / value`. Useful for inverting a value, e.g., making amplitude decrease as octave increases.

```json
{
  "name": "octaveAmpVal",
  "outputType": "float",
  "function": "reciprocal",
  "inputEmitters": ["octavePlusOne"]
}
```

#### `indexPicker(emitter:)`
Uses an `int`-typed emitter to index into `candidates`. The emitter provides the index; the candidates provide the values.

```json
{
  "name": "rootNote",
  "outputType": "float",
  "function": "indexPicker",
  "inputEmitters": ["indexEmitter"],
  "candidates": ["C", "E", "G"]
}
```

### Update Modes

The `updateMode` field controls when an emitter produces a new value. If omitted, the default is `each`.

#### `each`
The emitter produces a new value every time it is called (approximately every 15 ms in the engine's modulator loop). This gives continuous, evolving values.

#### `waiting(emitter:)`
The emitter only updates its output when a named float emitter fires (crosses a threshold). Until then, it latches its last value. This lets you synchronize multiple emitters so they all change at the same moment — useful for root note changes where melody and harmony should agree.

```json
{
  "name": "root",
  "outputType": "float",
  "function": "random",
  "candidates": ["C", "E", "G"],
  "updateMode": { "waiting": { "emitter": "gapTimer" } }
}
```

---

## Section 2: Hierarchy

The `hierarchy` object defines the shared musical context. All note materials and hierarchy modulators operate on this single shared state.

```json
"hierarchy": {
  "root": "C",
  "scale": "lydian",
  "chord": { "degrees": [0, 2, 4], "inversion": 0 }
}
```

| Field | Description |
|---|---|
| `root` | Starting tonic (note name: "C", "Bb", "F#", etc.) |
| `scale` | Scale name ("major", "minor", "lydian", "dorian", "mixolydian", etc.) |
| `chord.degrees` | 0-based scale degree indices that form the current chord |
| `chord.inversion` | 0 = root position, 1 = first inversion, etc. |

The hierarchy is mutable at runtime via hierarchy modulators (see below). Multiple tracks share the same hierarchy, so they automatically stay in sync harmonically.

---

## Section 3: Hierarchy Modulators

Hierarchy modulators are timed events that mutate the shared hierarchy state. They fire on a timer provided by a float emitter, so the rate of change is itself stochastic.

```json
"hierarchyModulators": [
  {
    "name": "chordShifter",
    "level": "chord",
    "operation": "markovChord",
    "n": 1,
    "fireIntervalEmitter": "gap"
  }
]
```

| Field | Description |
|---|---|
| `name` | Identifier for this modulator |
| `level` | What layer to target: `"scale"` or `"chord"` |
| `operation` | What mutation to apply |
| `n` | Integer parameter for the operation |
| `fireIntervalEmitter` | Name of a float emitter; its value (in seconds) becomes the interval between fires |

### Hierarchy Operations

| `operation` | Effect |
|---|---|
| `T` | Diatonic transposition: shift each chord degree up by `n` scale steps |
| `t` | Chromatic transposition: shift the root by `n` semitones |
| `L` | Move to the next scale in a sequence (level must be `scale`) |
| `markovChord` | Use a Markov chain to pick the next chord from music-theoretically plausible successors |

`markovChord` is the most powerful option. It selects the next chord using weighted transitions based on common practice voice-leading tendencies. The `n` parameter controls how many steps the Markov chain takes (usually 1).

---

## Section 4: Note Materials

Note materials define what pitches a track will play. Each note material references the shared hierarchy and one or more emitters.

There are two types: `hierarchyMelody` (single notes) and `hierarchyChord` (voiced chords).

### `hierarchyMelody`

Produces one note per event, selected by degree from either the current scale or the current chord.

```json
{
  "type": "hierarchyMelody",
  "name": "melody",
  "level": "scale",
  "degreeEmitter": "degreePicker",
  "octaveEmitter": "octaves"
}
```

| Field | Description |
|---|---|
| `name` | Identifier |
| `level` | `"scale"` picks from the full 7-note scale; `"chord"` picks only from chord tones |
| `degreeEmitter` | An `int` emitter whose value is the 0-based degree index |
| `octaveEmitter` | An `octave` emitter whose value is the MIDI octave number |

When `level` is `"scale"`, degree 0 is the tonic, degree 4 is the fifth, degree 6 is the leading tone, etc. When `level` is `"chord"`, degree 0 is the lowest chord degree, degree 1 the next, etc.

### `hierarchyChord`

Produces all the notes of the current chord simultaneously, as a voiced spread.

```json
{
  "type": "hierarchyChord",
  "name": "chords",
  "voicing": "spread",
  "octaveEmitter": "octaves"
}
```

| Field | Description |
|---|---|
| `name` | Identifier |
| `voicing` | How notes are distributed across octaves (see Voicing Styles below) |
| `octaveEmitter` | An `octave` emitter setting the base octave of the chord |

### Voicing Styles

| Style | Description |
|---|---|
| `closed` | All tones in the smallest possible range |
| `open` | Alternate tones raised an octave |
| `dropTwo` | The second-highest voice drops an octave |
| `spread` | Voices spread across two octaves |
| `shell` | Root and seventh only |
| `fifthsOnly` | Root and fifth only |

---

## Section 5: Preset Modulators

Preset modulators connect emitter values to instrument parameter handles at note time. Every time a note fires, the track's modulators are evaluated and their values are pushed to the instrument.

There are two ways to wire a modulator: the `floatEmitter` path (direct) and the `arrow` path (expression tree).

### floatEmitter path

```json
{
  "name": "ampMod",
  "targetHandle": "overallAmp",
  "floatEmitter": "overallAmpVal"
}
```

The named emitter's current value is sent directly to the `targetHandle` parameter on the instrument.

### arrow path

For computed values, use an `arrow` expression tree instead of a simple emitter reference:

```json
{
  "name": "octaveAmpMod",
  "targetHandle": "overallAmp2",
  "arrow": {
    "reciprocal": {
      "sum": [
        { "const": { "name": "one", "val": 1 } },
        { "emitterValue": { "name": "octaves" } }
      ]
    }
  }
}
```

This computes `1 / (1 + octaves)` — higher octaves get lower amplitude. Arrow trees support `const`, `emitterValue`, `sum` (array of sub-arrows), and `reciprocal` (single sub-arrow).

### Meta-modulation

A modulator can target another emitter's parameter instead of an instrument handle, by using a dotted `targetHandle`:

```json
{
  "name": "gapMaxMod",
  "targetHandle": "gap.max",
  "floatEmitter": "someOtherEmitter"
}
```

This sets the `max` field of the emitter named `gap` at note time. Useful for dynamically changing the range of a random emitter based on musical state.

---

## Section 6: Tracks

Tracks are the final wiring step. Each track names a preset, picks a note material, names its sustain and gap emitters, and lists which preset modulators to apply.

```json
{
  "name": "Aurora Arpeggio",
  "presetFilename": "auroraBorealis",
  "numVoices": 3,
  "presetModulatorNames": ["ampMod", "octaveAmpMod", "vibAmpMod", "vibFreqMod"],
  "noteMaterial": "melody",
  "sustainEmitter": "sustain",
  "gapEmitter": "gap"
}
```

| Field | Description |
|---|---|
| `name` | Display name |
| `presetFilename` | Instrument preset to load |
| `numVoices` | Maximum simultaneous voices; voice stealing applies above this |
| `presetModulatorNames` | Ordered list of modulator names to apply at each note event |
| `noteMaterial` | Name of the note material to use for pitch generation |
| `sustainEmitter` | Name of a float emitter; its value (in seconds) is the note-on duration |
| `gapEmitter` | Name of a float emitter; its value (in seconds) is the silence after note-off |

The track fires continuously: play → sustain → gap → play → sustain → gap → ... The sustain and gap emitters are polled fresh on each cycle, so the rhythm is naturally stochastic when their functions are random.

---

## Worked Examples

### Example 1: Minimal Pulse (`minimal_pulse.json`)

A simple cyclic arpeggio through C major triad tones. Everything is deterministic (`cyclic`), making it useful for understanding the structure.

```json
"emitters": [
  { "name": "degreePicker", "outputType": "int",   "function": "cyclic", "candidates": ["0", "2", "4"] },
  { "name": "octaves",      "outputType": "octave", "function": "cyclic", "candidates": ["4"] },
  { "name": "sustain",      "outputType": "float",  "function": "randFloat", "arg1": 0.8, "arg2": 0.8 },
  { "name": "gap",          "outputType": "float",  "function": "cyclic", "candidates": ["1.0", "1.0", "1.0", "2.0"] }
]
```

`degreePicker` steps through degrees 0→2→4→0→2→4→... `gap` cycles through three 1-second gaps then a 2-second gap, creating a 5-beat rhythmic feel.

```json
"noteMaterials": [
  { "type": "hierarchyMelody", "name": "pulse", "level": "scale",
    "degreeEmitter": "degreePicker", "octaveEmitter": "octaves" }
]
```

Because `level` is `"scale"`, the degrees 0/2/4 pick the 1st, 3rd, and 5th scale degrees — C, E, G in C major.

---

### Example 2: Aurora Arpeggio (`aurora_arpeggio.json`)

A shimmering arpeggio using `shuffle` for even-but-random degree selection, plus an `arrow` modulator that makes higher octaves quieter.

```json
"hierarchy": { "root": "C", "scale": "lydian", "chord": {"degrees": [0,2,4], "inversion": 0} }
```

The `shuffle` degree picker:
```json
{ "name": "degreePicker", "outputType": "int", "function": "shuffle",
  "candidates": ["0","1","2","3","4","5","6"] }
```

All 7 scale degrees appear in each random permutation cycle. In Lydian, this includes the characteristic raised 4th.

The octave amplitude modulator uses the arrow syntax to compute `1 / (1 + octave)`:
```json
{
  "name": "octaveAmpMod",
  "targetHandle": "overallAmp2",
  "arrow": { "reciprocal": { "sum": [
    { "const": { "name": "one", "val": 1 } },
    { "emitterValue": { "name": "octaves" } }
  ]}}
}
```

When `octaves` emits 4, the result is `1/(1+4) = 0.2`. When it emits 2, it's `1/(1+2) = 0.33`. Higher octave notes automatically get a lower amplitude, creating a natural register-based fade.

---

### Example 3: Baroque Chords (`baroque_chords.json`)

Full voiced chords evolving via `markovChord`, creating a continuously changing but harmonically coherent harmonic texture.

```json
"hierarchy": { "root": "C", "scale": "major", "chord": {"degrees": [0,2,4], "inversion": 0} }
```

The hierarchy modulator uses the `gap` emitter as its fire interval, so chord changes happen at the same rate as note changes:

```json
"hierarchyModulators": [
  { "name": "chordShifter", "level": "chord", "operation": "markovChord",
    "n": 1, "fireIntervalEmitter": "gap" }
]
```

The note material plays the whole voiced chord:
```json
{ "type": "hierarchyChord", "name": "chords", "voicing": "spread", "octaveEmitter": "octaves" }
```

The `spread` voicing distributes chord tones across two octaves. The `octaves` emitter (weighted toward octave 3) controls the base register.

Two preset modulators provide per-note amplitude variation and a random detune:
```json
{ "name": "ampMod",    "targetHandle": "overallAmp",        "floatEmitter": "overallAmpVal" },
{ "name": "detuneMod", "targetHandle": "overallCentDetune", "floatEmitter": "detuneVal" }
```

`detuneVal` ranges from -5 to +5 cents, giving a subtle organic drift to the tuning.

---

## Summary: How Data Flows

At runtime, each track runs a continuous loop:

1. **Gap fires**: the `gapEmitter` determines how many seconds to wait before the next note.
2. **Modulators evaluate**: each preset modulator queries its emitter (or arrow expression) and pushes the value to the instrument handle.
3. **Note material queries hierarchy**: the note material asks the shared hierarchy (possibly just updated by a hierarchy modulator) for the current key and chord state.
4. **Pitch resolution**: the degree emitter and octave emitter are called; the resulting scale/chord position is mapped to MIDI pitches.
5. **Note on**: the MIDI note fires.
6. **Sustain fires**: the `sustainEmitter` determines how long the note rings.
7. **Note off**: the note is released.
8. **Return to step 1**.

The hierarchy modulators run on their own independent timers, mutating the shared harmony state. Because both the note-material query and the chord-change timer are driven by the same `gap` emitter in `baroque_chords.json`, they stay naturally synchronized. When they use different timers, they can drift pleasingly out of phase.
