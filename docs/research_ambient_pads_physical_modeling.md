# Research: Ambient Pads via Comb Filter / Waveguide Synthesis

## The Exciter → Resonator Model

All comb-filter-based synthesis follows one pattern: an **exciter** feeds a
**resonator**. The exciter determines the attack character and spectral content.
The resonator determines pitch, sustain, and timbral decay.

```
exciter → comb filter (resonator) → output
              ↑ feedback loop ↓
              └── damping filter ←┘
```

The exciter can be:
- **Impulsive** (noise burst, click) → plucked string, struck object
- **Continuous** (filtered noise, bow friction model) → bowed string, blown pipe, sustained pad

For ambient pads, the exciter must be **continuous**. A sustained noise signal
keeps pumping energy into the comb filter so the tone doesn't decay.

### Reference implementations

**Mutable Instruments Elements** (Émilie Gillet): BOW exciter = combination of a
specific excitation signal and a feedback path in the resonator. BLOW exciter =
continuous noise. The resonator is a bank of 60 tuned bandpass filters (modal
synthesis). For polyphony, Rings splits this into 2×30 or 4×15.

**Mutable Instruments Rings**: Also offers a **comb filter string model** — a
comb filter with a multimode filter and nonlinearities in the feedback loop.
The Structure parameter adjusts inharmonicity of the spectrum (perceived
"material" — wood, metal, glass).

**Nonlinear Labs C15**: Uses an oscillator signal (exciter) to stimulate a comb
filter (resonator). Short, percussive exciter = plucked string. Sustained
exciter = bowed string or overblown woodwind. An allpass filter in the loop
shifts overtones to produce metallic timbres.

## Technique 1: Sustained Comb Filter (Bowed String)

The simplest path from our `airports_piano_comb` to an ambient pad.

```
continuous noise → [envelope: slow attack, full sustain] → comb filter
                                                              ↑
                                                         feedback ~0.995
                                                         + low-pass in loop
```

Changes from the current piano preset:
- Noise envelope: `attack: 2.0s, sustain: 1.0, release: 4.0s` (was short decay)
- Feedback: raise toward 0.995 (was 0.98). With continuous excitation you can go
  higher because the noise masks any buildup artifacts.
- Add a **low-pass filter inside the feedback loop** for frequency-dependent
  damping. High partials die faster, low partials sustain. This is the standard
  "string damping" trick. Without it, the harmonic series is unnaturally even.
- Slowly modulate the noise amplitude (LFO at 0.1–0.3 Hz) for a "bowing"
  quality — the sound breathes.
- Slowly modulate the feedback loop's low-pass cutoff for timbral drift.

This reuses our existing `CombFilter` class with zero new DSP code. The only
change is in the preset JSON (envelope shape and parameter values).

**Limitation**: A single comb filter produces a perfectly harmonic series
(f, 2f, 3f, ...). Real-world objects are inharmonic. For richer pad textures,
see Techniques 2 and 3.

## Technique 2: Allpass Filter in the Feedback Loop (Inharmonic String)

Adding an allpass filter inside the comb filter's feedback path shifts the phase
of different frequencies by different amounts, which effectively detunes the
upper partials. The result sounds metallic or bell-like rather than stringy.

```
exciter → delay buffer → output
              ↑
         feedback × gain
              ↑
         allpass filter (detunes partials)
              ↑
         low-pass filter (damps highs)
              ↑
         ←── delay buffer output
```

This is what Rings calls "string with dispersion" and what the C15 calls
"AP Tune." The allpass coefficient controls how much inharmonicity — at 0 you
get a pure string, at higher values you get piano-like stiffness, and at extreme
values you get bell/metallic timbres.

**Implementation**: Modify `CombFilter` to optionally include a first-order
allpass in the feedback path. One new parameter (`dispersion: CoreFloat`).

## Technique 3: Parallel Comb Bank (Modal Resonator)

Multiple comb filters in parallel, each tuned to a different partial frequency.
This directly models modal synthesis — each comb represents one resonant mode
of a vibrating object.

```
             ┌─ comb @ f1 (feedback1) ─┐
noise/bow →──┼─ comb @ f2 (feedback2) ─┼──→ sum → output
             ├─ comb @ f3 (feedback3) ─┤
             └─ comb @ f4 (feedback4) ─┘
```

Frequency ratios determine the perceived material:
- **Harmonic** (1:2:3:4) → string, voice
- **Nearly harmonic** (1:2.01:3.03:4.02) → slightly detuned string = chorus
- **Inharmonic** (1:2.76:5.40:8.93) → bell, bowl, chime
- **Dense cluster** (1:1.02:1.05:1.08) → metallic plate, gong

Each comb can have its own feedback (higher partials get lower feedback = faster
decay). 4–8 combs is enough for rich pad textures. Elements uses 60 bandpass
filters, but that's for full-spectrum modal fidelity — pads don't need that.

**Implementation options**:
- Express in preset JSON as a `sum` of `combFilter` nodes fed by the same noise
  source (works today, no new code).
- New `CombBank` Arrow11 subclass that owns N comb filters internally. More
  efficient because it avoids redundant buffer copies between Arrow nodes.

## Technique 4: Feedback Delay Network (Reverberant Pad)

A feedback delay network (FDN) is N delay lines cross-coupled through a mixing
matrix. When the matrix is diagonal, it collapses to parallel comb filters
(Technique 3). With off-diagonal terms, energy circulates between the delay
lines, producing dense, reverberant textures.

```
             ┌─ delay1 ─┐
input →──────┤           ├──→ sum → output
             └─ delay2 ─┘
                  ↑ ↓
              mixing matrix
              (cross-feedback)
```

This is overkill for basic pads but interesting for evolving, reverb-like drone
textures where the sound has no clear "pitch" but a complex, shifting harmonic
field. Starts to resemble what Rings does in "sympathetic strings" mode.

## Trilling Bug in airports_piano_comb

When rapidly trilling two keys, the comb filter produces a runaway sound that
sustains indefinitely. Root cause analysis:

### The problem

`CombFilter.reset()` is **never called when a voice is reallocated**. The only
buffer-clearing mechanism is the time-gap detection in `CombFilter.process()`:

```swift
if lastTime > 0 && (currentTime - lastTime) > 0.05 {
  // clear delay buffer
}
```

This fails during trills because:

1. Time values come from `AVAudioSourceNode`'s wall-clock ramp, not per-voice
   time. The audio engine produces continuous, monotonically increasing time
   regardless of voice lifecycle.
2. When VoiceLedger steals a releasing voice (Tier 2/3 allocation), the stolen
   voice's `CombFilter` delay buffer still contains resonance from the previous
   note.
3. Rapid trilling means the gap between noteOff and the next noteOn on the same
   voice index is well under 50ms — the detection threshold is never hit.
4. The new note's excitation adds energy on top of the previous note's residual
   energy. With feedback at 0.98, this accumulates across multiple steals.
5. The amplitude envelope gates the output, but the comb filter's internal
   buffer state persists through the gate closure because AudioGate only zeroes
   the output — it doesn't break the time continuity flowing into the inner
   Arrow graph.

### Fix

Call `CombFilter.reset()` (which already exists and clears the delay buffer)
whenever a voice is retriggered. The natural place is in `Preset.triggerVoice()`,
which already handles `env.noteOn()` for the amplitude envelopes.

Specifically: when `triggerVoice` is called, iterate the voice's
`namedCombFilters` and call `reset()` on each. This ensures stale resonance
from a previous note is cleared before the new note's excitation begins.

An alternative or complementary fix: have `AudioGate` call a reset method on
its inner Arrow graph when transitioning from closed → open, rather than relying
on time-gap detection.

## Implementation Priority

1. **Fix the trilling bug** — call `CombFilter.reset()` in `triggerVoice()`.
2. **Technique 1** — sustained comb pad preset (JSON-only, no new code).
3. **Technique 2** — allpass in feedback loop (small `CombFilter` modification).
4. **Technique 3** — parallel comb bank (JSON composition or new Arrow subclass).

## Sources

- [Mutable Instruments Rings documentation](https://pichenettes.github.io/mutable-instruments-documentation/modules/rings/)
- [Mutable Instruments Elements manual](https://pichenettes.github.io/mutable-instruments-documentation/modules/elements/manual/)
- [Mutable Instruments Elements resonator source](https://github.com/pichenettes/eurorack/blob/master/elements/dsp/resonator.cc)
- [Nonlinear Labs C15 — Comb Filter tutorial](https://www.nonlinear-labs.de/support/help/docs/HTML-Manual/documents/tut-sound-generation/06-comb-filter.html)
- [Digital Waveguide Models — Julius O. Smith III](https://www.dsprelated.com/freebooks/pasp/Digital_Waveguide_Models.html)
- [Karplus-Strong — Wikipedia](https://en.wikipedia.org/wiki/Karplus%E2%80%93Strong_string_synthesis)
- [Integraudio — Comb Filter & Resonator guide](https://integraudio.com/full-guide-comb-filter-resonator/)
- [Baby Audio — Ambient Pads blog post](https://babyaud.io/blog/ambient-pads)
