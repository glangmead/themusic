# RomanText Format Specification

Based on Dmitri Tymoczko's RomanText format as described in the accompanying PDF and the corpus in `/Music/`. This format encodes harmonic Roman-numeral analyses of tonal music as plain text files.

---

## File Structure

A RomanText file has two sections separated by a blank line:

1. **Header block** — key/value metadata fields, one per line
2. **Body** — measure lines, directives, and annotations, one or more per line

```
Composer: Mozart
Piece: K545
Analyst: Nathan Martin
Time Signature: 4/4

m1 C: I
m2 V4/3 b3 I
...
```

---

## Header Fields

All header fields use the format `Key: Value`. Fields may have empty values. Unknown fields should be preserved and ignored by parsers.

| Field | Description |
|---|---|
| `Composer` | Composer name (free text) |
| `Piece` | Piece identifier (catalogue number, opus, etc.) |
| `Title` | Work title |
| `BWV` | Bach-Werke-Verzeichnis number (Bach-specific) |
| `Artist` | Performer/band (used for popular music) |
| `Date` | Year or date of composition/recording |
| `Analyst` | Person who created the analysis |
| `Proofreader` | Person who verified the analysis |
| `Note` | Free-text comment (may appear multiple times) |
| `Tempo` | Tempo marking (free text, e.g. `Allegro`, `Adagio`) |
| `Time Signature` | Initial meter in `N/D` format, e.g. `4/4`, `3/4`, `3/1` |
| `Global Tonic` | Pitch class of the tonic used for modal/pre-tonal music (e.g. `E`, `G`) |

- `Note:` lines may appear anywhere in both the header and body and are ignored for harmonic parsing.
- `Time Signature:` may also appear in the body to indicate a meter change (see below).

---

## Body Lines

The body consists of five kinds of lines:

1. **Measure lines** — specify chords at specific beats
2. **Form markers** — section labels
3. **Pedal markers** — sustained bass notes
4. **Repeat directives** — shorthand for repeated passages
5. **Note/comment lines** — free-text annotations

---

## Measure Lines

### Basic Format

```
mN [KEY:] CHORD [bBEAT CHORD [bBEAT CHORD ...]]
```

- `mN` — measure number (integer), e.g. `m1`, `m12`, `m100`
- `KEY:` — optional key context (see Keys below); if absent, the current key from context applies
- `CHORD` — Roman numeral chord symbol (see Chord Symbols below)
- `bBEAT` — beat marker specifying when the next chord starts (see Beat Markers below)

Multiple chords in a measure are separated by beat markers. The first chord in a measure begins on beat 1 (unless a beat marker appears before it).

**Examples:**
```
m1 C: I
m2 V4/3 b3 I
m8 I b2 iio6 b3 i6/4 b4 V7
m10 b4.5 V6/5/V
```

The last example (`b4.5` before any chord) means beat 1 through beat 4.5 is a continuation from the previous measure, and only at beat 4.5 does a new chord appear.

### Measure Ranges

```
mN-M KEY: CHORD ...
```

A range `mN-M` means the chord(s) apply uniformly across measures N through M. Beat markers within a range apply to each measure in the range identically.

**Example:**
```
m3-4 = m1-2
m1-4 C: I
```

### Anacrusis (Pickup Measure)

Measure `m0` denotes an anacrusis (upbeat / pickup) that precedes measure 1. Beat markers within `m0` indicate which beat the piece begins on.

**Example:**
```
m0 b4 e: i
```
This means: one chord, starting on beat 4 of the pickup measure.

### Variant Measures

```
mNvarM KEY: CHORD ...
```

Some measures have documented variants (e.g., due to repeats with different endings or editorial alternatives). `mNvarM` gives an alternate reading for measure N. Parsers may optionally include or ignore variants.

**Example:**
```
m12 I b3 I6
m12var1 I b3 I6 b3.75 viio6
```

### Bar Line / Phrase Markers

`||` within a measure line marks a phrase boundary (double bar or section ending). It is an annotation only and does not affect the harmonic parsing; chords continue past it.

**Example:**
```
m2 ii6/5 b2 V b2.5 V7 b3 I || b4 I
```

---

## Beat Markers

```
bN
```

`N` is a real number (integer or decimal) specifying the beat within the measure. Beat 1 is the downbeat. Fractional beats are written as decimals.

Common fractional beat values:

| Notation | Meaning |
|---|---|
| `b1.5` | halfway through beat 1 (the "&" in 4/4) |
| `b2.5` | halfway through beat 2 |
| `b3.75` | three-quarters through beat 3 |
| `b4.5` | halfway through beat 4 |
| `b1.25` | one-quarter through beat 1 |
| `b1.66` | two-thirds through beat 1 (triplet) |

The granularity of beats depends on the time signature. In `3/1` (breve meter), beats are whole notes, so `b1.5` = one half note into the measure.

---

## Keys

### Key Notation

A key is written as a pitch class letter followed by a colon:

- **Uppercase** = major key: `C:`, `F:`, `G:`, `Bb:`, `Eb:`
- **Lowercase** = minor key: `a:`, `e:`, `g:`, `d:`, `bb:`

Accidentals:
- `#` = sharp: `F#:`, `c#:`
- `b` = flat: `Bb:`, `eb:`

### Key Scope

- A key specified at the start of a measure line (`m1 C: I`) takes effect from beat 1 of that measure.
- A key specified after a beat marker (`b3 G: V`) takes effect at that beat.
- Once set, a key persists until the next key declaration.
- A `Global Tonic` header provides a single reference pitch for modal music without a strong major/minor distinction.

**Key modulation examples:**
```
m13 G: V b3 V2          ← key changes to G at m13 b1
m31 i d: iv             ← key changes to d at the chord "iv"
m41 N6 F: IV6 b3 V7     ← key changes to F at the chord "IV6"
```

---

## Chord Symbols

### Roman Numerals

The scale degree of the chord root is given as a Roman numeral. Case encodes quality:

| Symbol | Quality |
|---|---|
| `I`, `II`, `III`, `IV`, `V`, `VI`, `VII` | Major |
| `i`, `ii`, `iii`, `iv`, `v`, `vi`, `vii` | Minor |
| `viio` | Diminished (the `o` suffix = diminished) |
| `ii/o` or `iiø` | Half-diminished (the `/o` prefix = half-dim) |

### Figured Bass / Inversions

Inversions follow the numeral as a figured-bass string:

| Suffix | Inversion | Common name |
|---|---|---|
| (none) | Root position | |
| `6` | First inversion | |
| `6/4` | Second inversion | |
| `6/5` | First inversion seventh | |
| `4/3` | Second inversion seventh | |
| `2` or `4/2` | Third inversion seventh | |
| `7` | Root-position seventh | |
| `9` | Ninth chord | |

**Examples:** `I6`, `V7`, `ii6/5`, `V4/3`, `viio6`, `V2`

Figured bass may be combined: `I6/4` = second inversion tonic.

### Applied (Secondary) Chords

The `/X` suffix means "applied to scale degree X":

```
V/V      ← dominant of the dominant
viio7/V  ← leading-tone seventh of the dominant
V6/5/IV  ← first-inversion dominant seventh of IV
```

The target `X` is itself a Roman numeral in the current key. Applied chords use the same inversion notation before the slash:

```
viio4/3/vi   ← second-inversion diminished seventh applied to vi
```

Half-diminished applied chords use `/o`:
```
ii/o7/vi    ← half-diminished seventh applied to vi
ii/o4/3     ← half-diminished second inversion
```

### Chromatic Alterations

- **Flat prefix** (`b`): lowers the chord root by a semitone relative to the scale degree
  `bII`, `bvii`, `bVI`, `bIII`
- **Sharp prefix** (`#`): raises the chord root (rare)

The `b` prefix on a Roman numeral is distinct from the `b` in beat markers (context makes these unambiguous since beat markers follow spaces and appear mid-line).

### Special Chord Types

| Symbol | Name | Notes |
|---|---|---|
| `N` or `N6` | Neapolitan | Typically in first inversion `N6`; `N` = root position |
| `It6` | Italian augmented sixth | |
| `Ger6/5` | German augmented sixth | |
| `Fr4/3` | French augmented sixth | |
| `Ger7` | German seventh (enharmonic) | |
| `vo` | Diminished triad on scale degree 5 | |
| `vo6` | First inversion diminished triad | |

### Quality Overrides (Case Conflicts)

In minor keys, some scale degrees can be ambiguous. The notation follows the actual chord quality, not the diatonic default. For example, `V` in a minor key means a raised (major) dominant, `v` means a minor dominant chord.

---

## Form Markers

```
Form: LABEL
```

A `Form:` line marks the beginning of a structural section. The label is free text. Common labels include:

- `exposition`, `development`, `recapitulation`
- `second theme`, `closing theme`, `transition`
- `introduction`, `coda`
- `verse`, `chorus`, `bridge`
- `Kyrie`, `Gloria`, etc. (for sacred music)

Form markers are annotations; they do not affect harmonic parsing but are useful for segmenting analyses.

---

## Repeat Directives

```
mN = mP
mN-M = mP-Q
```

This states that measure(s) N (or range N–M) have identical harmonic content to measure(s) P (or range P–Q). Parsers may expand these by copying the referenced measures' chord content.

The ranges must be the same length (`M - N = Q - P`).

**Examples:**
```
m3-4 = m1-2
m16-17 = m14-15
m54-57 = m9-12
```

Repeat directives may appear even when the referenced measures are in a different key; the copy is literal (chord symbols only; the key context at the destination applies).

---

## Pedal Markers

```
Pedal: PITCH mSTART [bBEAT] mEND [bBEAT]
```

Indicates a sustained or repeated pedal tone (usually in the bass) over a range of measures.

- `PITCH` — the pitch class letter of the pedal note (e.g. `F`, `A`, `C`, `G`)
- `mSTART` — first measure of the pedal
- `bBEAT` — optional beat within mSTART where pedal begins (default: beat 1)
- `mEND` — last measure of the pedal
- `bBEAT` — optional beat within mEND where pedal ends (default: end of measure)

**Examples:**
```
Pedal: F m1 b1 m5 b1
Pedal: A m9 m11
Pedal: C m50 m52
Pedal: G m16 m20 b1
```

Pedal markers are annotations. They do not override the chord symbols in those measures but indicate that the analysis is made over a sustained note.

---

## Mid-Body Directives

### Time Signature Changes

```
Time Signature: N/D
```

When appearing in the body (after the blank line), this marks a meter change starting at the next measure. Beat numbering and fractional beat values should be reinterpreted in the new meter.

**Example (from Palestrina):**
```
Time Signature: 3/1
m1 E: i b2 e: i b3 bII
...
Time Signature: 2/1
m17 IV
...
Time Signature: 3/1
m53 iv
```

### Note Lines in Body

```
Note: free text
```

Annotation lines may appear anywhere in the body. They carry no harmonic information.

---

## Complete Grammar (Informal BNF)

```
file         ::= header_block BLANK_LINE body

header_block ::= header_line*
header_line  ::= KEY ": " VALUE "\n"

body         ::= body_line*
body_line    ::= measure_line
               | form_line
               | pedal_line
               | repeat_line
               | timesig_line
               | note_line
               | blank_line

measure_line ::= measure_ref " " chord_sequence "\n"
measure_ref  ::= "m" INT ("-" INT)? ("var" INT)?
chord_sequence ::= (key_prefix? chord_symbol) (beat_marker key_prefix? chord_symbol)* bar_marker?

key_prefix   ::= PITCH_CLASS ":"
chord_symbol ::= chromatic? numeral quality? figured? applied? bar_marker?
chromatic    ::= "b" | "#"
numeral      ::= [IiVv]+ (using Roman numeral characters)
quality      ::= "o" | "/o"
figured      ::= ("6" ("/" "5")?)? | ("4" "/" ("3" | "2"))? | "7" | "9" | "2"
applied      ::= "/" chord_symbol

beat_marker  ::= "b" REAL_NUMBER
bar_marker   ::= "||"

form_line    ::= "Form: " TEXT "\n"
pedal_line   ::= "Pedal: " PITCH_CLASS " m" INT (" b" REAL)? " m" INT (" b" REAL)? "\n"
repeat_line  ::= "m" INT ("-" INT)? " = " "m" INT ("-" INT)? "\n"
timesig_line ::= "Time Signature: " INT "/" INT "\n"
note_line    ::= "Note: " TEXT "\n"
```

---

## Parsing Considerations

### Key State Machine

A parser must maintain a running key that updates:
- At the start of each new `KEY:` prefix anywhere in a measure line
- Across measure boundaries (key persists)
- On `Global Tonic:` (sets a reference pitch for modal interpretation)

### Beat Resolution

To convert a beat number to a time offset:
1. Determine the current time signature `N/D`
2. One beat = one `D`-th note (e.g., in `4/4`, one beat = one quarter note)
3. Fractional beats: `b2.5` = 1.5 beats from beat 2 = 2.5 quarter notes from downbeat in `4/4`

### Repeat Expansion

When expanding `mN-M = mP-Q`, copy the chord events from measures P–Q into measures N–M verbatim. Key context at the target location applies (do not carry over key from the source).

### Chord Ambiguities

- `b` at start of a chord symbol is always a flat prefix on the Roman numeral (e.g., `bII`, `bvii`)
- `b` followed by a digit is always a beat marker (e.g., `b3`, `b2.5`)
- `V/V` = applied dominant; `V4/3` = inversion; `viio4/3/vi` = inverted applied (parse `figured` before `applied`)
- Half-diminished: `/o` prefix on the numeral, e.g. `ii/o7` = half-dim seventh on II; this is distinct from the `/` in applied chords (context: `/o` directly follows the numeral letters)

### Mode / Quality of Numeral

In a major key (`C:`):
- Uppercase = chord built on that scale degree with major quality
- Lowercase = minor quality chord (chromatic alteration implied)

In a minor key (`c:`):
- Lowercase numerals are diatonic
- Uppercase numerals may indicate raised degrees (e.g., `III` = major mediant, `VI` = major submediant)
- `V` in minor = major dominant (raised 7th)

### Special Symbols Quick Reference

| Symbol | Description |
|---|---|
| `N6` | Neapolitan sixth |
| `It6` | Italian augmented sixth |
| `Ger6/5` | German augmented sixth |
| `Fr4/3` | French augmented sixth |
| `bII` | Neapolitan (root position) or flat-II in general |
| `viio` | Fully diminished leading-tone triad |
| `ii/o` | Half-diminished supertonic |
| `vo` | Diminished chord on scale degree 5 |
| `V/V` | Secondary dominant of V |
| `||` | Double bar / phrase end (annotation only) |
