# Pattern tables

I'm imagining the user creating all these tables with SwiftUI lists. The names get plugged in elsewhere to build up the pattern's notes and modulators via function composition. It seems like a tractable way to present nested function composition in a linear format.

The interactions between rows are done by name. Names are text, e.g. emojis.

Track 0 is meant to be very close to aurora_arpeggio.json.

During playback, when one track has come to the end of the gap, it requests a new note. At this time a conductor calls next() on *all* the emitters in the table (I think), and then calls next() on its note emitter.

Might this design mean that the piece changes root note when the melody wants a new note, then again when the harmony wants a new note? No, that's what 🚙 is doing, it turns the root note changes into a WaitingIterator, keeping the tracks in sync about that piece of data.

## Emitters, i.e. Iterators (no inputs after construction, just next())

| Name | Output | arg1 | arg2 | Function | Updates |
| --- | --- | --- | --- | --- | --- |
| 🚙 | FloatEmitter | min: 10 | min: 25 | randFloat | each |
| ❤️ | IntEmitter | min: 0 | max: 3 | randInt | each |
| ♣️ | FloatEmitter | min: 0.0002 | max: 0.001 | exponentialRandFloat | each |
| ♦️ | FloatEmitter | min: 0.2 | max: 0.5 | randFloat | each |
| 🤖 | FloatEmitter | min: 0.3 | max: 0.6 | randFloat | each |
| 🐮 | FloatEmitter | min: 5 | max: 10 | randFloat | each |
| ⭐️ | FloatEmitter | min: 1 | max: 25 | randFloat | each |
| ♠️ | IntEmitter | min: 0 | max: 2 | shuffle | each |
| MyCoolRoots | RootEmitter | ["C", "E", "G"] |  | indexPicker: ❤️ | waiting: 🚙 |
| MyCoolOctaves | OctaveEmitter | [2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 5] |  | random | each |
| MyCoolScales | ScaleEmitter | [lydian, aeolean] |  | cyclic | each |
| MyLydian | ScaleEmitter | [lydian] |  | cyclic | each |
| OctavePlus | FloatEmitter | MyCoolOctaves | 1 | sum | each |
| 💥 | FloatEmitter | OctavePlus |  | reciprocal | each |

## Note material: match emitters with lists, to emit notes via music-theoretic data

| Name | Interval material | Interval picker | Octave | Scale | Scale root | Track |
| --- | --- | --- | --- | --- | --- | --- |
| MyCoolMelody | ["0","1","2","3","4","5","6"] | ♠️ | MyCoolOctaves | MyLydian | MyCoolRoots | 0 |
| MyCoolHarmony | ["[0,2,4]","[1,3,5]","[2,4,6]"] | ♠️ | MyCoolOctaves | MyCoolScales | MyCoolRoots | 1 |


## Modulators

| Name | Target handle | FloatEmitter |
| --- | --- | --- |
| A | overallAmp | 🤖 |
| B | overallAmp2 | 💥 |
| C | vibratoAmp | ♣️ |
| D | vibratoFreq | ⭐️ |
| E | ♦️.max | 🤖 |

## MusicPattern

|  | Track 0 | Track 1 |
| --- | --- | --- |
| Presets | Organ | Pad2 |
| Modulators | [A, B, C, D] | [E] |
| Notes | MyCoolMelody | MyCoolHarmony |
| Sustains | 🐮 | 🐮 |
| Gaps | ♦️ | ♦️ |
