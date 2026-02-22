# Subtractive Synthesis Preset Analysis

## 1. Current Engine Capabilities Inventory

### Primitives available in ArrowSyntax (JSON)

| JSON key            | Arrow class                  | Description |
|---------------------|------------------------------|-------------|
| `osc`               | `BasicOscillator`            | sine, triangle, sawtooth, square, noise; has `width` (pulse-width) parameter |
| `envelope`          | `ADSR`                       | Linear ADSR with `attack`, `decay`, `sustain`, `release`, `scale` |
| `lowPassFilter`     | `LowPassFilter2`             | Biquad 2nd-order LPF with arrow-rate `cutoff` and `resonance` |
| `const`             | `ArrowConst`                 | Named constant value (mutable at runtime via handles) |
| `constOctave`       | `ArrowConstOctave`           | Outputs `2^val` -- octave transposition multiplier |
| `constCent`         | `ArrowConstCent`             | Outputs `cent^val` -- fine detuning multiplier |
| `identity`          | `ArrowIdentity`              | Pass-through (time ramp) |
| `compose`           | composition chain            | Sequential arrow composition (inner-to-outer) |
| `sum`               | `ArrowSum`                   | Additive mixing of parallel arrows |
| `prod`              | `ArrowProd`                  | Multiplicative combination (ring mod, AM, envelope shaping) |
| `crossfade`         | `ArrowCrossfade`             | Linear crossfade between N arrows via `mixPoint` |
| `crossfadeEqPow`    | `ArrowEqualPowerCrossfade`   | Equal-power crossfade (sqrt weighting) |
| `choruser`          | `Choruser`                   | Frequency-spread chorus via cent detuning |
| `noiseSmoothStep`   | `NoiseSmoothStep`            | Smoothly interpolated random (good for slow modulation) |
| `rand`              | `ArrowRandom`                | Uniform random per sample |
| `exponentialRand`   | `ArrowExponentialRandom`     | Exponentially distributed random |
| `line`              | `ArrowLine`                  | Linear ramp from `min` to `max` over `duration` |
| `control`           | `ControlArrow11`             | Decimated control-rate wrapper (every 10th sample) |

### Effects chain (AVAudioUnit-based, post-arrow)

- `AVAudioUnitReverb` (factory presets, wet/dry)
- `AVAudioUnitDelay` (time, feedback, low-pass cutoff, wet/dry)
- `AVAudioUnitDistortion` (factory presets, pre-gain, wet/dry)
- `AVAudioMixerNode` (spatial positioning via Rose LFO)

### Existing preset architecture

All existing presets follow a common template:
```
compose([
  prod([
    sum([                         <-- 3 oscillator mixer
      prod([osc1Mix, compose([freq_chain, osc1, choruser1])]),
      prod([osc2Mix, compose([freq_chain, osc2, choruser2])]),
      prod([osc3Mix, compose([freq_chain, osc3, choruser3])])
    ]),
    envelope(ampEnv)              <-- amplitude envelope
  ]),
  lowPassFilter(cutoff, resonance) <-- filter stage
])
```

Each oscillator's frequency chain is:
```
sum([
  prod([freq, constOctave, constCent, identity]),  <-- pitched frequency
  prod([vibratoAmp, compose([vibratoFreq * t, vibratoOsc])])  <-- vibrato
])
```

---

## 2. Classic Subtractive Synthesis Preset Recipes

The following recipes are drawn from well-documented techniques in subtractive synthesis literature (Sound On Sound "Synth Secrets" series by Gordon Reid, the Welsh Synthesizer Cookbook, and Minimoog/Prophet-5/Jupiter-8 programming guides).

### 2a. Lush Pad (string ensemble / ambient pad)

**Target sound**: Slow-evolving, warm, wide stereo pad. Think Juno-106 string pad or Oberheim OB-X pad.

**Recipe**:
- **Oscillators**: Two sawtooth oscillators, detuned against each other by ~7-15 cents. Optional third oscillator (sine or triangle) one octave lower for sub-bass warmth.
- **Filter**: Low-pass, cutoff around 2-4x fundamental frequency. Low resonance (0.5-0.7, Butterworth-flat). Filter envelope with slow attack (1-3s), no decay movement, full sustain.
- **Amp envelope**: Slow attack (0.5-2s), no decay, full sustain, slow release (1.5-3s).
- **Modulation**: Slow vibrato (4-6 Hz, subtle depth ~1-3 Hz of frequency deviation). Chorus with 3-5 voices spread 10-20 cents for width.
- **Effects**: Heavy reverb (cathedral or large hall, 60-80% wet). Optional slow delay.

**What the current engine can do**: Everything. The three-oscillator architecture with per-oscillator detuning, choruser, filter envelope, and amp envelope can express this completely.

### 2b. Analog Brass (Minimoog/Prophet brass stab)

**Target sound**: Punchy, bright attack that settles into a warm sustain. Classic brass patch from Minimoog or Sequential Prophet-5.

**Recipe**:
- **Oscillators**: Two oscillators -- sawtooth primary + square (pulse width ~0.4-0.5) secondary. Square one octave below or at unison with slight detuning (~5 cents). Mix roughly 70/30 saw/square.
- **Filter**: Low-pass with aggressive filter envelope. Cutoff base ~1-2x fundamental. Filter envelope: fast attack (5-30ms), medium decay (200-500ms), sustain at ~0.3-0.5 of peak, fast release (50-150ms). Moderate resonance (1.0-2.0) for harmonic emphasis.
- **Amp envelope**: Near-instant attack (5-20ms), short decay (100-300ms) to sustain ~0.7-0.8, medium release (100-300ms).
- **Modulation**: No vibrato initially; delayed vibrato (attack 2-5s on vibrato envelope) at 5-6 Hz is characteristic of real brass players "leaning in" to a note.
- **Effects**: Light reverb (small room or plate, 20-40% wet). No delay.

**What the current engine can do**: Mostly everything. The delayed vibrato is already demonstrated in auroraBorealis.json using a vibrato envelope with a long attack time. Filter envelope with fast attack and medium decay works with the existing `filterEnv` pattern in 5th_cluedo.json.

### 2c. Classic Synth Lead (Minimoog solo lead)

**Target sound**: Fat, cutting monophonic lead. Think Keith Emerson, Jan Hammer, or Trent Reznor lead lines.

**Recipe**:
- **Oscillators**: Two or three sawtooth oscillators at slight detuning (3-7 cents between each). One oscillator optionally one octave up for brightness. Sub-oscillator (square, one octave below) for body.
- **Filter**: Low-pass, cutoff around 3-6x fundamental. Moderate resonance (1.5-3.0) -- enough to add edge but not self-oscillate. Filter envelope: instant attack, fast decay (100-200ms), moderate sustain (0.4-0.6), matching release.
- **Amp envelope**: Instant attack (<5ms), no decay, full sustain, short release (50-100ms) for articulation.
- **Modulation**: Vibrato at 5-7 Hz, moderate depth, delayed onset (1-3s). Pitch bend support is desirable but out of scope.
- **Effects**: Light reverb, optional slapback delay (100-200ms, 20-30% feedback).

**What the current engine can do**: Fully expressible. The main difference from pads is faster envelopes and more aggressive filter settings.

### 2d. Warm String Ensemble (Solina / ARP Solina)

**Target sound**: Warm, diffuse, chorused string sound. The Solina string ensemble sound that underpins 70s/80s pop and new wave.

**Recipe**:
- **Oscillators**: Sawtooth primary, optionally mixed with a quieter square. The characteristic Solina sound comes from *heavy* chorus -- 5-8 voices with 15-30 cent spread.
- **Filter**: Low-pass, cutoff ~3-5x fundamental. Very low resonance (0.5-0.7). No filter envelope movement (static filter) OR very slow filter envelope matching amp attack.
- **Amp envelope**: Medium attack (50-200ms for realistic bow attack), full sustain, medium-long release (500ms-1.5s).
- **Modulation**: Light vibrato (4-5 Hz, very subtle). The chorus does most of the animation work.
- **Effects**: Medium-heavy reverb (large hall, 50-70% wet). This is essential to the Solina sound.

**What the current engine can do**: Fully expressible. The choruser with high voice counts (5+) and wide cent radius is exactly what this needs.

### 2e. Sub Bass (808-style or Moog bass)

**Target sound**: Deep, powerful bass that provides foundation. Two variants: clean sine sub (808) or slightly dirty filtered saw (Moog).

**Recipe (Moog variant)**:
- **Oscillators**: Square wave at fundamental (pulse width 0.5 for maximum fundamental). Optional sawtooth one octave up at low mix (0.2-0.3) for harmonic content.
- **Filter**: Low-pass, cutoff ~2x fundamental. Low resonance (0.7-1.0). Filter envelope: instant attack, medium decay (200-400ms), low sustain (0.2-0.4), fast release. This "pluck" shape gives the bass its attack definition.
- **Amp envelope**: Instant attack, long decay (500ms-1s), moderate sustain (0.5-0.7), medium release (200-400ms).
- **Modulation**: None or very subtle. Bass patches should be stable.
- **Effects**: Minimal reverb (0-20% wet). No delay. Light distortion can add warmth.

**What the current engine can do**: Fully expressible. The distortion node could enhance this further.

---

## 3. Gap Analysis: Missing Features for Richer Presets

Based on the recipes above and standard subtractive synthesis practice, here are features that are commonly expected but absent or limited in the current engine, ordered from most to least impactful.

### 3a. High-pass and band-pass filters (HIGH IMPACT)

**Current state**: Only `LowPassFilter2` exists (biquad 2nd-order low-pass).

**What's missing**: High-pass filter (HPF) and band-pass filter (BPF). These share the same biquad structure -- only the coefficient calculation differs.

**Why it matters**: HPF is essential for cleaning up low-end rumble from pads and leads, preventing muddiness in mixes. BPF creates vocal/vowel-like resonant peaks and is the basis for "wah" effects. Many classic patches use a combination of LPF + HPF to create a band-pass effect with independent control over both cutoffs.

**Implementation effort**: Low. The existing `LowPassFilter2` already implements the biquad from the Audio EQ Cookbook (w3.org/TR/audio-eq-cookbook). HPF and BPF are alternate coefficient formulas on the same structure. The `ArrowSyntax` enum would need `highPassFilter` and `bandPassFilter` cases mirroring the existing `lowPassFilter` case.

### 3b. Filter key-tracking (MEDIUM IMPACT)

**Current state**: Filter cutoff is either a static constant or driven by an envelope multiplied by a constant. The note frequency is not involved in the cutoff calculation.

**What's missing**: "Key tracking" or "keyboard follow" -- making the filter cutoff proportional to the played note's frequency. Without this, low notes sound muffled (cutoff is too far above harmonics) and high notes sound harsh (cutoff is too low relative to harmonics).

**Why it matters**: Nearly every hardware synth has a key-tracking knob on the filter. The standard setting for most patches is 50-100% tracking (cutoff rises with pitch). For this engine, since `freq` is a named const that gets set per-voice on noteOn, the filter cutoff expression could already reference it. Looking at the existing presets, `auroraBorealis.json` already does this: `{"prod": {"of": [{"const": {"name": "freq", "val": 300}}, {"const": {"name": "cutoffMultiplier", "val": 4}}]}}` computes cutoff as `freq * 4`. So partial key-tracking already exists -- the cutoff moves with `freq` because `freq` is updated on noteOn. But the `5th_cluedo.json` and other presets use a static cutoff. This is a **preset design issue**, not a missing engine feature. Presets that want key-tracking just need to reference `freq` in the cutoff expression, as `auroraBorealis` already demonstrates.

**Action**: Document this pattern. No engine changes needed.

### 3c. Velocity sensitivity (MEDIUM IMPACT)

**Current state**: `MidiNote` carries `velocity` but it is never used to modulate any parameter. `noteOn` sets `freq` from the note but ignores velocity entirely.

**What's missing**: Velocity-to-amplitude scaling (louder notes when played harder) and velocity-to-filter-cutoff (brighter notes when played harder). These are the two most common velocity destinations.

**Why it matters**: Velocity sensitivity is fundamental to expressive playing. Without it, every note hits at the same dynamic level regardless of MIDI velocity. For MIDI file playback especially, velocity data carries essential phrasing information that is currently lost. For brass and lead patches, velocity sensitivity is the difference between mechanical and expressive.

**Implementation approach**: In `Preset.triggerVoice()`, after setting `freq`, also set a named const (e.g., `"velocity"`) to `CoreFloat(note.velocity) / 127.0`. Then presets can reference `velocity` in their amp or filter expressions. The ADSR `scale` parameter already exists and could be driven by velocity. Alternatively, a `velocityScale` const could be multiplied into the amp prod.

### 3d. Portamento / glide (LOW-MEDIUM IMPACT)

**Current state**: Frequency changes are instantaneous on noteOn.

**What's missing**: Smooth pitch gliding between notes (portamento). When a new note triggers while a previous note was playing, the frequency should glide from the old pitch to the new pitch over a configurable time.

**Why it matters**: Portamento is characteristic of monophonic lead sounds (Minimoog, TB-303) and adds expressiveness to legato playing. It is less important for polyphonic patches.

**Implementation approach**: Instead of setting `freq` directly on noteOn, a glide arrow could interpolate from the previous frequency to the new one over a configurable duration. This would require per-voice state tracking of the previous frequency.

### 3e. LFO as a first-class arrow type (LOW IMPACT, nice-to-have)

**Current state**: LFOs are built manually by composing `prod([freq * identity]) -> osc(sine)`. This works but is verbose in JSON and requires understanding the frequency-to-oscillator composition pattern.

**What's missing**: A dedicated `lfo` JSON node that encapsulates the frequency/shape/depth pattern. E.g., `{"lfo": {"freq": 5, "shape": "sineOsc", "depth": 0.5, "name": "filterLFO"}}`.

**Why it matters**: Primarily a quality-of-life improvement for preset authoring. The existing compose/prod pattern works correctly -- this would just reduce JSON verbosity and make presets easier to read and write.

### 3f. Filter self-oscillation / higher resonance control (LOW IMPACT)

**Current state**: The biquad filter's resonance (Q) is clamped at the mathematical level by `max(0.001, resonance)` but there is no explicit self-oscillation behavior.

**What's missing**: At very high resonance (Q > ~20), analog filters begin to self-oscillate, producing a sine tone at the cutoff frequency. This is used creatively in some patches (acid bass, special effects). The current biquad should approach this naturally at high Q values, but it may become numerically unstable. Testing would be needed.

**Why it matters**: Low priority. Self-oscillation is a niche technique, mostly for acid/TB-303 sounds.

### 3g. Unison / super-saw mode (LOW IMPACT -- partially covered)

**Current state**: The `Choruser` provides frequency-spread voices, which is the core of unison/super-saw.

**What's close**: The choruser already implements the frequency-spread pattern. The main limitation is that it re-processes the same inner arrow at different frequencies sequentially (see the `Choruser.process` loop), which multiplies CPU cost linearly with voice count.

**Why it matters**: Super-saw (7+ detuned sawtooths) is the backbone of trance, EDM, and modern pop synthesis. The choruser covers this, but performance at high voice counts may be a concern given the CPU-sensitive nature of the render path.

---

## 4. Five Specific Preset Recipes in Arrow JSON Format

These presets are designed to work with the current engine without modifications. They exercise different combinations of the existing primitives to produce distinct timbres.

### Preset 1: "Warm Analog Pad"

Lush, evolving pad using detuned sawtooths with heavy chorus and slow envelopes. Inspired by Roland Juno-106 string pads.

Signal flow:
- Osc1: Sawtooth, 0 octave, -7 cent detune, chorus 5 voices at 15 cents
- Osc2: Sawtooth, 0 octave, +7 cent detune, chorus 3 voices at 10 cents
- Osc3: Triangle, -1 octave (sub), no chorus
- Mix: 0.4 / 0.4 / 0.2
- Amp env: A=1.5s, D=1.0s, S=0.85, R=2.5s
- Filter: Cutoff = freq * 3 (key-tracked), resonance 0.6
- Filter env: A=2.0s, D=1.0s, S=0.8, R=2.0s
- Vibrato: 4.5 Hz, amp 1.5, delayed onset (attack 5s)
- Effects: Cathedral reverb, 70% wet

```json
{
 "name"   : "Warm Analog Pad",
 "rose"   : {"freq": 0.15, "leafFactor": 3, "phase": 1.57, "amp": 5},
 "effects": {"reverbPreset": 8, "delayTime": 0.4, "delayLowPassCutoff": 2000, "delayFeedback": 20, "reverbWetDryMix": 70, "delayWetDryMix": 25},
 "arrow"  : {
  "compose": { "arrows": [
    {
     "prod": { "of": [
       {
        "sum": { "of": [
          {
           "prod": { "of": [
             { "const": {"val": 0.4, "name": "osc1Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                    { "const": {"name": "freq", "val": 300} },
                    { "constOctave": {"name": "osc1Octave", "val": 0} },
                    { "constCent": {"name": "osc1CentDetune", "val": -7} },
                    { "identity": {}}
                   ]}},
                   {"compose": {"arrows": [
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 1.5}},
                       { "envelope": { "release": 0.1, "scale": 1, "name": "vibratoEnv", "attack": 5, "decay": 0.1, "sustain": 1 } },
                       { "sum": { "of": [
                         { "const": {"name": "vibratoOscShift", "val": 0.5}},
                         { "prod": { "of": [
                           { "const": {"name": "vibratoOscScale", "val": 0.5}},
                           { "compose": { "arrows": [
                             { "prod": { "of": [
                               { "const": {"val": 4.5, "name": "vibratoFreq"} },
                               { "identity": {} }
                             ]}},
                             { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc1VibWidth", "val": 1 } } } }
                           ]}}
                         ]}}
                       ]}}
                     ]}
                   },
                   {"control": {}}
                   ]}}
                 ]}},
                { "osc": {"name": "osc1", "shape": "sawtoothOsc", "width": { "const": {"val": 1, "name": "osc1Width"} }} },
                { "choruser": {"name": "osc1Choruser", "valueToChorus": "freq", "chorusCentRadius": 15, "chorusNumVoices": 5 } }
              ]}}
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.4, "name": "osc2Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     {"const": {"name": "freq", "val": 300} },
                     {"constOctave": {"name": "osc2Octave", "val": 0} },
                     {"constCent": {"name": "osc2CentDetune", "val": 7} },
                     {"identity": {}}
                   ]}},
                   {"compose": {"arrows": [
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 1.5}},
                       { "envelope": { "release": 0.1, "scale": 1, "name": "vibratoEnv", "attack": 5, "decay": 0.1, "sustain": 1 } },
                       { "sum": { "of": [
                         { "const": {"name": "vibratoOscShift", "val": 0.5}},
                         { "prod": { "of": [
                           { "const": {"name": "vibratoOscScale", "val": 0.5}},
                           { "compose": { "arrows": [
                             { "prod": { "of": [
                               { "const": {"val": 4.5, "name": "vibratoFreq"} },
                               { "identity": {} }
                             ]}},
                             { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc2VibWidth", "val": 1 } } } }
                           ]}}
                         ]}}
                       ]}}
                     ]}
                   },
                   {"control": {}}
                   ]}}
                 ]}
                },
                { "osc": {"name": "osc2", "shape": "sawtoothOsc", "width": { "const": {"name": "osc2Width", "val": 1} }} },
                { "choruser": { "name": "osc2Choruser", "valueToChorus": "freq", "chorusCentRadius": 10, "chorusNumVoices": 3 } }
              ]}
             }
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.2, "name": "osc3Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     { "const": {"name": "freq", "val": 300} },
                     { "constOctave": {"name": "osc3Octave", "val": -1} },
                     { "constCent": {"name": "osc3CentDetune", "val": 0} },
                     { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 1.5} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 4.5, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc3VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc3", "shape": "triangleOsc", "width": { "const": {"name": "osc3Width", "val": 1} }} },
                { "choruser": { "name": "osc3Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1} }
               ]
              }
             }
           ]}
          }
        ]}
       },
       { "envelope": { "decay": 1.0, "sustain": 0.85, "attack": 1.5, "name": "ampEnv", "release": 2.5, "scale": 1 } }
      ]}
    },
    {
     "lowPassFilter": {
       "cutoff"   :
        {"sum": { "of": [
          { "const": {"name": "cutoffLow", "val": 80} },
          { "prod": { "of": [
            { "const": {"name": "freq", "val": 300} },
            { "const": {"name": "cutoffMultiplier", "val": 3} },
            { "envelope": { "release": 2.0, "scale": 1, "name": "filterEnv", "attack": 2.0, "decay": 1.0, "sustain": 0.8 } }
          ]}}
       ]}},
       "resonance": { "const": {"name": "resonance", "val": 0.6} },
       "name"     : "filter"
     }
   }]
  }
 }
}
```

---

### Preset 2: "Prophet Brass"

Punchy brass stab with aggressive filter envelope and slight detuning. Inspired by Sequential Prophet-5 brass patches.

Signal flow:
- Osc1: Sawtooth, 0 octave, 0 detune, no chorus
- Osc2: Square (pulse width 0.45), -1 octave, +3 cent detune, no chorus
- Osc3: Noise, low mix for breath texture
- Mix: 0.7 / 0.25 / 0.05
- Amp env: A=0.01s, D=0.2s, S=0.75, R=0.15s
- Filter: Cutoff = freq * 6 (key-tracked, opens wide then closes), resonance 1.4
- Filter env: A=0.01s, D=0.35s, S=0.3, R=0.1s (the fast-attack/medium-decay is what gives brass its "bite")
- Vibrato: 5.5 Hz, amp 1, delayed onset (attack 3s)
- Effects: Small room reverb, 25% wet

```json
{
 "name"   : "Prophet Brass",
 "rose"   : {"freq": 0.3, "leafFactor": 2, "phase": 0, "amp": 3},
 "effects": {"reverbPreset": 3, "delayTime": 0, "delayLowPassCutoff": 100000, "delayFeedback": 0, "reverbWetDryMix": 25, "delayWetDryMix": 0},
 "arrow"  : {
  "compose": { "arrows": [
    {
     "prod": { "of": [
       {
        "sum": { "of": [
          {
           "prod": { "of": [
             { "const": {"val": 0.7, "name": "osc1Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                    { "const": {"name": "freq", "val": 300} },
                    { "constOctave": {"name": "osc1Octave", "val": 0} },
                    { "constCent": {"name": "osc1CentDetune", "val": 0} },
                    { "identity": {}}
                   ]}},
                   {"compose": {"arrows": [
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 1}},
                       { "envelope": { "release": 0.1, "scale": 1, "name": "vibratoEnv", "attack": 3, "decay": 0.1, "sustain": 1 } },
                       { "sum": { "of": [
                         { "const": {"name": "vibratoOscShift", "val": 0.5}},
                         { "prod": { "of": [
                           { "const": {"name": "vibratoOscScale", "val": 0.5}},
                           { "compose": { "arrows": [
                             { "prod": { "of": [
                               { "const": {"val": 5.5, "name": "vibratoFreq"} },
                               { "identity": {} }
                             ]}},
                             { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc1VibWidth", "val": 1 } } } }
                           ]}}
                         ]}}
                       ]}}
                     ]}
                   },
                   {"control": {}}
                   ]}}
                 ]}},
                { "osc": {"name": "osc1", "shape": "sawtoothOsc", "width": { "const": {"val": 1, "name": "osc1Width"} }} },
                { "choruser": {"name": "osc1Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1 } }
              ]}}
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.25, "name": "osc2Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     {"const": {"name": "freq", "val": 300} },
                     {"constOctave": {"name": "osc2Octave", "val": -1} },
                     {"constCent": {"name": "osc2CentDetune", "val": 3} },
                     {"identity": {}}
                   ]}},
                   {"compose": {"arrows": [
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 1}},
                       { "envelope": { "release": 0.1, "scale": 1, "name": "vibratoEnv", "attack": 3, "decay": 0.1, "sustain": 1 } },
                       { "sum": { "of": [
                         { "const": {"name": "vibratoOscShift", "val": 0.5}},
                         { "prod": { "of": [
                           { "const": {"name": "vibratoOscScale", "val": 0.5}},
                           { "compose": { "arrows": [
                             { "prod": { "of": [
                               { "const": {"val": 5.5, "name": "vibratoFreq"} },
                               { "identity": {} }
                             ]}},
                             { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc2VibWidth", "val": 1 } } } }
                           ]}}
                         ]}}
                       ]}}
                     ]}
                   },
                   {"control": {}}
                   ]}}
                 ]}
                },
                { "osc": {"name": "osc2", "shape": "squareOsc", "width": { "const": {"name": "osc2Width", "val": 0.45} }} },
                { "choruser": { "name": "osc2Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1 } }
              ]}
             }
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.05, "name": "osc3Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     { "const": {"name": "freq", "val": 300} },
                     { "constOctave": {"name": "osc3Octave", "val": 0} },
                     { "constCent": {"name": "osc3CentDetune", "val": 0} },
                     { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 0} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 5.5, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc3VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc3", "shape": "noiseOsc", "width": { "const": {"name": "osc3Width", "val": 1} }} },
                { "choruser": { "name": "osc3Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1} }
               ]
              }
             }
           ]}
          }
        ]}
       },
       { "envelope": { "decay": 0.2, "sustain": 0.75, "attack": 0.01, "name": "ampEnv", "release": 0.15, "scale": 1 } }
      ]}
    },
    {
     "lowPassFilter": {
       "cutoff"   :
        {"sum": { "of": [
          { "const": {"name": "cutoffLow", "val": 100} },
          { "prod": { "of": [
            { "const": {"name": "freq", "val": 300} },
            { "const": {"name": "cutoffMultiplier", "val": 6} },
            { "envelope": { "release": 0.1, "scale": 1, "name": "filterEnv", "attack": 0.01, "decay": 0.35, "sustain": 0.3 } }
          ]}}
       ]}},
       "resonance": { "const": {"name": "resonance", "val": 1.4} },
       "name"     : "filter"
     }
   }]
  }
 }
}
```

---

### Preset 3: "Screaming Lead"

Fat, aggressive lead with multiple detuned sawtooths and biting filter. Inspired by Minimoog lead patches.

Signal flow:
- Osc1: Sawtooth, 0 octave, -5 cent detune, no chorus (raw)
- Osc2: Sawtooth, 0 octave, +5 cent detune, no chorus (raw)
- Osc3: Square, -1 octave (sub-oscillator for body), no detune
- Mix: 0.4 / 0.4 / 0.2
- Amp env: A=0.005s, D=0.5s, S=1.0, R=0.08s (nearly instant on/off)
- Filter: Cutoff = freq * 5, resonance 2.5 (aggressive peak)
- Filter env: A=0.005s, D=0.15s, S=0.5, R=0.08s
- Vibrato: 6 Hz, amp 2, delayed onset (attack 1.5s)
- Effects: Small room reverb 20% wet, slapback delay 150ms at 15% feedback

```json
{
 "name"   : "Screaming Lead",
 "rose"   : {"freq": 0.8, "leafFactor": 5, "phase": 0, "amp": 2},
 "effects": {"reverbPreset": 2, "delayTime": 0.15, "delayLowPassCutoff": 5000, "delayFeedback": 15, "reverbWetDryMix": 20, "delayWetDryMix": 30},
 "arrow"  : {
  "compose": { "arrows": [
    {
     "prod": { "of": [
       {
        "sum": { "of": [
          {
           "prod": { "of": [
             { "const": {"val": 0.4, "name": "osc1Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                    { "const": {"name": "freq", "val": 300} },
                    { "constOctave": {"name": "osc1Octave", "val": 0} },
                    { "constCent": {"name": "osc1CentDetune", "val": -5} },
                    { "identity": {}}
                   ]}},
                   {"compose": {"arrows": [
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 2}},
                       { "envelope": { "release": 0.1, "scale": 1, "name": "vibratoEnv", "attack": 1.5, "decay": 0.1, "sustain": 1 } },
                       { "sum": { "of": [
                         { "const": {"name": "vibratoOscShift", "val": 0.5}},
                         { "prod": { "of": [
                           { "const": {"name": "vibratoOscScale", "val": 0.5}},
                           { "compose": { "arrows": [
                             { "prod": { "of": [
                               { "const": {"val": 6, "name": "vibratoFreq"} },
                               { "identity": {} }
                             ]}},
                             { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc1VibWidth", "val": 1 } } } }
                           ]}}
                         ]}}
                       ]}}
                     ]}
                   },
                   {"control": {}}
                   ]}}
                 ]}},
                { "osc": {"name": "osc1", "shape": "sawtoothOsc", "width": { "const": {"val": 1, "name": "osc1Width"} }} },
                { "choruser": {"name": "osc1Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1 } }
              ]}}
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.4, "name": "osc2Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     {"const": {"name": "freq", "val": 300} },
                     {"constOctave": {"name": "osc2Octave", "val": 0} },
                     {"constCent": {"name": "osc2CentDetune", "val": 5} },
                     {"identity": {}}
                   ]}},
                   {"compose": {"arrows": [
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 2}},
                       { "envelope": { "release": 0.1, "scale": 1, "name": "vibratoEnv", "attack": 1.5, "decay": 0.1, "sustain": 1 } },
                       { "sum": { "of": [
                         { "const": {"name": "vibratoOscShift", "val": 0.5}},
                         { "prod": { "of": [
                           { "const": {"name": "vibratoOscScale", "val": 0.5}},
                           { "compose": { "arrows": [
                             { "prod": { "of": [
                               { "const": {"val": 6, "name": "vibratoFreq"} },
                               { "identity": {} }
                             ]}},
                             { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc2VibWidth", "val": 1 } } } }
                           ]}}
                         ]}}
                       ]}}
                     ]}
                   },
                   {"control": {}}
                   ]}}
                 ]}
                },
                { "osc": {"name": "osc2", "shape": "sawtoothOsc", "width": { "const": {"name": "osc2Width", "val": 1} }} },
                { "choruser": { "name": "osc2Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1 } }
              ]}
             }
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.2, "name": "osc3Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     { "const": {"name": "freq", "val": 300} },
                     { "constOctave": {"name": "osc3Octave", "val": -1} },
                     { "constCent": {"name": "osc3CentDetune", "val": 0} },
                     { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 0} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 6, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc3VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc3", "shape": "squareOsc", "width": { "const": {"name": "osc3Width", "val": 0.5} }} },
                { "choruser": { "name": "osc3Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1} }
               ]
              }
             }
           ]}
          }
        ]}
       },
       { "envelope": { "decay": 0.5, "sustain": 1.0, "attack": 0.005, "name": "ampEnv", "release": 0.08, "scale": 1 } }
      ]}
    },
    {
     "lowPassFilter": {
       "cutoff"   :
        {"sum": { "of": [
          { "const": {"name": "cutoffLow", "val": 150} },
          { "prod": { "of": [
            { "const": {"name": "freq", "val": 300} },
            { "const": {"name": "cutoffMultiplier", "val": 5} },
            { "envelope": { "release": 0.08, "scale": 1, "name": "filterEnv", "attack": 0.005, "decay": 0.15, "sustain": 0.5 } }
          ]}}
       ]}},
       "resonance": { "const": {"name": "resonance", "val": 2.5} },
       "name"     : "filter"
     }
   }]
  }
 }
}
```

---

### Preset 4: "Solina Strings"

Wide, diffuse string ensemble with heavy chorus. The signature sound of 70s/80s string machines.

Signal flow:
- Osc1: Sawtooth, 0 octave, 0 detune, chorus 7 voices at 20 cents (the Solina character)
- Osc2: Sawtooth, +1 octave, +3 cent detune, chorus 5 voices at 15 cents (upper shimmer)
- Osc3: off (mix 0)
- Mix: 0.6 / 0.4 / 0.0
- Amp env: A=0.15s, D=0.5s, S=1.0, R=1.0s (gentle bow-like attack)
- Filter: Cutoff = freq * 4 (key-tracked), resonance 0.5 (flat, warm)
- Filter env: A=0.2s, D=0.5s, S=0.9, R=1.0s (tracks amp roughly)
- Vibrato: 4 Hz, amp 0.8, subtle
- Effects: Large hall reverb, 65% wet

```json
{
 "name"   : "Solina Strings",
 "rose"   : {"freq": 0.2, "leafFactor": 4, "phase": 2.0, "amp": 6},
 "effects": {"reverbPreset": 6, "delayTime": 0, "delayLowPassCutoff": 100000, "delayFeedback": 0, "reverbWetDryMix": 65, "delayWetDryMix": 0},
 "arrow"  : {
  "compose": { "arrows": [
    {
     "prod": { "of": [
       {
        "sum": { "of": [
          {
           "prod": { "of": [
             { "const": {"val": 0.6, "name": "osc1Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                    { "const": {"name": "freq", "val": 300} },
                    { "constOctave": {"name": "osc1Octave", "val": 0} },
                    { "constCent": {"name": "osc1CentDetune", "val": 0} },
                    { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                      { "const": {"name": "vibratoAmp", "val": 0.8} },
                      { "compose": { "arrows": [
                         { "prod": { "of": [
                           { "const": {"val": 4, "name": "vibratoFreq"} },
                           { "identity": {} }
                         ]}},
                         { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc1VibWidth", "val": 1} }} }
                      ]}}
                    ]}
                   }
                 ]}},
                { "osc": {"name": "osc1", "shape": "sawtoothOsc", "width": { "const": {"val": 1, "name": "osc1Width"} }} },
                { "choruser": {"name": "osc1Choruser", "valueToChorus": "freq", "chorusCentRadius": 20, "chorusNumVoices": 7 } }
              ]}}
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.4, "name": "osc2Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     {"const": {"name": "freq", "val": 300} },
                     {"constOctave": {"name": "osc2Octave", "val": 1} },
                     {"constCent": {"name": "osc2CentDetune", "val": 3} },
                     {"identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 0.8} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 4, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc2VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc2", "shape": "sawtoothOsc", "width": { "const": {"name": "osc2Width", "val": 1} }} },
                { "choruser": { "name": "osc2Choruser", "valueToChorus": "freq", "chorusCentRadius": 15, "chorusNumVoices": 5 } }
              ]}
             }
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.0, "name": "osc3Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     { "const": {"name": "freq", "val": 300} },
                     { "constOctave": {"name": "osc3Octave", "val": 0} },
                     { "constCent": {"name": "osc3CentDetune", "val": 0} },
                     { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 0} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 4, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc3VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc3", "shape": "noiseOsc", "width": { "const": {"name": "osc3Width", "val": 1} }} },
                { "choruser": { "name": "osc3Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1} }
               ]
              }
             }
           ]}
          }
        ]}
       },
       { "envelope": { "decay": 0.5, "sustain": 1.0, "attack": 0.15, "name": "ampEnv", "release": 1.0, "scale": 1 } }
      ]}
    },
    {
     "lowPassFilter": {
       "cutoff"   :
        {"sum": { "of": [
          { "const": {"name": "cutoffLow", "val": 60} },
          { "prod": { "of": [
            { "const": {"name": "freq", "val": 300} },
            { "const": {"name": "cutoffMultiplier", "val": 4} },
            { "envelope": { "release": 1.0, "scale": 1, "name": "filterEnv", "attack": 0.2, "decay": 0.5, "sustain": 0.9 } }
          ]}}
       ]}},
       "resonance": { "const": {"name": "resonance", "val": 0.5} },
       "name"     : "filter"
     }
   }]
  }
 }
}
```

---

### Preset 5: "Moog Sub Bass"

Deep, weighty bass with filter pluck. The Moog bass sound that anchors funk, R&B, and electronic music.

Signal flow:
- Osc1: Square, 0 octave, pulse width 0.5 (maximum fundamental content)
- Osc2: Sawtooth, +1 octave, 0 detune (adds harmonic definition above the fundamental)
- Osc3: off (mix 0)
- Mix: 0.7 / 0.3 / 0.0
- Amp env: A=0.005s, D=0.6s, S=0.6, R=0.2s
- Filter: Cutoff = freq * 2 (tight), resonance 0.9
- Filter env: A=0.005s, D=0.3s, S=0.25, R=0.15s (pluck shape: opens briefly then closes)
- Vibrato: None
- Effects: No reverb, no delay

```json
{
 "name"   : "Moog Sub Bass",
 "rose"   : {"freq": 0.1, "leafFactor": 2, "phase": 0, "amp": 1},
 "effects": {"reverbPreset": 1, "delayTime": 0, "delayLowPassCutoff": 100000, "delayFeedback": 0, "reverbWetDryMix": 0, "delayWetDryMix": 0},
 "arrow"  : {
  "compose": { "arrows": [
    {
     "prod": { "of": [
       {
        "sum": { "of": [
          {
           "prod": { "of": [
             { "const": {"val": 0.7, "name": "osc1Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                    { "const": {"name": "freq", "val": 300} },
                    { "constOctave": {"name": "osc1Octave", "val": 0} },
                    { "constCent": {"name": "osc1CentDetune", "val": 0} },
                    { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                      { "const": {"name": "vibratoAmp", "val": 0} },
                      { "compose": { "arrows": [
                         { "prod": { "of": [
                           { "const": {"val": 1, "name": "vibratoFreq"} },
                           { "identity": {} }
                         ]}},
                         { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc1VibWidth", "val": 1} }} }
                      ]}}
                    ]}
                   }
                 ]}},
                { "osc": {"name": "osc1", "shape": "squareOsc", "width": { "const": {"val": 0.5, "name": "osc1Width"} }} },
                { "choruser": {"name": "osc1Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1 } }
              ]}}
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.3, "name": "osc2Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     {"const": {"name": "freq", "val": 300} },
                     {"constOctave": {"name": "osc2Octave", "val": 1} },
                     {"constCent": {"name": "osc2CentDetune", "val": 0} },
                     {"identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 0} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 1, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc2VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc2", "shape": "sawtoothOsc", "width": { "const": {"name": "osc2Width", "val": 1} }} },
                { "choruser": { "name": "osc2Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1 } }
              ]}
             }
           ]}
          },
          {
           "prod": { "of": [
             { "const": {"val": 0.0, "name": "osc3Mix"} },
             {
              "compose": { "arrows": [
                {
                 "sum": { "of": [
                   { "prod": { "of": [
                     { "const": {"name": "freq", "val": 300} },
                     { "constOctave": {"name": "osc3Octave", "val": 0} },
                     { "constCent": {"name": "osc3CentDetune", "val": 0} },
                     { "identity": {}}
                   ]}},
                   { "prod": { "of": [
                       { "const": {"name": "vibratoAmp", "val": 0} },
                       { "compose": { "arrows": [
                          { "prod": { "of": [
                            { "const": {"val": 1, "name": "vibratoFreq"} },
                            { "identity": {} }
                          ]}},
                          { "osc": {"name": "vibratoOsc", "shape": "sineOsc", "width": { "const": {"name": "osc3VibWidth", "val": 1} }} }
                       ]}}
                     ]}
                    }
                 ]}
                },
                { "osc": {"name": "osc3", "shape": "noiseOsc", "width": { "const": {"name": "osc3Width", "val": 1} }} },
                { "choruser": { "name": "osc3Choruser", "valueToChorus": "freq", "chorusCentRadius": 0, "chorusNumVoices": 1} }
               ]
              }
             }
           ]}
          }
        ]}
       },
       { "envelope": { "decay": 0.6, "sustain": 0.6, "attack": 0.005, "name": "ampEnv", "release": 0.2, "scale": 1 } }
      ]}
    },
    {
     "lowPassFilter": {
       "cutoff"   :
        {"sum": { "of": [
          { "const": {"name": "cutoffLow", "val": 40} },
          { "prod": { "of": [
            { "const": {"name": "freq", "val": 300} },
            { "const": {"name": "cutoffMultiplier", "val": 2} },
            { "envelope": { "release": 0.15, "scale": 1, "name": "filterEnv", "attack": 0.005, "decay": 0.3, "sustain": 0.25 } }
          ]}}
       ]}},
       "resonance": { "const": {"name": "resonance", "val": 0.9} },
       "name"     : "filter"
     }
   }]
  }
 }
}
```

---

## 5. Summary of Recommendations

### Presets to add immediately (no engine changes needed)

1. **Warm Analog Pad** -- slow envelopes, detuned saws, heavy chorus, reverb
2. **Prophet Brass** -- fast filter envelope with medium decay, saw+square, moderate resonance
3. **Screaming Lead** -- dual detuned saws + sub-square, aggressive filter, slapback delay
4. **Solina Strings** -- heavy chorus (7 voices/20 cents), gentle attack, lots of reverb
5. **Moog Sub Bass** -- square + saw, tight low-pass, filter pluck envelope, dry

### Engine improvements by priority

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| 1 | High-pass / band-pass filters | Low | Opens up pad clarity, wah effects, formant sounds |
| 2 | Velocity sensitivity | Low-Medium | Essential for expressive MIDI playback |
| 3 | Document key-tracking pattern | Minimal | Already possible; presets just need to use it |
| 4 | Portamento / glide | Medium | Important for monophonic lead expressiveness |
| 5 | LFO convenience node | Low | JSON authoring quality-of-life |
| 6 | Filter self-oscillation testing | Low | Niche but characterful for acid bass |

### References for further study

- Gordon Reid, "Synth Secrets" series, Sound On Sound magazine (1999-2004) -- 63-part series covering the physics and synthesis of every instrument family
- Fred Welsh, "Welsh's Synthesizer Cookbook" -- parameter-by-parameter recipes for dozens of classic patches on 2-oscillator subtractive synths
- Mark Vail, "The Synthesizer" -- historical context for Minimoog, Prophet-5, Jupiter-8, and Oberheim patch design
- Miller Puckette, "The Theory and Technique of Electronic Music" (freely available) -- mathematical foundations of subtractive synthesis and filter design
- The Audio EQ Cookbook (w3.org/TR/audio-eq-cookbook) -- already referenced in the codebase; contains HPF and BPF coefficient formulas alongside the LPF already implemented
