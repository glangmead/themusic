# Research: Ambient Pads via Physical Modeling

## Baby Audio Atoms — Mass-Spring Physical Modeling

Baby Audio's **Atoms** synth uses a mass-spring network simulation rather than
waveguides or comb filters. The sound engine models interconnected masses and
springs with inertia, weight, and nonlinear interactions, excited by a virtual
bow.

### Atoms Architecture

- **Excitation**: A virtual bow continuously drives the mass-spring network.
  The `Force` parameter controls bow pressure (more pressure = noisier, sharper
  harmonics). The `Overtones` parameter moves the bow position along the
  network (closer to the boundary = brighter, like bowing near the bridge on a
  violin).
- **Resonator**: The network of masses and springs itself. `Chaos` increases
  nonlinear interactions between masses, producing pitch drift and detuning.
  `Order` increases high-frequency damping in the springs (acts like a low-pass
  filter on the resonating system).
- **Envelope from physics**: Attack varies the onset speed of the bow (abrupt =
  pluck, gradual = pad). Release controls damping in the network (short = quick
  decay, long = infinite sustain).
- **Effects inside the model**: Chorus and vibrato come from varying the pickup
  position on the springs or modulating spring stiffness — not from post-FX.
- **Four sonic profiles**: Different calibrations of the mass-spring network
  parameters.

### Mass-Spring DSP: How It Works

A mass-spring-damper system is mathematically equivalent to a two-pole IIR
filter driven by an impulse. The standard numerical integration method is the
**symplectic Euler method**:

```
For each mass i at each sample:
  force[i] = sum of spring forces from connected masses + external force (bow)
  velocity[i] += (force[i] / mass[i]) * dt
  position[i] += velocity[i] * dt
  output = position[pickup_mass]
```

Spring force between two masses: `F = -k * (pos_a - pos_b - rest_length)`
plus damping: `F_damp = -d * (vel_a - vel_b)`.

The `mi-gen` toolbox (ACROE/ICA research) implements this in Max/MSP gen~ and
Faust: https://github.com/mi-creative/mi-gen

Reference paper: "Analysis of Damped Mass-Spring Systems for Sound Synthesis"
(EURASIP Journal on Advances in Signal Processing, 2009).

## Approaches for Implementation in Our Arrow System

### Option A: Mass-Spring Network (What Atoms Does)

Add a new `Arrow11` subclass that simulates N masses connected by springs.

```
MassSpringNetwork: Arrow11
  - masses: [CoreFloat]          // mass values
  - positions: [CoreFloat]       // current positions
  - velocities: [CoreFloat]      // current velocities
  - springs: [(from, to, k, d)]  // connectivity, stiffness, damping
  - bowPosition: Int             // which mass the bow excites
  - bowForce: CoreFloat          // continuous excitation amplitude
  - pickupPosition: Int          // which mass we read output from
```

Per-sample loop (symplectic Euler):
1. Calculate spring forces on each mass
2. Add bow excitation force to the bowed mass (filtered noise or friction model)
3. Update velocities, then positions
4. Output = position of pickup mass

Pros: Organic, nonlinear, evolving timbres. Natural sustain via continuous bow.
Cons: N masses = N force calculations per sample. CPU cost scales with network
size. Tuning to specific pitches requires careful spring constant selection
(resonant frequency of a mass-spring chain depends on k, m, and chain length).

### Option B: Extended Comb Filter / Waveguide (Closer to airport_piano_comb)

Our `CombFilter` already does Karplus-Strong (one-shot noise burst → feedback
delay → decaying pluck). To make sustained pads, change the excitation from a
one-shot burst to **continuous filtered noise**:

```
Signal flow:
  continuous noise → envelope (slow attack/sustain) → comb filter (feedback ~0.99)
                                                        ↓
                                                    low-pass in feedback loop
                                                        ↓
                                                      output
```

Modifications to current system:
- Remove (or lengthen) the amplitude envelope's decay so the noise excitation
  sustains.
- The comb filter's feedback handles the pitch; the continuous noise keeps
  energy flowing so the tone doesn't decay.
- Add a low-pass filter **inside** the feedback loop (not after it) for
  frequency-dependent damping — high frequencies die faster, like a real string.
- Modulate the noise amplitude with a slow LFO for "bowed" feel.

This is essentially a bowed-string waveguide model simplified to one delay
line. It already works with our `CombFilter` class — the main change is in the
preset JSON: use an envelope with long sustain on the noise source instead of a
short decay.

Pros: Almost free — reuses existing `CombFilter`. CPU cost identical to current
airport_piano_comb. Easy to tune (frequency = pitch).
Cons: Less organic than mass-spring. Single delay line = single mode of
vibration (harmonics only, no inharmonicity without extra work).

### Option C: Banded Waveguide / Modal Resonator

Multiple comb filters in parallel, each tuned to a different partial. This
models objects with inharmonic spectra (bells, bars, bowls, metallic pads).

```
noise → [comb @ f1, comb @ f2, comb @ f3, ...] → sum → output
```

Each comb has its own feedback and damping. The partial frequencies don't need
to be harmonic — set them to ratios like 1.0, 2.76, 5.40, 8.93 for bell-like
timbres.

This could be implemented as a new `Arrow11` subclass `BandedWaveguide` that
internally owns N `CombFilter` instances and sums their outputs. Or it could be
expressed in preset JSON as a `sum` of `combFilter` nodes fed by the same noise
source.

Pros: Inharmonic spectra. Rich, evolving pad sounds. Moderate CPU.
Cons: More comb filters = more CPU. Tuning the partial ratios by hand.

## Practical Next Steps

1. **Quick experiment (Option B)**: Duplicate `airports_piano_comb.json` and
   change the envelope to `attack: 2.0, decay: 0, sustain: 1.0, release: 4.0`.
   This gives continuous noise excitation into the comb filter — instant
   sustained pad. Add slow LFO on `combFeedback` or noise amplitude.

2. **Richer version (Option C)**: Stack 3-4 comb filters at different frequency
   ratios fed by the same noise source. Each with slightly different feedback
   values so higher partials decay faster.

3. **Full mass-spring (Option A)**: New `MassSpringNetwork` Arrow11 subclass.
   Most work but most interesting results.

## Sources

- [Baby Audio Atoms — product page](https://babyaud.io/atoms)
- [Baby Audio — Ambient Pads blog post](https://babyaud.io/blog/ambient-pads)
- [Atoms review — CDM](https://cdm.link/baby-audio-atoms-tested/)
- [Atoms review — Synthanatomy](https://synthanatomy.com/2024/11/baby-audio-atoms-new-physical-modeling-synthesizer-plugin-with-mass-and-springs.html)
- [mi-gen mass-interaction toolbox](https://github.com/mi-creative/mi-gen)
- [Analysis of Damped Mass-Spring Systems for Sound Synthesis](https://www.researchgate.net/publication/220497186_Analysis_of_Damped_Mass-Spring_Systems_for_Sound_Synthesis)
- [Karplus-Strong — Wikipedia](https://en.wikipedia.org/wiki/Karplus%E2%80%93Strong_string_synthesis)
- [Digital Waveguide Models — Julius O. Smith III](https://www.dsprelated.com/freebooks/pasp/Digital_Waveguide_Models.html)
- [Banded Waveguides for Bowed Bar Percussion](https://quod.lib.umich.edu/i/icmc/bbp2372.1999.408?rgn=main&view=fulltext)
- [Mutable Instruments Elements resonator source](https://github.com/pichenettes/eurorack/blob/master/elements/dsp/resonator.cc)
- [Physical Modelling in Csound](https://flossmanual.csound.com/sound-synthesis/physical-modelling)
