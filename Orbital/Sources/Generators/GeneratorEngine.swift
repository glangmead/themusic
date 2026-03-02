//
//  GeneratorEngine.swift
//  Orbital
//
//  Converts a GeneratorSyntax into a ScorePatternSyntax.
//  This is a pure function: same params + same seed → same pattern.
//

import Foundation

// MARK: - Seeded RNG

/// A simple seeded LCG (Knuth multiplicative) for reproducible randomness.
/// Not cryptographically secure; intended only for musical pattern generation.
struct SeededRNG {
  private var state: UInt64

  init(seed: Int) {
    state = UInt64(bitPattern: Int64(seed &* 6364136223846793005 &+ 1442695040888963407))
    if state == 0 { state = 1 }
  }

  mutating func nextBool() -> Bool {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return (state >> 63) == 1
  }

  mutating func nextInt(in range: ClosedRange<Int>) -> Int {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    let span = UInt64(range.upperBound - range.lowerBound + 1)
    return range.lowerBound + Int(state % span)
  }
}

// MARK: - GeneratorEngine

struct GeneratorEngine {

  // MARK: Public entry point

  /// Convert a GeneratorSyntax into a fully specified ScorePatternSyntax.
  static func generate(_ params: GeneratorSyntax) -> ScorePatternSyntax {
    let seed = params.randomSeed ?? Int.random(in: 0...Int.max)
    var rng = SeededRNG(seed: seed)

    let chordDegrees = params.chordType.degrees
    let chordCount = motionChordCount(params.motion, scaleSize: scaleSize(params.scaleType))
    let totalBeats = params.beatsPerChord * Double(chordCount)

    let chordEvents = buildChordEvents(params, chordDegrees: chordDegrees, chordCount: chordCount, rng: &rng)
    let tracks = buildTracks(params, chordCount: chordCount, totalBeats: totalBeats, rng: &rng)

    return ScorePatternSyntax(
      bpm: params.bpm,
      totalBeats: totalBeats,
      loop: true,
      key: ScoreKeySyntax(root: params.rootNote, scale: params.scaleType.tonicScaleName),
      chordEvents: chordEvents,
      tracks: tracks
    )
  }

  // MARK: - Chord Events

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  private static func buildChordEvents(
    _ params: GeneratorSyntax,
    chordDegrees: [Int],
    chordCount: Int,
    rng: inout SeededRNG
  ) -> [ChordEventSyntax] {
    let bpc = params.beatsPerChord
    var events: [ChordEventSyntax] = []

    // Opening chord (always setChord to establish the initial voicing):
    events.append(ChordEventSyntax(beat: 0, op: "setChord", degrees: chordDegrees, inversion: 0))

    switch params.motion {

    // --- Functional diatonic progressions (use setRoman for labeled chords) ---

    case .drone:
      break // Only the opening setChord needed

    case .shuttle:
      let romans = isMinorScale(params.scaleType) ? ["i", "V"] : ["I", "V"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    case .plagal:
      let romans = isMinorScale(params.scaleType) ? ["i", "iv"] : ["I", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    case .fourChords:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "III", "VII"] : ["I", "V", "vi", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    case .oneLoop:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "iv"] : ["I", "V", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    case .twoLoop:
      // Uses bVII and bVI which parseRomanNumeral already handles (confirmed in guitar_rift.json)
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "VI", "iv"] : ["I", "bVII", "bVI", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    case .descendingThirds:
      let romans = isMinorScale(params.scaleType) ? ["i", "VI", "iv", "ii"] : ["I", "vi", "IV", "ii"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    case .descendingFifths:
      let romans = isMinorScale(params.scaleType)
        ? ["i", "iv", "VII", "III", "VI", "ii", "V", "i"]
        : ["I", "IV", "vii", "iii", "vi", "ii", "V", "I"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events, openingDegrees: chordDegrees)

    // --- Stochastic ---

    case .randomWalk:
      var beat = bpc
      for _ in 1..<chordCount {
        let n = rng.nextBool() ? 1 : -1
        events.append(ChordEventSyntax(beat: beat, op: "T", n: n))
        beat += bpc
      }

    case .shepardDescent:
      var beat = bpc
      for _ in 1..<chordCount {
        events.append(ChordEventSyntax(beat: beat, op: "T", n: -1))
        beat += bpc
      }

    // --- Parallel motion within scale (Debussy) ---

    case .parallelAscending:
      var beat = bpc
      for _ in 1..<chordCount {
        events.append(ChordEventSyntax(beat: beat, op: "T", n: 1))
        beat += bpc
      }

    case .parallelDescending:
      var beat = bpc
      for _ in 1..<chordCount {
        events.append(ChordEventSyntax(beat: beat, op: "T", n: -1))
        beat += bpc
      }

    case .parallelRandom:
      var beat = bpc
      for _ in 1..<chordCount {
        let n = rng.nextBool() ? 1 : -1
        events.append(ChordEventSyntax(beat: beat, op: "T", n: n))
        beat += bpc
      }

    // --- Macro-level scale navigation (Debussy) ---

    case .acousticBridge:
      // Structure: diatonic(4) → acoustic(4) → whole-tone(4) → acoustic(4) → diatonic(4)
      // totalBeats = bpc × 20, chordCount = 20
      let diatonicKey = params.rootNote
      let diatonicScale = params.scaleType.tonicScaleName
      let acousticScale = GeneratorScaleType.acoustic.tonicScaleName
      let wholeToneScale = GeneratorScaleType.wholeTone.tonicScaleName

      appendKeyShift(at: bpc * 4, root: diatonicKey, scale: acousticScale, to: &events)
      appendKeyShift(at: bpc * 8, root: diatonicKey, scale: wholeToneScale, to: &events)
      appendKeyShift(at: bpc * 12, root: diatonicKey, scale: acousticScale, to: &events)
      appendKeyShift(at: bpc * 16, root: diatonicKey, scale: diatonicScale, to: &events)
      // Add ascending T steps within each section for motion
      for i in 1..<chordCount {
        events.append(ChordEventSyntax(beat: bpc * Double(i), op: "T", n: 1))
      }

    case .octatonicImmersion:
      // Structure: diatonic(4) → octatonic(8) → diatonic(4) = 16 chords
      let diatonicKey = params.rootNote
      let diatonicScale = params.scaleType.tonicScaleName
      let octatonicScale = GeneratorScaleType.octatonic.tonicScaleName

      appendKeyShift(at: bpc * 4, root: diatonicKey, scale: octatonicScale, to: &events)
      appendKeyShift(at: bpc * 12, root: diatonicKey, scale: diatonicScale, to: &events)
      // T steps within each section
      for i in 1..<chordCount {
        events.append(ChordEventSyntax(beat: bpc * Double(i), op: "T", n: 1))
      }
    }

    // Sort by beat so HarmonyTimeline.state(at:) works correctly
    return events.sorted { $0.beat < $1.beat }
  }

  // MARK: - Tracks

  private static func buildTracks(
    _ params: GeneratorSyntax,
    chordCount: Int,
    totalBeats: Double,
    rng: inout SeededRNG
  ) -> [ScoreTrackSyntax] {
    let bpc = params.beatsPerChord
    let chordSize = params.chordType.degrees.count
    let presets = resolvedPresets(params)
    let voicing = params.voicing ?? defaultVoicing(params.texture)

    switch params.texture {

    case .pad:
      return [padTrack(name: "Pad", preset: presets[0], bpc: bpc,
                       chordCount: chordCount, octave: 3, voicing: voicing)]

    case .arpeggio:
      return [arpeggioTrack(name: "Arpeggio", preset: presets[0], bpc: bpc,
                            chordCount: chordCount, chordSize: chordSize, octave: 4)]

    case .melody:
      return [melodyTrack(name: "Melody", preset: presets[0], bpc: bpc,
                          chordCount: chordCount, chordSize: chordSize, octave: 4, rng: &rng)]

    case .satb:
      return satbTracks(presets: presets, bpc: bpc, chordCount: chordCount,
                        chordSize: chordSize, rng: &rng)

    case .bassAndMelody:
      return [
        bassTrack(preset: presets[0], bpc: bpc, chordCount: chordCount, octave: 2),
        melodyTrack(name: "Melody", preset: presets[1], bpc: bpc,
                    chordCount: chordCount, chordSize: chordSize, octave: 4, rng: &rng)
      ]

    case .full:
      return [
        bassTrack(preset: presets[0], bpc: bpc, chordCount: chordCount, octave: 2),
        padTrack(name: "Pad", preset: presets[1], bpc: bpc,
                 chordCount: chordCount, octave: 3, voicing: voicing),
        melodyTrack(name: "Melody", preset: presets[2], bpc: bpc,
                    chordCount: chordCount, chordSize: chordSize, octave: 5, rng: &rng)
      ]
    }
  }

  // MARK: - Track builders

  // swiftlint:disable:next function_parameter_count
  private static func padTrack(
    name: String, preset: String, bpc: Double,
    chordCount: Int, octave: Int, voicing: VoicingStyle
  ) -> ScoreTrackSyntax {
    let notes = (0..<chordCount).map { _ in
      ScoreNoteSyntax(type: .currentChord, durationBeats: bpc)
    }
    return ScoreTrackSyntax(
      name: name, presetFilename: preset, numVoices: 8,
      octave: octave, voicing: voicing, sustainFraction: 0.95, notes: notes
    )
  }

  // swiftlint:disable:next function_parameter_count
  private static func arpeggioTrack(
    name: String, preset: String, bpc: Double,
    chordCount: Int, chordSize: Int, octave: Int
  ) -> ScoreTrackSyntax {
    let noteDuration = bpc / Double(chordSize)
    var notes: [ScoreNoteSyntax] = []
    for _ in 0..<chordCount {
      for idx in 0..<chordSize {
        notes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: noteDuration, index: idx))
      }
    }
    return ScoreTrackSyntax(
      name: name, presetFilename: preset, numVoices: 4,
      octave: octave, voicing: .closed, sustainFraction: 0.7, notes: notes
    )
  }

  // swiftlint:disable:next function_parameter_count
  private static func melodyTrack(
    name: String, preset: String, bpc: Double,
    chordCount: Int, chordSize: Int, octave: Int, rng: inout SeededRNG
  ) -> ScoreTrackSyntax {
    var notes: [ScoreNoteSyntax] = []
    for _ in 0..<chordCount {
      // Simple melodic cell: top → mid → bottom → mid, with hold on beat 3
      let top = chordSize - 1
      let mid = chordSize / 2
      notes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: bpc * 0.25, index: top))
      notes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: bpc * 0.25, index: mid))
      notes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: bpc * 0.25, index: 0))
      // Seeded variation: sometimes hold, sometimes restart from top
      if rng.nextBool() {
        notes.append(ScoreNoteSyntax(type: .hold, durationBeats: bpc * 0.25))
      } else {
        notes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: bpc * 0.25, index: mid))
      }
    }
    return ScoreTrackSyntax(
      name: name, presetFilename: preset, numVoices: 4,
      octave: octave, voicing: .closed, sustainFraction: 0.8, notes: notes
    )
  }

  private static func bassTrack(
    preset: String, bpc: Double, chordCount: Int, octave: Int
  ) -> ScoreTrackSyntax {
    let notes = (0..<chordCount).map { _ in
      ScoreNoteSyntax(type: .chordTone, durationBeats: bpc, index: 0)
    }
    return ScoreTrackSyntax(
      name: "Bass", presetFilename: preset, numVoices: 2,
      octave: octave, voicing: .closed, sustainFraction: 0.85, notes: notes
    )
  }

  private static func satbTracks(
    presets: [String], bpc: Double, chordCount: Int,
    chordSize: Int, rng: inout SeededRNG
  ) -> [ScoreTrackSyntax] {
    // For triads (size 3): Bass=0, Tenor=2 (fifth), Alto=1 (third), Soprano=0+octave
    // For 7th chords (size 4): Bass=0, Tenor=1, Alto=2, Soprano=3
    // Bass
    let bassNotes = (0..<chordCount).map { _ in
      ScoreNoteSyntax(type: .chordTone, durationBeats: bpc, index: 0)
    }
    // Tenor: fifth for triads, second note for 7th chords
    let tenorIdx = chordSize == 3 ? 2 : 1
    let tenorNotes = (0..<chordCount).map { _ in
      ScoreNoteSyntax(type: .chordTone, durationBeats: bpc, index: tenorIdx)
    }
    // Alto: third for triads, second-to-top for larger chords
    let altoIdx = chordSize >= 4 ? 2 : 1
    let altoNotes = (0..<chordCount).map { _ in
      ScoreNoteSyntax(type: .chordTone, durationBeats: bpc, index: altoIdx)
    }
    // Soprano: top voice, with seeded melodic variation
    var sopranoNotes: [ScoreNoteSyntax] = []
    let topIdx = chordSize - 1
    for _ in 0..<chordCount {
      sopranoNotes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: bpc * 0.5, index: topIdx))
      if rng.nextBool() {
        sopranoNotes.append(ScoreNoteSyntax(type: .hold, durationBeats: bpc * 0.5))
      } else {
        sopranoNotes.append(ScoreNoteSyntax(type: .chordTone, durationBeats: bpc * 0.5, index: topIdx - 1 < 0 ? 0 : topIdx - 1))
      }
    }

    let bassPreset  = presets.count > 0 ? presets[0] : defaultPresets(.satb)[0]
    let tenorPreset = presets.count > 1 ? presets[1] : defaultPresets(.satb)[1]
    let altoPreset  = presets.count > 2 ? presets[2] : defaultPresets(.satb)[2]
    let sopPreset   = presets.count > 3 ? presets[3] : defaultPresets(.satb)[3]

    return [
      ScoreTrackSyntax(name: "Bass", presetFilename: bassPreset, numVoices: 2, octave: 2, voicing: .closed, sustainFraction: 0.9, notes: bassNotes),
      ScoreTrackSyntax(name: "Tenor", presetFilename: tenorPreset, numVoices: 2, octave: 3, voicing: .closed, sustainFraction: 0.85, notes: tenorNotes),
      ScoreTrackSyntax(name: "Alto", presetFilename: altoPreset, numVoices: 2, octave: 4, voicing: .closed, sustainFraction: 0.85, notes: altoNotes),
      ScoreTrackSyntax(name: "Soprano", presetFilename: sopPreset, numVoices: 2, octave: 5, voicing: .closed, sustainFraction: 0.8, notes: sopranoNotes)
    ]
  }

  // MARK: - Helpers

  /// Append a sequence of setRoman chord events, replacing the initial setChord.
  private static func appendRomanSequence(
    _ romans: [String], bpc: Double, startBeat: Double,
    to events: inout [ChordEventSyntax], openingDegrees: [Int]
  ) {
    // Replace the setChord at beat 0 with a setRoman for the first chord
    events.removeAll { $0.beat == 0 }
    for (i, roman) in romans.enumerated() {
      events.append(ChordEventSyntax(beat: startBeat + bpc * Double(i), op: "setRoman", roman: roman))
    }
  }

  private static func appendKeyShift(at beat: Double, root: String, scale: String, to events: inout [ChordEventSyntax]) {
    events.append(ChordEventSyntax(beat: beat, op: "setKey", root: root, scale: scale))
  }

  /// How many distinct chord events does this motion produce?
  private static func motionChordCount(_ motion: GeneratorMotion, scaleSize: Int) -> Int {
    switch motion {
    case .drone:              return 4   // 4 repeats of the same chord
    case .shuttle, .plagal:   return 2
    case .fourChords, .twoLoop, .descendingThirds: return 4
    case .oneLoop:            return 3
    case .descendingFifths:   return 8
    case .randomWalk:         return 8
    case .shepardDescent:     return scaleSize  // one full scale rotation
    case .parallelAscending, .parallelDescending, .parallelRandom: return scaleSize
    case .acousticBridge:     return 20  // 4 sections × 5 chords each
    case .octatonicImmersion: return 16  // diatonic(4) + octatonic(8) + diatonic(4)
    }
  }

  private static func scaleSize(_ type: GeneratorScaleType) -> Int {
    switch type {
    case .wholeTone:                    return 6
    case .hexatonic:                    return 6
    case .pentatonicMajor, .pentatonicMinor: return 5
    case .octatonic:                    return 8
    default:                            return 7
    }
  }

  private static func isMinorScale(_ type: GeneratorScaleType) -> Bool {
    switch type {
    case .naturalMinor, .harmonicMinor, .dorian, .phrygian: return true
    default: return false
    }
  }

  private static func defaultVoicing(_ texture: GeneratorTexture) -> VoicingStyle {
    switch texture {
    case .pad, .full:    return .open
    case .satb:          return .closed
    default:             return .closed
    }
  }

  static func defaultPresets(_ texture: GeneratorTexture) -> [String] {
    switch texture {
    case .pad:           return ["warm_analog_pad"]
    case .arpeggio:      return ["organ_baroque_positive"]
    case .melody:        return ["organ_baroque_positive"]
    case .bassAndMelody: return ["moog_sub_bass", "organ_baroque_positive"]
    case .full:          return ["moog_sub_bass", "warm_analog_pad", "organ_baroque_positive"]
    case .satb:          return ["moog_sub_bass", "solina_strings", "solina_strings", "solina_strings"]
    }
  }

  private static func resolvedPresets(_ params: GeneratorSyntax) -> [String] {
    if let names = params.presetNames, !names.isEmpty { return names }
    return defaultPresets(params.texture)
  }
}
