//
//  GeneratorEngine.swift
//  Orbital
//
//  Converts a GeneratorSyntax into a ScorePatternSyntax using Tymoczko's
//  chorale model: L-power progressions on the diatonic spiral, OUCH-driven
//  upper-voice spacing, constraint-based voice-leading solver.
//
//  Output: ScorePatternSyntax with one bass track + N upper-voice tracks
//  (N = 2/3/4 matching chord type). Each note in each track is an absolute
//  MIDI pitch — the voicer has already committed to concrete voicings.
//

import Foundation
import Tonic

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
    let seed = params.randomSeed ?? SongRNG.int(in: 0...Int.max)
    var rng = SeededRNG(seed: seed)

    let chordDegrees = params.chordType.degrees
    let chordCount = motionChordCount(params.motion, params: params)
    let totalBeats = params.beatsPerChord * Double(chordCount)

    let chordEvents = buildChordEvents(
      params, chordDegrees: chordDegrees, chordCount: chordCount, rng: &rng
    )
    let tracks = buildTracks(
      params, chordEvents: chordEvents, chordCount: chordCount,
      totalBeats: totalBeats, rng: &rng
    )

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

    case .drone:
      break

    case .shuttle:
      let romans = isMinorScale(params.scaleType) ? ["i", "V"] : ["I", "V"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

    case .plagal:
      let romans = isMinorScale(params.scaleType) ? ["i", "iv"] : ["I", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

    case .fourChords:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "III", "VII"] : ["I", "V", "vi", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

    case .oneLoop:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "iv"] : ["I", "V", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

    case .twoLoop:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "VI", "iv"] : ["I", "bVII", "bVI", "IV"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

    case .descendingThirds:
      let romans = isMinorScale(params.scaleType) ? ["i", "VI", "iv", "ii"] : ["I", "vi", "IV", "ii"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

    case .descendingFifths:
      let romans = isMinorScale(params.scaleType)
        ? ["i", "iv", "VII", "III", "VI", "ii", "V", "i"]
        : ["I", "IV", "vii", "iii", "vi", "ii", "V", "I"]
      appendRomanSequence(romans, bpc: bpc, startBeat: 0, to: &events)

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

    case .acousticBridge:
      let diatonicKey = params.rootNote
      let diatonicScale = params.scaleType.tonicScaleName
      let acousticScale = GeneratorScaleType.acoustic.tonicScaleName
      let wholeToneScale = GeneratorScaleType.wholeTone.tonicScaleName

      appendKeyShift(at: bpc * 4, root: diatonicKey, scale: acousticScale, to: &events)
      appendKeyShift(at: bpc * 8, root: diatonicKey, scale: wholeToneScale, to: &events)
      appendKeyShift(at: bpc * 12, root: diatonicKey, scale: acousticScale, to: &events)
      appendKeyShift(at: bpc * 16, root: diatonicKey, scale: diatonicScale, to: &events)
      for i in 1..<chordCount {
        events.append(ChordEventSyntax(beat: bpc * Double(i), op: "T", n: 1))
      }

    case .octatonicImmersion:
      let diatonicKey = params.rootNote
      let diatonicScale = params.scaleType.tonicScaleName
      let octatonicScale = GeneratorScaleType.octatonic.tonicScaleName

      appendKeyShift(at: bpc * 4, root: diatonicKey, scale: octatonicScale, to: &events)
      appendKeyShift(at: bpc * 12, root: diatonicKey, scale: diatonicScale, to: &events)
      for i in 1..<chordCount {
        events.append(ChordEventSyntax(beat: bpc * Double(i), op: "T", n: 1))
      }

    case .tPowers:
      // Each element is one T(n) — n scale steps, applied cumulatively.
      let sequence = params.tPowerSequence ?? [1]
      var beat = bpc
      for power in sequence where power != 0 {
        events.append(ChordEventSyntax(beat: beat, op: "T", n: power))
        beat += bpc
      }

    case .ttPowers:
      // Each element is one TT(n) — n semitones, applied cumulatively.
      let sequence = params.ttPowerSequence ?? [2]
      var beat = bpc
      for power in sequence where power != 0 {
        events.append(ChordEventSyntax(beat: beat, op: "TT", n: power))
        beat += bpc
      }
    }

    return events.sorted { $0.beat < $1.beat }
  }

  // MARK: - Tracks

  // swiftlint:disable:next function_body_length
  private static func buildTracks(
    _ params: GeneratorSyntax,
    chordEvents: [ChordEventSyntax],
    chordCount: Int,
    totalBeats: Double,
    rng: inout SeededRNG
  ) -> [ScoreTrackSyntax] {
    let bpc = params.beatsPerChord
    let chordSize = params.chordType.degrees.count

    // Build harmony timeline to query (key, chord) at each beat.
    let initialKey = resolveKey(root: params.rootNote, scale: params.scaleType.tonicScaleName)
    let timelineEvents = chordEvents.map { HarmonyTimeline.Event(beat: $0.beat, op: $0) }
    let timeline = HarmonyTimeline(
      totalBeats: totalBeats,
      initialKey: initialKey,
      events: timelineEvents
    )

    let lowMidi = (params.upperVoiceLowOctave + 1) * 12
    let highMidi = (params.upperVoiceHighOctave + 1) * 12 + 11
    var constraints = VoicingConstraints.default
    constraints.upperVoiceRange = lowMidi...highMidi
    let voicer = ChoraleVoicer(constraints: constraints)

    var ouchState = OUCHState(current: .closed)
    var previousUpper: [Int] = []
    var previousBass: Int = 0

    var bassMidis: [Int] = []
    var upperMidis: [[Int]] = Array(repeating: [], count: chordSize)

    for i in 0..<chordCount {
      let beat = bpc * Double(i)
      let (key, chord) = timeline.state(at: beat, loop: false)
      let hierarchy = PitchHierarchy(key: key, chord: chord)

      let bassMidi = computeBassMidi(hierarchy: hierarchy, octave: params.bassOctave)
      let chordPCs = chordPitchClasses(hierarchy: hierarchy)
      let scaleRootPC = Int(key.root.canonicalNote.noteNumber) % 12

      let target: OUCHConfiguration? = (chordSize == 3) ? ouchState.step(using: &rng) : nil

      let newUpper = voicer.voice(
        previousUpper: previousUpper,
        previousBass: previousBass,
        nextChordPCs: chordPCs,
        nextBass: bassMidi,
        upperVoiceCount: chordSize,
        targetConfiguration: target,
        scaleRootPC: scaleRootPC
      )

      bassMidis.append(bassMidi)
      for (idx, pitch) in newUpper.enumerated() where idx < chordSize {
        upperMidis[idx].append(pitch)
      }
      previousUpper = newUpper
      previousBass = bassMidi
    }

    // Assemble tracks. nil presetFilename → random pad with GM-driven constraints.
    let bassPreset = params.bassPresetName              // nil → random pad
    let upperPresets = params.upperPresetNames          // nil → random pads
    let upperNames = upperVoiceNames(chordSize)

    var tracks: [ScoreTrackSyntax] = []
    let bassNotes = bassMidis.map {
      ScoreNoteSyntax(type: .absolute, durationBeats: bpc, midi: $0)
    }
    tracks.append(ScoreTrackSyntax(
      name: "Bass",
      presetFilename: bassPreset,
      numVoices: 2,
      octave: params.bassOctave,
      voicing: .closed,
      sustainFraction: 0.9,
      gmProgram: bassGmProgram,                          // 33 = electric bass
      notes: bassNotes
    ))

    for (i, name) in upperNames.enumerated() {
      let preset = (upperPresets != nil && i < upperPresets!.count) ? upperPresets![i] : nil
      let notes = upperMidis[i].map {
        ScoreNoteSyntax(type: .absolute, durationBeats: bpc, midi: $0)
      }
      tracks.append(ScoreTrackSyntax(
        name: name,
        presetFilename: preset,
        numVoices: 2,
        octave: params.upperVoiceLowOctave,
        voicing: .closed,
        sustainFraction: 0.85,
        gmProgram: upperVoiceGmProgram,                  // 89 = warm pad
        notes: notes
      ))
    }
    return tracks
  }

  // GM program defaults: bass family (32–39) carries noDetune/subOctaveSine
  // constraints; synth pad family (88–95) gets slow attacks and soft filters.
  private static let bassGmProgram = 33                  // Electric Bass (finger)
  private static let upperVoiceGmProgram = 89            // Warm Pad

  // MARK: - Helpers

  /// Compute pitch classes directly from chord degrees + scale + chromatic
  /// perturbations. Octave-independent and immune to degree drift.
  private static func chordPitchClasses(hierarchy: PitchHierarchy) -> [Int] {
    let intervals = hierarchy.key.scale.intervals
    let scaleSize = intervals.count
    guard scaleSize > 0 else { return [] }
    let rootPC = Int(hierarchy.key.root.canonicalNote.noteNumber) % 12
    let perturbs = hierarchy.chord.perturbations
    return hierarchy.chord.degrees.enumerated().map { idx, degree in
      let normDegree = ((degree % scaleSize) + scaleSize) % scaleSize
      let semitones = intervals[normDegree].semitones
      var pc = rootPC + semitones
      if let perturbs, idx < perturbs.count, case .chromatic(let delta) = perturbs[idx] {
        pc += delta
      }
      return ((pc % 12) + 12) % 12
    }
  }

  /// Compute bass MIDI from the chord's abstract root (degrees[0]) and the
  /// configured bass octave. We compute the *pitch class* — accounting for the
  /// scale interval and any chromatic perturbation — then place it inside the
  /// bass octave. Without the mod-12 step, repeated TT(n) shifts would push
  /// the bass MIDI value upward indefinitely.
  private static func computeBassMidi(hierarchy: PitchHierarchy, octave: Int) -> Int {
    guard let bassDegree = hierarchy.chord.degrees.first else {
      return (octave + 1) * 12
    }
    let intervals = hierarchy.key.scale.intervals
    let scaleSize = intervals.count
    guard scaleSize > 0 else { return (octave + 1) * 12 }
    let rootPC = Int(hierarchy.key.root.canonicalNote.noteNumber) % 12
    let normDegree = ((bassDegree % scaleSize) + scaleSize) % scaleSize
    let semitones = intervals[normDegree].semitones
    var pc = rootPC + semitones
    if let perturbs = hierarchy.chord.perturbations, let first = perturbs.first,
       case .chromatic(let delta) = first {
      pc += delta
    }
    pc = ((pc % 12) + 12) % 12
    let midi = (octave + 1) * 12 + pc
    return max(0, min(127, midi))
  }

  private static func resolveKey(root: String, scale: String) -> Key {
    let noteClass = NoteGeneratorSyntax.resolveNoteClass(root)
    let scaleValue = NoteGeneratorSyntax.resolveScale(scale)
    return Key(root: noteClass, scale: scaleValue)
  }

  private static func appendRomanSequence(
    _ romans: [String], bpc: Double, startBeat: Double,
    to events: inout [ChordEventSyntax]
  ) {
    events.removeAll { $0.beat == 0 }
    for (i, roman) in romans.enumerated() {
      events.append(ChordEventSyntax(
        beat: startBeat + bpc * Double(i), op: "setRoman", roman: roman
      ))
    }
  }

  private static func appendKeyShift(at beat: Double, root: String, scale: String, to events: inout [ChordEventSyntax]) {
    events.append(ChordEventSyntax(beat: beat, op: "setKey", root: root, scale: scale))
  }

  /// How many chord events this motion produces.
  private static func motionChordCount(_ motion: GeneratorMotion, params: GeneratorSyntax) -> Int {
    switch motion {
    case .drone:              return 4
    case .shuttle, .plagal:   return 2
    case .fourChords, .twoLoop, .descendingThirds: return 4
    case .oneLoop:            return 3
    case .descendingFifths:   return 8
    case .randomWalk:         return 8
    case .shepardDescent:     return scaleSize(params.scaleType)
    case .parallelAscending, .parallelDescending, .parallelRandom:
      return scaleSize(params.scaleType)
    case .acousticBridge:     return 20
    case .octatonicImmersion: return 16
    case .tPowers:
      let seq = params.tPowerSequence ?? [1]
      let nonZero = seq.filter { $0 != 0 }.count
      return max(1, nonZero + 1)
    case .ttPowers:
      let seq = params.ttPowerSequence ?? [2]
      let nonZero = seq.filter { $0 != 0 }.count
      return max(1, nonZero + 1)
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

  private static func upperVoiceNames(_ chordSize: Int) -> [String] {
    switch chordSize {
    case 2: return ["Tenor", "Soprano"]
    case 3: return ["Tenor", "Alto", "Soprano"]
    case 4: return ["Tenor", "Alto", "Mezzo", "Soprano"]
    default: return (0..<chordSize).map { "Voice \($0)" }
    }
  }

}
