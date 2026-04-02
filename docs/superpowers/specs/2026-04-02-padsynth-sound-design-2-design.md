# PADsynth Sound Design 2 — Design Spec

## Overview

A new "Sound Design 2" tab implementing the PADsynth extended algorithm with an interactive frequency-domain envelope drawing feature. The user can configure PADsynth parameters via controls, draw a multiplicative envelope on a frequency spectrum graph, and preview the resulting sound with a 10-second chord progression.

## Algorithm

Based on the PADsynth extended algorithm from ZynAddSubFX (https://zynaddsubfx.sourceforge.io/doc/PADsynth/PADsynth.htm).

### Core steps

1. Initialize `freq_amp[0..N/2-1]` to zero (N = 262144).
2. For each harmonic `nh` from 1 to `number_harmonics`:
   - Compute harmonic amplitude: `A[nh] = baseShape(nh) * pow(nh, tilt)`
   - Compute bandwidth: `bw_Hz = (pow(2, bw/1200) - 1) * f * pow(relF(nh), bwscale)`
   - Compute normalized bandwidth: `bwi = bw_Hz / (2 * samplerate)`
   - Compute harmonic frequency: `fi = f * relF(nh) / samplerate`
   - For each frequency bin `i`, add `profile((i/N) - fi, bwi) * A[nh]` to `freq_amp[i]`
3. Multiply `freq_amp` element-wise by the user's polynomial envelope (evaluated at each bin's frequency).
4. Assign random phases: `freq_phase[i] = random(0, 2*pi)`.
5. Inverse FFT to produce the wavetable.
6. Normalize.

### Parameters

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| Base shape | Picker | `1/n`, `1/sqrt(n)`, odd harmonics, equal, `1/n²` | `1/sqrt(n)` | Per-harmonic amplitude formula before tilt |
| Tilt | Slider | -2.0 to +2.0 | 0.0 | Multiplies each harmonic's amplitude by `n^tilt`. Positive = brighter, negative = darker |
| Bandwidth | Slider | 1–200 cents | 50 | Bandwidth of the fundamental harmonic in cents |
| BW scale | Slider | 0.5–2.0 | 1.0 | Exponent controlling how bandwidth grows with harmonic number. 1.0 = linear growth |
| Profile | Picker | Gaussian, Flat, Detuned, Narrow | Gaussian | Shape of each harmonic's frequency spread |
| Overtones | Picker | Harmonic, Piano, Bell, Metallic, Glass | Harmonic | Named preset that sets the Stretch slider to a starting value |
| Stretch | Slider | 0.9–1.5 | 1.0 | Exponent for `relF(nh) = nh^stretch`. 1.0 = harmonic, >1.0 = stretched/metallic, <1.0 = compressed |

### Harmonic profile functions

- **Gaussian:** `exp(-x²) / bwi` — natural ensemble sound, most common
- **Flat:** `(abs(x) < bwi) ? 1.0 / (2*bwi) : 0.0` — synthetic, even energy within band
- **Detuned:** `(exp(-(x - 0.5*bwi)²/(0.1*bwi)²) + exp(-(x + 0.5*bwi)²/(0.1*bwi)²)) / (2*bwi)` — two peaks within each harmonic, chorus-like
- **Narrow:** `exp(-x²/(0.25*bwi)²) / (0.5*bwi)` — tighter Gaussian, more tonal

All profiles are normalized so total energy is independent of bandwidth.

### Base shape formulas

- `1/n`: `A[nh] = 1.0 / Double(nh)` (sawtooth-like)
- `1/sqrt(n)`: `A[nh] = 1.0 / sqrt(Double(nh))` (warm)
- Odd harmonics: `A[nh] = (nh % 2 == 1) ? 1.0 / Double(nh) : 0.0` (hollow/square-like)
- Equal: `A[nh] = 1.0` (bright/harsh)
- `1/n²`: `A[nh] = 1.0 / Double(nh * nh)` (mellow)

### Overtone presets → Stretch values

- Harmonic: 1.0
- Piano: 1.01
- Bell: 1.15
- Metallic: 1.3
- Glass: 0.95

### Drawn envelope

The user draws on the frequency graph by dragging their finger. Touch points are collected as (frequency, amplitude) pairs where:
- Frequency is derived from the x-position via the logarithmic axis: `freq = 20 * pow(40000/20, x / width)`
- Amplitude is derived from y-position: `amp = 1.0 - (y / height)` (top = 1.0, bottom = 0.0)

On finger-up, the collected points are fit to a degree-20 polynomial via least-squares regression. The polynomial is evaluated in log-frequency space (so the polynomial operates on `log2(freq)`, not `freq` directly — this matches the visual curve the user drew on the logarithmic axis).

The polynomial coefficients are stored and the envelope is evaluated per frequency bin during wavetable generation, multiplying the `freq_amp` array. Values are clamped to [0, 1].

When no envelope has been drawn, the multiplier is 1.0 everywhere (identity).

**Fitting method:** LAPACK `dgels_` via Accelerate framework. Constructs the Vandermonde matrix from the touch points' log-frequencies, solves for 21 coefficients (degree 20).

**Polynomial degree:** Fixed at 20.

## UI Layout

### Tab placement

New tab "Sound Design 2" added as the 6th tab in `AppView.swift`, after the existing "Sound design" tab.

### View structure — vertical 60/40 split

**Top 60%: Frequency graph** (Swift Charts)

- `Chart` with three data series:
  - **Blue `AreaMark` + `LineMark`:** PADsynth `freq_amp` (algorithm output before envelope)
  - **Amber dashed `LineMark`:** Drawn polynomial envelope
  - **Green `AreaMark` + `LineMark`:** Product of freq_amp × envelope (what will be heard)
- Logarithmic x-axis (20 Hz – 40 kHz) via `ScaleType.log`
- Linear y-axis (0 to max amplitude, auto-scaled)
- Axis labels: 20, 50, 200, 1k, 5k, 20k, 40k Hz
- Legend in top-right corner
- `chartOverlay(content:)` with `DragGesture` for drawing interaction
  - `ChartProxy` converts gesture coordinates to data coordinates on the log axis
  - During drag: raw touch points shown as small dots
  - On drag end: polynomial fit runs, amber curve updates, green product updates

**Display downsampling:** The `freq_amp` array (131072 entries) is downsampled to ~1000 points for chart display using peak-hold (maximum value within each bin), so narrow harmonic spikes are preserved rather than averaged away.

**Bottom 40%: Controls** (scrollable `Form` or `VStack`)

In order from top to bottom:
1. Base shape picker
2. Tilt slider
3. Bandwidth slider (displayed in cents)
4. BW scale slider
5. Profile picker (Gaussian / Flat / Detuned / Narrow)
6. Overtones picker (Harmonic / Piano / Bell / Metallic / Glass)
7. Stretch slider
8. Buttons row: **Play 10s** (prominent) and **Clear** (secondary, removes drawn envelope)

### Reactivity

Changing any parameter triggers an asynchronous re-computation of `freq_amp` on a background task. The graph updates when computation completes. The drawn envelope (polynomial coefficients) persists across parameter changes — only the blue and green layers update.

The computation should be debounced (~200ms) so rapid slider dragging doesn't queue excessive work.

## Playback

### Chord progression

When the user taps "Play 10s":
1. Generate 4 wavetables on a background task (fundamentals: C4=261.63 Hz, E4=329.63 Hz, G4=392.00 Hz, C5=523.25 Hz)
2. Schedule playback:
   - 0–2s: C4 solo
   - 2–4s: C4 + E4
   - 4–6s: C4 + E4 + G4
   - 6–10s: C4 + E4 + G4 + C5
3. Fade out over the final 0.5s

### Audio implementation

- `PADSynthPlayer` owns a private `AVAudioEngine` with 4 `AVAudioPlayerNode`s and an `AVAudioMixerNode`.
- Each wavetable is loaded into an `AVAudioPCMBuffer` set to loop.
- Playback starts from a random position in each wavetable (per PADsynth best practices).
- Left/right channels use the same wavetable but offset by N/2 samples for stereo width.
- Player stops and tears down after 10 seconds.
- Button shows a progress indicator or countdown while playing.

### Future integration

The wavetable generation code (`PADSynthEngine`) is structured so a future `ArrowSyntax.padWavetable(...)` node can wrap it. The engine has no AVFoundation dependency — it produces raw `[Float]` buffers that any consumer can use.

## File structure

| File | Purpose |
|------|---------|
| `Orbital/Sources/Tones/PADSynthEngine.swift` | Algorithm + polynomial fitting. `@MainActor @Observable` class. No AVFoundation. |
| `Orbital/Sources/AppleAudio/PADSynthPlayer.swift` | Playback via `AVAudioEngine` + 4 `AVAudioPlayerNode`s |
| `Orbital/Sources/UI/PADSynthGraphView.swift` | Swift Charts frequency graph with drawing overlay |
| `Orbital/Sources/UI/PADSynthFormView.swift` | "Sound Design 2" tab — graph + controls layout |
| `OrbitalTests/PADSynthEngineTests.swift` | Unit tests for engine: peak positions, bandwidth growth, envelope multiplication, polynomial fitting, wavetable length |

## Testing

All tests target `PADSynthEngine` (no audio, no UI):

- **Peak positions:** For a given fundamental and harmonic count, verify `freq_amp` has peaks at the expected frequency bins.
- **Bandwidth growth:** Verify that higher harmonics produce wider peaks in `freq_amp` (measure width at half-max).
- **Profile shapes:** Verify Gaussian vs. Flat vs. Detuned produce qualitatively different peak shapes.
- **Envelope multiplication:** Verify that applying a known polynomial envelope produces the expected element-wise product.
- **Polynomial fitting:** Generate points on a known polynomial, fit them, verify coefficients match within tolerance.
- **Inharmonicity:** Verify that stretch != 1.0 shifts peak positions away from integer multiples.
- **Base shape + tilt:** Verify harmonic amplitudes match expected formulas.
- **Wavetable output:** Verify correct length (N), normalized to [-1, 1].

## Constraints

- No third-party frameworks. Accelerate (vDSP for FFT, LAPACK for polynomial fitting) only.
- All computation off the main thread except state updates.
- No real-time audio thread concerns — wavetables are generated offline, played back via AVAudioPlayerNode.
- Target iOS 26.1+.
