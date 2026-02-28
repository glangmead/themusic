# scoreTracks — Deterministic Beat-Based Sequencing

`scoreTracks` is one of three pattern types in Orbital (alongside `midiTracks` and `tableTracks`). It is designed for situations where you want to write out exact notes at exact beat positions — a traditional score-like approach — while still using Orbital's music-theoretic pitch system for harmony-relative note types.

Unlike `tableTracks`, which produces notes stochastically at runtime, `scoreTracks` patterns are compiled once to a fixed sequence of MIDI events. The sequence then loops (or plays once) according to the `loop` flag.

---

## Top-Level Structure

```json
{
  "name": "My Pattern",
  "scoreTracks": {
    "bpm": 90,
    "totalBeats": 16,
    "loop": true,
    "key": { "root": "C", "scale": "major" },
    "chordEvents": [ ... ],
    "tracks": [ ... ]
  }
}
```

| Field | Type | Description |
|---|---|---|
| `bpm` | number | Tempo in beats per minute |
| `totalBeats` | number | Total length of the pattern; also the loop boundary |
| `loop` | bool | If `true`, the pattern loops from beat 0 after `totalBeats` |
| `key` | object | Starting key: `root` (note name) and `scale` (scale name) |
| `chordEvents` | array | Ordered list of harmony changes, placed at absolute beat positions |
| `tracks` | array | One or more instrument tracks, each with its own note list |

The `root` in `key` is a note name like `"C"`, `"Bb"`, or `"F#"`. The `scale` is a scale name like `"major"`, `"minor"`, `"lydian"`, `"dorian"`, etc.

---

## Chord Events

`chordEvents` is an array of events, each placed at an absolute beat position via the `beat` field. Events are processed in order; the harmony state at any given beat is determined by folding all events whose beat is ≤ that beat.

```json
"chordEvents": [
  { "beat": 0,  "op": "setChord", "degrees": [0, 2, 4], "inversion": 0 },
  { "beat": 4,  "op": "T", "n": 3 },
  { "beat": 8,  "op": "T", "n": 1 },
  { "beat": 12, "op": "setChord", "degrees": [0, 2, 4], "inversion": 0 }
]
```

### Chord Operations

| `op` | Extra fields | Effect |
|---|---|---|
| `setChord` | `degrees`, `inversion` | Replace the current chord with a specific set of scale degrees |
| `T` | `n` | Apply n diatonic transpositions to the chord (move each degree up by n steps in the scale) |
| `t` | `n` | Increase the inversion by n (rotate the bass voice up; `t(1)` = first inversion) |
| `Tt` | `n`, `tVal` | Apply n diatonic transpositions, then increase inversion by `tVal` |
| `setKey` | `root`, `scale` | Change the key entirely; chord is reset |
| `setRoman` | `roman` | Set the chord using a Roman numeral string in the current key |

**`setChord` degrees** use 0-based scale degree indices. The triad [0, 2, 4] is the 1st, 3rd, and 5th scale degrees (e.g., C-E-G in C major). The `inversion` field shifts the bass voice: 0 = root position, 1 = first inversion, 2 = second inversion.

**`T` (diatonic transposition)** moves every chord degree up by `n` diatonic steps. `T n=3` applied to [0,2,4] in C major gives [3,5,7] (F-A-C, the IV chord). This is the most idiomatic way to move through chord changes within a key.

**`t` (inversion)** increases the inversion count by `n`. The inversion controls which chord tone is in the bass: inversion 0 = root in bass, 1 = third in bass, 2 = fifth in bass. `t(1)` applied to root-position C-E-G puts E in the bass.

---

### `setRoman` — Roman Numeral Chord Notation

`setRoman` sets the current chord by parsing a standard Roman numeral string in the context of the current key. It is the most readable way to write harmonic progressions for tonal music.

```json
{ "beat": 0,  "op": "setRoman", "roman": "I" },
{ "beat": 4,  "op": "setRoman", "roman": "vi" },
{ "beat": 8,  "op": "setRoman", "roman": "ii6/5" },
{ "beat": 12, "op": "setRoman", "roman": "V7" }
```

#### Roman numeral syntax

**Scale degree:** Uppercase = major-quality chord, lowercase = minor-quality chord. The degree is determined by the numeral.

| Numeral | Scale degree (0-based) |
|---|---|
| `I` / `i` | 0 |
| `II` / `ii` | 1 |
| `III` / `iii` | 2 |
| `IV` / `iv` | 3 |
| `V` / `v` | 4 |
| `VI` / `vi` | 5 |
| `VII` / `vii` | 6 |

**Quality suffix:** `o` (diminished) or `/o` / `ø` (half-diminished). These affect the chord quality label but the diatonic scale degrees are still used for pitch resolution; the quality naturally emerges from the scale.

**Figured bass suffix:** Controls chord size and inversion:

| Suffix | Chord size | Inversion |
|---|---|---|
| (none) | triad | root position |
| `6` | triad | 1st inversion |
| `6/4` | triad | 2nd inversion |
| `7` | seventh chord | root position |
| `6/5` | seventh chord | 1st inversion |
| `4/3` | seventh chord | 2nd inversion |
| `2` | seventh chord | 3rd inversion |
| `9` | ninth chord | root position |

Combining quality and figures: `viio7` = fully-diminished leading-tone seventh, `ii/o6/5` = half-diminished supertonic seventh in first inversion.

#### Applied (secondary) chords

A `/TARGET` suffix tonicizes the chord to the scale degree indicated by `TARGET`. The current key is updated to the key of `TARGET` and persists until the next `setKey` or tonicizing chord event.

```json
{ "beat": 0,  "op": "setRoman", "roman": "V7/V" },
{ "beat": 2,  "op": "setKey",   "root": "C", "scale": "major" },
{ "beat": 2,  "op": "setRoman", "roman": "I" }
```

`V7/V` in C major: the target `V` (scale degree 4 = G) becomes a temporary major key. The chord `V7` is then voiced in G major (D-F#-A-C). The key persists as G major until the explicit `setKey` restores C major.

Uppercase target = tonicize to major; lowercase target = tonicize to minor:

| Applied chord | Home key | Resolved as |
|---|---|---|
| `V/V` | C major | V chord in G major |
| `V/vi` | C major | V chord in A minor |
| `viio7/V` | C major | viio7 chord in G major |
| `V6/5/IV` | C major | V6/5 chord in F major |

Multiple layers of application are parsed right-to-left at the last `/` preceding a Roman numeral letter. Applied chord targets may now carry a `b` or `#` prefix:

| Applied chord | Home key | Resolved as |
|---|---|---|
| `V/V` | C major | V chord in G major |
| `V/vi` | C major | V chord in A minor |
| `viio7/V` | C major | viio7 chord in G major |
| `V6/5/IV` | C major | V6/5 chord in F major |
| `V/bIII` | C major | V chord in E♭ major |

#### Chromatic harmony — flat/sharp prefix, Neapolitan, augmented sixths

`setRoman` handles chromatic chords via the **perturbation** system: each chord tone carries an integer semitone offset that is applied after the diatonic pitch is resolved. This makes chromatic chords sound correct without abandoning the scale-degree framework.

**Flat/sharp prefix chords** — `bII`, `bVII`, `#IV`, etc.:

The `b` or `#` prefix lowers or raises the chord root by one semitone from its diatonic position. All chord tones are adjusted to maintain the chord's quality (major/minor/diminished). For example, `bVII` in C major is a B♭ major triad: the root is lowered from B to B♭, while D and F are already in the right place.

```json
{ "beat": 0, "op": "setRoman", "roman": "bVII" }
```

**Neapolitan chord** — `N` and `N6`:

`N` is an alias for `bII` (flat-II major triad, root position). `N6` is an alias for `bII6` (first inversion). In C major, `N6` = D♭ major triad with F in the bass.

```json
{ "beat": 0, "op": "setRoman", "roman": "N6" }
```

**Augmented sixth chords** — `It6`, `Ger6/5`, `Ger7`, `Fr4/3`, `Fr6`:

These chromatic chords are defined by fixed pitch targets (semitones above the tonic), independent of the scale. The perturbations are computed automatically from the current key context so the correct spelling always sounds.

| Symbol | Notes (above tonic) | Chord tones |
|---|---|---|
| `It6` | ♭6, 8va, ♯4+8va | Ab–C–F♯ |
| `Ger6/5` | ♭6, 8va, ♭3+8va, ♯4+8va | Ab–C–E♭–F♯ |
| `Fr4/3` | ♭6, 8va, M2+8va, ♯4+8va | Ab–C–D–F♯ |

```json
{ "beat": 0, "op": "setRoman", "roman": "Ger6/5" }
```

**Bracket annotations** — `V9[b9]`, etc.:

Analytical annotations in square brackets (e.g., `[b9]`) are stripped before parsing. `V9[b9]` is treated identically to `V9`.

```json
{ "beat": 0, "op": "setRoman", "roman": "V9[b9]" }
```

---

## Tracks

Each track specifies an instrument and a list of notes:

```json
{
  "name": "Melody",
  "presetFilename": "organ_full_tutti",
  "numVoices": 4,
  "octave": 4,
  "voicing": "closed",
  "sustainFraction": 0.8,
  "notes": [ ... ]
}
```

| Field | Type | Description |
|---|---|---|
| `name` | string | Display name |
| `presetFilename` | string | Instrument preset to load |
| `numVoices` | int | Polyphony limit (voice stealing applies above this) |
| `octave` | int | Default octave (MIDI octave number; middle C = C4) |
| `voicing` | string | How multi-note chords are spread across octaves (see Voicing Styles) |
| `sustainFraction` | number | Note duration as a fraction of the beat duration (0.0–1.0) |
| `notes` | array | Ordered note events; total `durationBeats` should equal `totalBeats` |

The `octave` and `voicing` fields are defaults for notes in this track. Individual notes can override voicing if needed.

### sustainFraction

`sustainFraction` controls how long a note rings relative to its beat duration. A value of `0.95` means the note sustains for 95% of its slot — nearly legato. A value of `0.5` means staccato. The note-off fires at `durationBeats * sustainFraction` seconds into the note slot.

---

## Note Types

Each entry in a track's `notes` array describes one note event. All note types share the `durationBeats` field, which sets how many beats this event occupies.

```json
{ "type": "chordTone", "index": 2, "durationBeats": 1 }
```

### `rest`

Silence for `durationBeats`. No note is sounded.

```json
{ "type": "rest", "durationBeats": 1 }
```

### `hold`

Extends the duration of the immediately preceding non-rest, non-hold note. At compile time, consecutive holds are merged into the preceding note. No new note-on is generated; only the sustain duration increases.

```json
{ "type": "chordTone", "index": 0, "durationBeats": 2 },
{ "type": "hold",                  "durationBeats": 4 }
```

This produces a single 6-beat note (2 + 4), not two note-ons. Holds must immediately follow a sounding note (or another hold extending the same note).

### `currentChord`

Plays the entire current chord as a simultaneous voicing. The number of voices is determined by the track's `numVoices` and the `voicing` style. This is the simplest way to write block chords.

```json
{ "type": "currentChord", "durationBeats": 4 }
```

### `chordTone`

Plays a single note selected by `index` into the current chord's degree list. Index 0 is the lowest chord degree, 1 is the next, etc. If the index exceeds the chord's size, it wraps with an octave shift: index 3 in a 3-note chord plays the root one octave up.

```json
{ "type": "chordTone", "index": 1, "durationBeats": 1 }
```

### `scaleDegree`

Plays a single note selected by `degree` (0-based) from the current scale, within the track's `octave`. Degree 0 is the tonic, degree 4 is the fifth, etc.

```json
{ "type": "scaleDegree", "degree": 4, "durationBeats": 1 }
```

### `absolute`

Plays a specific MIDI pitch by name. The format is `[note letter][accidentals][octave]`:

- `"C4"` — middle C (MIDI 60)
- `"Bb3"` — B-flat in octave 3 (MIDI 58)
- `"F#5"` — F-sharp in octave 5 (MIDI 78)
- `"Eb5"` — E-flat in octave 5 (MIDI 75)

Note names are case-sensitive: the letter must be uppercase (A–G), accidentals are `b` (flat) or `#` (sharp), and the octave is an integer (0–8, where middle C = octave 4).

```json
{ "type": "absolute", "note": "D5", "durationBeats": 3 }
```

---

## Voicing Styles

The `voicing` field on a track (and optionally on individual `currentChord` notes) controls how multi-note chords are distributed across octaves:

| Style | Description |
|---|---|
| `closed` | All chord tones in the smallest possible range |
| `open` | Alternate tones raised an octave, creating an open spread |
| `dropTwo` | The second-highest voice drops an octave |
| `spread` | Voices spread across two octaves |
| `shell` | Root and seventh only (shell voicing) |
| `fifthsOnly` | Root and fifth only |

---

## Worked Examples

### Example 1: C Major Progression (`score_c_major_progression.json`)

A looping 16-beat progression (I–IV–V–I) at 90 BPM with a pad track playing full chords and a melody track picking individual chord tones.

```json
"chordEvents": [
  { "beat": 0,  "op": "setChord", "degrees": [0, 2, 4], "inversion": 0 },
  { "beat": 4,  "op": "T", "n": 3 },
  { "beat": 8,  "op": "T", "n": 1 },
  { "beat": 12, "op": "setChord", "degrees": [0, 2, 4], "inversion": 0 }
]
```

Beat 0: set I chord (C-E-G). Beat 4: T by 3 steps → IV chord (F-A-C). Beat 8: T by 1 step → V chord (G-B-D). Beat 12: reset to I chord explicitly.

The pad plays one `currentChord` per 4-beat block. The melody interleaves `chordTone` picks, a `hold`, and a `rest`:

```json
{ "type": "chordTone",   "index": 2, "durationBeats": 2 },
{ "type": "hold",                    "durationBeats": 2 },
```

These two events produce a single 4-beat note on the third chord tone.

---

### Example 2: Mozart Minuet (`score_mozart_minuet.json`)

A Bb major minuet at 72 BPM (3-beat groups, 24 total beats). The left hand plays block chords; the right hand plays absolute note names with holds and rests.

```json
"key": { "root": "Bb", "scale": "major" }
```

The right-hand melody:

```json
{ "type": "absolute", "note": "D5",  "durationBeats": 3 },
{ "type": "absolute", "note": "C5",  "durationBeats": 1 },
{ "type": "absolute", "note": "Eb5", "durationBeats": 2 },
{ "type": "absolute", "note": "Bb4", "durationBeats": 2 },
{ "type": "hold",                    "durationBeats": 4 },
{ "type": "rest",                    "durationBeats": 4 },
```

The `Bb4` followed by a `hold` of 4 beats produces a single 6-beat Bb4. The `rest` of 4 beats after it is silence. Absolute note names let you specify exact pitches when harmonic abstraction is not wanted.

---

### Example 3: Baroque Two-Voice (`score_baroque_two_voice.json`)

D minor at 80 BPM, 16 beats looping. A bass voice uses `chordTone` to walk between chord tones; a soprano voice uses `scaleDegree` to move melodically above.

```json
"key": { "root": "D", "scale": "minor" }
```

Bass (octave 2, closed voicing):
```json
{ "type": "chordTone", "index": 0, "durationBeats": 2 },
{ "type": "chordTone", "index": 2, "durationBeats": 2 },
{ "type": "chordTone", "index": 0, "durationBeats": 2 },
{ "type": "chordTone", "index": 1, "durationBeats": 2 },
```

Soprano (octave 4, scaleDegree):
```json
{ "type": "scaleDegree", "degree": 4, "durationBeats": 1 },
{ "type": "scaleDegree", "degree": 5, "durationBeats": 1 },
...
{ "type": "scaleDegree", "degree": 4, "durationBeats": 2 },
{ "type": "hold",                     "durationBeats": 2 }
```

The chord events shift at beats 4, 8, and 12 (using `T` and an explicit `setChord`). Both voices automatically play notes appropriate to whichever chord is active at their current beat position.

---

### Example 4: Bach Chorale (`score_bach_chorale_181.json`)

A Bach chorale (BWV riemenschneider 181) in E minor at 54 BPM, converted from a RomanText harmonic analysis via `romantext_to_orbital.py`. The harmonic rhythm is dense — chord changes happen every half-beat in some passages — and the piece modulates frequently to the relative major (G) and back.

```json
"key": { "root": "E", "scale": "minor" },
"chordEvents": [
  { "beat": 0,   "op": "setRoman", "roman": "i" },
  { "beat": 1,   "op": "setRoman", "roman": "V6" },
  { "beat": 2,   "op": "setKey",   "root": "G", "scale": "major" },
  { "beat": 2,   "op": "setRoman", "roman": "vi" },
  { "beat": 3,   "op": "setRoman", "roman": "V6" },
  { "beat": 3.5, "op": "setRoman", "roman": "V6/5" },
  { "beat": 4,   "op": "setRoman", "roman": "I" },
  ...
]
```

Beat 0: E minor tonic (i). Beat 1: dominant first inversion (V6). Beat 2: modulates to G major — a `setKey` is emitted because the original analysis wrote `G: vi` (vi in G major = E minor, a pivot chord). Beat 3.5: half-beat chord change typical of Bach's voice-leading density.

The output has two tracks: a `warm_analog_pad` chord track playing `currentChord` notes, and an `organ_baroque_positive` bass track playing `chordTone index 0`:

```json
"tracks": [
  {
    "name": "Chords",
    "presetFilename": "warm_analog_pad",
    "octave": 3,
    "voicing": "open",
    "notes": [
      { "type": "currentChord", "durationBeats": 1 },
      { "type": "currentChord", "durationBeats": 1 },
      ...
    ]
  },
  {
    "name": "Bass",
    "presetFilename": "organ_baroque_positive",
    "octave": 2,
    "notes": [
      { "type": "chordTone", "index": 0, "durationBeats": 1 },
      ...
    ]
  }
]
```

---

### Example 5: Yesterday (`score_yesterday.json`)

The Beatles' "Yesterday" in F major at 60 BPM. The original analysis uses applied chords (`ii/o7/vi`, `V/V`, `V7/vi`) that tonicize to secondary keys. The converter emits `setKey` events each time the tonicized key changes, then restores the home key when the analysis returns:

```json
{ "beat": 0,  "op": "setRoman", "roman": "I" },
{ "beat": 4,  "op": "setKey",   "root": "D", "scale": "minor" },
{ "beat": 4,  "op": "setRoman", "roman": "ii/o7" },
{ "beat": 6,  "op": "setRoman", "roman": "V7" },
{ "beat": 8,  "op": "setKey",   "root": "F", "scale": "major" },
{ "beat": 8,  "op": "setRoman", "roman": "vi" },
{ "beat": 28, "op": "setKey",   "root": "C", "scale": "major" },
{ "beat": 28, "op": "setRoman", "roman": "V" },
{ "beat": 32, "op": "setKey",   "root": "F", "scale": "major" },
{ "beat": 32, "op": "setRoman", "roman": "IV" }
```

Beat 4: the `ii/o7/vi` applied chord in F major tonicizes to D minor (vi of F = A, but the source is `vi` in lowercase, so D minor). The `ii/o7` (half-diminished supertonic seventh) is voiced in D minor as E–G–Bb–C. Beat 8: the analysis returns to F major. Beat 28: `V/V` (C major V chord) tonicizes briefly to C major.

---

### Example 6: Beethoven Waldstein, 1st movement (`op053-1_orbital.json`)

Beethoven's Op. 53 Sonata in C major at 80 BPM, converted from the Tymoczko corpus. The piece is 302 measures (1208 beats) and uses heavy chromatic vocabulary throughout — the development section alone contains Neapolitan sixths, German augmented sixths, flat-prefixed chords, and applied chords to flat-scale-degree targets.

All 475 chord events convert without warnings. A sample of the development:

```json
{ "beat": 672, "op": "setRoman", "roman": "bII" },
{ "beat": 676, "op": "setKey",   "root": "Eb", "scale": "major" },
{ "beat": 676, "op": "setRoman", "roman": "V" },
{ "beat": 680, "op": "setKey",   "root": "C",  "scale": "major" },
{ "beat": 680, "op": "setRoman", "roman": "bIII" },
{ "beat": 728, "op": "setRoman", "roman": "Ger6/5" }
```

Beat 672: the Neapolitan (`bII` = D♭ major) prepares a mediant motion. Beat 676: `V/bIII` is resolved by the converter to `setKey(E♭)` + `setRoman(V)` — Bb major, the dominant of E♭. Beat 680: back to C major, `bIII` = E♭ major triad (the chromatic mediant). Beat 728: German augmented sixth (Ab–C–E♭–F♯).

---

## `romantext_to_orbital.py` — Automatic Converter

The script `romantext_to_orbital.py` (in the project root) converts any RomanText `.txt` file from the Tymoczko corpus into a `scoreTracks` JSON. It handles the full harmonic vocabulary used in standard RomanText analyses:

- Diatonic numerals → `setRoman` events
- Applied chords (`V/V`, `V/bIII`, etc.) → `setKey` (tonicized key) + `setRoman`
- Pivot chords (two chords on the same beat) → keeps the new-key reading
- Explicit key changes → `setKey`
- Flat/sharp prefix chords (`bVII`, `bII`, `#IV`) → `setRoman` with perturbations computed automatically
- Neapolitan chords (`N`, `N6`) → aliased to `bII` / `bII6`
- Augmented sixth chords (`It6`, `Ger6/5`, `Ger7`, `Fr4/3`, `Fr6`) → `setRoman` with fixed-pitch perturbations
- Bracket annotations (`V9[b9]`) → stripped automatically
- Short chord events → filtered by `--min-duration` (default 0.25 beats)
- Form sections → selectable via `--section "Verse"`

```sh
python3 romantext_to_orbital.py INPUT.txt \
  --bpm 72 --bass --octave 3 \
  --section "exposition" \
  --out score_mypiece.json
```

The `--bass` flag adds a second track playing `chordTone index 0` at octave `--octave - 1`. The output JSON is ready to drop into `Orbital/Resources/patterns/`.

---

## How Compilation Works

At compile time, `ScorePatternCompiler` builds a `HarmonyTimeline` from the `chordEvents` list — an immutable sorted sequence of `(beat, operation)` pairs. For each note in each track:

1. Its absolute beat position is computed by summing prior note durations.
2. `HarmonyTimeline.state(at: beat, loop: loop)` folds all chord events up to that beat to find the current key and chord.
3. The note type is resolved against the current harmony to produce MIDI pitches.
4. Hold chains are merged: a note followed by consecutive holds produces one MIDI event with extended sustain duration.

The result is pre-computed arrays of `[MidiNote]`, sustain durations, and gap durations — identical to the output of `midiTracks`, and consumed by the same playback engine.
