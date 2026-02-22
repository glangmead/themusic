# Analysis: "Whump" Transient During Fast Trills on 5th Cluedo Preset

## Context

When trilling notes quickly (e.g., rapidly alternating two keyboard keys) on the 5th Cluedo preset, an audible "whump" transient is heard. This is a low-frequency percussive artifact, distinct from the intended synthesized tone.

The 5th Cluedo preset uses two active oscillators (a sawtooth at -500 cents detune with 3-voice chorus, and a square wave one octave down with 2-voice chorus), both multiplied by an amplitude envelope (`ampEnv`: attack 0.1s, decay 1s, sustain 1.0, release 0.1s), then fed through a low-pass filter whose cutoff is itself envelope-modulated (`filterEnv`: attack 0.1s, decay 0.3s, sustain 1.0, release 0.1s).

The system has a two-level voice allocation architecture:
- `SpatialPreset` has a `spatialLedger` routing each MIDI note to one of 12 `Preset` instances.
- Each `Preset` has exactly 1 internal voice (1 `ArrowWithHandles` containing the oscillators, envelopes, and filter).
- On retrigger (same MIDI note played again while still sounding), the existing voice's envelopes receive `noteOn()` again without releasing and reallocating.

---

## Candidate 1: Envelope Retrigger Evaluates `.attack` with Stale `timeOrigin`, Causing Amplitude Jump

### Mechanism

When a note is released and quickly re-attacked (the core of a fast trill), the ADSR envelope's `noteOn()` method captures `previousValue` as `valueAtAttack` (line 115 of `Envelope.swift`), and the attack ramp then interpolates from this value up to `env.scale` (1.0). However, there is a subtle ordering problem in the `env()` render function.

Look at `env()` (lines 51-75 of `Envelope.swift`):

```swift
func env(_ time: CoreFloat) -> CoreFloat {
    if newAttack || newRelease {
        timeOrigin = time
        newAttack = false
        newRelease = false
    }
    // ... then evaluate based on state
}
```

And `noteOn()` (lines 113-118):

```swift
func noteOn(_ note: MidiNote) {
    newAttack = true
    valueAtAttack = previousValue
    state = .attack
    startCallback?()
}
```

The `noteOn()` call happens on the main thread. The `env()` function runs on the real-time audio thread. There is a **race condition** between these two threads:

1. The audio thread is in the middle of processing a buffer. The envelope is in `.release` state, and `previousValue` is being updated sample-by-sample as it decays.
2. The main thread calls `noteOn()`. It reads `previousValue` (which the audio thread is also writing to). It sets `state = .attack` and `newAttack = true`.
3. On the audio thread, the *remaining samples in the current buffer* now evaluate in `.attack` state, but `timeOrigin` has not yet been reset (it will only be reset at the top of the *next* `env()` call when `newAttack` is checked).
4. This means for those remaining samples, the attack envelope is evaluated at `attackEnv.val(time - OLD_timeOrigin)`, which could be a very large value, placing us deep into the sustain segment of the attack curve -- jumping the envelope to the full sustain level instantaneously.

This instantaneous jump from a low release-phase amplitude to full sustain amplitude is a DC-offset-like step that produces the "whump" -- a broadband click/thump.

### Specific Code Locations

- `Envelope.swift`, lines 113-118: `noteOn()` sets `state` and `valueAtAttack` on the main thread
- `Envelope.swift`, lines 52-56: `newAttack` flag is only consumed at the start of a buffer, not at the exact sample where the transition occurs
- `Envelope.swift`, lines 58-62: the `.attack` case evaluates `attackEnv.val(time - timeOrigin)` which uses the stale `timeOrigin` until the flag is processed

### Suggested Fix

Make the state transition atomic from the audio thread's perspective. Instead of setting `state = .attack` directly in `noteOn()`, bundle the transition data into a single struct or use a lock-free flag that the audio thread consumes. The audio thread should be the one to actually perform the state change, the `timeOrigin` reset, and the `valueAtAttack` capture -- all in the same sample. For example:

```swift
// In noteOn(), instead of directly mutating state:
pendingAttack = true  // single atomic flag

// In env(), at the top of the per-sample loop:
if pendingAttack {
    pendingAttack = false
    valueAtAttack = previousValue  // captured at the exact sample
    timeOrigin = time
    state = .attack
    startCallback?()
}
```

This ensures the envelope never evaluates `.attack` with a stale `timeOrigin`.

---

## Candidate 2: Resonant Filter Sweep Through Low Frequencies on Retrigger

### Mechanism

The 5th Cluedo preset has **two** ADSR envelopes: `ampEnv` and `filterEnv`. Both are triggered by `triggerVoice()` in `Preset.swift` (lines 290-305):

```swift
private func triggerVoice(_ voiceIdx: Int, note: MidiNote, isRetrigger: Bool = false) {
    // ...
    let voice = voices[voiceIdx]
    for key in voice.namedADSREnvelopes.keys {
        for env in voice.namedADSREnvelopes[key]! {
            env.noteOn(note)
        }
    }
    // ...
}
```

Both envelopes' `noteOn()` sets `valueAtAttack = previousValue`. But the two envelopes may have very different `previousValue` levels at the moment of retrigger:

- **`ampEnv`** has release=0.1s. If the retrigger happens 50ms after note-off, `ampEnv.previousValue` is about 0.5 (halfway through release).
- **`filterEnv`** has release=0.1s and decay=0.3s. The filter envelope controls the low-pass cutoff. Its `previousValue` might be at a different phase of its own envelope.

The critical issue: the **filter envelope** controls a cutoff frequency range from `cutoffLow` (50 Hz) up to `cutoffLow + cutoff` (5050 Hz). When the filter envelope retriggers, it ramps from wherever its `previousValue` was back up to full scale. If the filter was nearly closed (low cutoff), the retrigger causes the cutoff to sweep rapidly from ~50 Hz upward. This fast filter sweep, combined with the resonance of 1.6 (above the Butterworth flat value of 0.707), produces a resonant "whump" -- a brief bass-heavy transient as the filter sweeps through low frequencies with gain from the resonance peak.

The 5th Cluedo preset's resonance of 1.6 is particularly problematic because resonant filters amplify frequencies near the cutoff. When the cutoff sweeps rapidly through the low-mid range during a retrigger, it momentarily boosts those frequencies, creating the characteristic thump.

### Specific Code Locations

- `5th_cluedo.json`, line 112: `ampEnv` with attack=0.1, release=0.1
- `5th_cluedo.json`, lines 117-124: `filterEnv` with attack=0.1, decay=0.3, release=0.1, modulating the cutoff from 50 Hz baseline
- `5th_cluedo.json`, line 125: resonance=1.6 (well above 0.707 Butterworth flat)
- `ToneGenerator.swift`, lines 502-545: `LowPassFilter2.filter()` -- the biquad filter with its `previousOutput1/2` state
- `Envelope.swift`, lines 89-111: `setFunctionsFromEnvelopeSpecs()` -- the attack ramp function uses `self.valueAtAttack` which is captured by closure reference, meaning the ramp starts from wherever the envelope was

### Suggested Fix

Two approaches:

1. **Smooth the filter cutoff retrigger**: When retriggering, instead of letting the filter envelope jump and sweep, add a minimum cutoff floor during retrigger. For instance, on retrigger, set `valueAtAttack` to `max(previousValue, sustainLevel * 0.5)` for the filter envelope specifically, preventing the cutoff from sweeping up from near-zero.

2. **Reset the biquad filter state on retrigger**: The `LowPassFilter2` accumulates `previousOutput1/2` and `previousInner1/2` state. When the cutoff changes rapidly, these stale state values interact with the new coefficients to produce transient ringing. Adding a `reset()` method to `LowPassFilter2` that zeros these values on note retrigger would eliminate the ringing (at the cost of a brief initial click, which could be smoothed).

---

## Candidate 3: AudioGate Open/Close Race Creates Brief Silence Gaps

### Mechanism

The `AudioGate` (in `Arrow.swift`, lines 110-122) is a binary on/off switch that controls whether the `AVAudioSourceNode` renders silence or actual audio. The gate lifecycle is managed by envelope callbacks in `Preset.setupLifecycleCallbacks()` (lines 118-135):

```swift
env.startCallback = { [weak self] in
    self?.activate()   // sets audioGate.isOpen = true
}
env.finishCallback = { [weak self] in
    // ...
    let allClosed = ampEnvs.allSatisfy { $0.state == .closed }
    if allClosed {
        self.deactivate()   // sets audioGate.isOpen = false
    }
}
```

The `startCallback` fires from `noteOn()` which runs on the main thread. The `finishCallback` fires from `env()` which runs on the audio thread (when release completes and state transitions to `.closed`).

During a fast trill, this sequence can occur:

1. Note A is released. The ampEnv enters `.release` state (release time = 0.1s).
2. 80ms later (before release completes), Note A is pressed again. `noteOn()` fires `startCallback` -> `activate()` -> `audioGate.isOpen = true`. But the gate was already open (it never closed because the release hadn't finished). No audible effect here.
3. Note A is released again. The ampEnv enters `.release` from a partially-attacked state.
4. The release completes. `finishCallback` fires on the audio thread. It checks `allClosed` and sets `audioGate.isOpen = false`.
5. But Note B might have *just* been pressed on the main thread, setting `state = .attack` and `newAttack = true`.
6. The audio thread sees `isOpen = false` in the `AVAudioSourceNode` render block and returns silence for the first part of the next buffer. Then when `newAttack` is processed, the gate opens.

This creates a brief dropout -- a few samples of silence inserted between the release-end and the new attack-start. The abrupt transition from signal to silence and back is perceived as a "whump" or click. The `AVAudioSourceNode` render callback (lines 28-37 of `AVAudioSourceNode+withSource.swift`) checks `source.isOpen` at the *start* of each buffer:

```swift
if !source.isOpen {
    // ... zero the buffer and return silence
    isSilence.pointee = true
    return noErr
}
```

This is a buffer-granularity check. If the gate closes and reopens within one buffer period (~5.8ms at 44100Hz/256 frames), the entire buffer is silent even though the note is already attacking.

### Specific Code Locations

- `Arrow.swift`, lines 110-122: `AudioGate` class with `isOpen` bool
- `AVAudioSourceNode+withSource.swift`, lines 28-37: render block early-exit on gate closed
- `Preset.swift`, lines 118-135: `setupLifecycleCallbacks()` where `finishCallback` can close the gate
- `Preset.swift`, lines 110-116: `activate()`/`deactivate()` toggle the gate
- `Envelope.swift`, lines 65-68: `finishCallback` fires when release time expires inside `env()`

### Suggested Fix

Do not use the `AudioGate` to hard-cut the signal. Instead, either:

1. **Remove the gate-close from `finishCallback` entirely** and let the envelope naturally produce zero output when closed. The gate's purpose is a CPU optimization (the render block can return early with silence). Instead, add a short delay (e.g., 50ms) before closing the gate after all envelopes report closed, giving time for a new noteOn to arrive and cancel the close:

```swift
env.finishCallback = { [weak self] in
    if let self = self {
        let allClosed = ampEnvs.allSatisfy { $0.state == .closed }
        if allClosed {
            // Delay the gate close to avoid race with incoming noteOn
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let stillAllClosed = ampEnvs.allSatisfy { $0.state == .closed }
                if stillAllClosed {
                    self.deactivate()
                }
            }
        }
    }
}
```

2. **Make the gate close gradual**: Instead of a binary `isOpen`, implement a short fade-out (e.g., 1ms linear ramp to zero) in the `AudioGate.process()` method, preventing the hard discontinuity.

---

## Summary

| # | Candidate | Severity | Confidence |
|---|-----------|----------|------------|
| 1 | Envelope retrigger evaluates `.attack` with stale `timeOrigin`, causing amplitude jump | High | High -- this is a clear thread-safety bug with direct audible consequence |
| 2 | Resonant filter sweep through low frequencies on retrigger | Medium | Medium -- depends on whether the resonance peak is strong enough to produce the specific "whump" character |
| 3 | AudioGate close/open race creates brief silence gaps | Medium | Medium -- the buffer-granularity gate check makes this plausible during fast note alternation |

The most likely primary cause is **Candidate 1**, as it directly produces a step discontinuity in the amplitude envelope, which is the classic source of clicks and thumps in synthesizer implementations. Candidates 2 and 3 may contribute additional coloration to the transient. A comprehensive fix would address all three.
