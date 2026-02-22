| Name | Output | arg1 | arg2 | Function | Updates |
| --- | --- | --- | --- | --- | --- |
| 🚙 | FloatEmitter | min: 10 | min: 25 | randFloat | each |
| ☔️ | FloatEmitter | min: 0 | max: 2 | cyclic | 🚙 |
| ❤️ | IntEmitter | min: 0 | max: 3 | randInt | each |
| ♣️ | FloatEmitter | min: 0.0002 | max: 0.001 | exponentialRandFloat | each |
| ♦️ | FloatEmitter | min: 0.2 | max: 0.5 | randFloat | each |
| 🤖 | FloatEmitter | min: 0.3 | max: 0.6 | randFloat | each |
| 🐮 | FloatEmitter | min: 5 | max: 10 | randFloat | each |
| ⭐️ | FloatEmitter | min: 1 | max: 25 | randFloat | each |
| ♠️ | IntEmitter | min: 0 | max: 2 | shuffle | each |
| MyCoolRoots | RootEmitter | ["C", "E", "G"] |  | ❤️ | each |
| MyCoolOctaves | OctaveEmitter | [2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 5] |  | random | each |
| MyCoolScales | ScaleEmitter | [lydian, aeolean] |  | cyclic | each |
| MyLydian | ScaleEmitter | [lydian] |  | cyclic | each |
| OctavePlus | FloatEmitter | MyCoolOctaves | 1 | sum | each |
| 💥 | FloatEmitter | OctavePlus |  | reciprocal | each |
