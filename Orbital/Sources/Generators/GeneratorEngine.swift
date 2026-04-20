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

// swiftlint:disable:next type_body_length
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
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

    case .plagal:
      let romans = isMinorScale(params.scaleType) ? ["i", "iv"] : ["I", "IV"]
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

    case .fourChords:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "III", "VII"] : ["I", "V", "vi", "IV"]
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

    case .oneLoop:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "iv"] : ["I", "V", "IV"]
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

    case .twoLoop:
      let romans = isMinorScale(params.scaleType) ? ["i", "VII", "VI", "iv"] : ["I", "bVII", "bVI", "IV"]
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

    case .descendingThirds:
      let romans = isMinorScale(params.scaleType) ? ["i", "VI", "iv", "ii"] : ["I", "vi", "IV", "ii"]
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

    case .descendingFifths:
      let romans = isMinorScale(params.scaleType)
        ? ["i", "iv", "VII", "III", "VI", "ii", "V", "i"]
        : ["I", "IV", "vii", "iii", "vi", "ii", "V", "I"]
      appendRomanSequence(romans, chordType: params.chordType, bpc: bpc, startBeat: 0, to: &events)

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
    let upperPreset = params.upperPresetNames?.first    // single shared preset across upper voices

    // Per-track velocity: one draw used for every note on the track.
    let bassVelocity = rng.nextInt(in: bassVelocityRange)

    var tracks: [ScoreTrackSyntax] = []
    let bassNotes = bassMidis.map {
      ScoreNoteSyntax(type: .absolute, durationBeats: bpc, midi: $0, velocity: bassVelocity)
    }
    tracks.append(ScoreTrackSyntax(
      name: "Bass",
      presetFilename: bassPreset,
      numVoices: 2,
      octave: params.bassOctave,
      voicing: .closed,
      sustainFraction: 1.0,
      gmProgram: bassGmProgram,                          // 33 = electric bass
      notes: bassNotes
    ))

    // One upper-voice track: all chord tones share the same preset/instrument
    // but fan out across spatial slots via SpatialPreset's per-note voice ledger.
    let upperVoicesVelocity = rng.nextInt(in: upperVoiceVelocityRange)
    var upperNotes: [ScoreNoteSyntax] = []
    for i in 0..<chordCount {
      let midis = (0..<chordSize).map { upperMidis[$0][i] }
      upperNotes.append(ScoreNoteSyntax(
        type: .absoluteChord,
        durationBeats: bpc,
        midis: midis,
        velocity: upperVoicesVelocity
      ))
    }
    tracks.append(ScoreTrackSyntax(
      name: "Upper Voices",
      presetFilename: upperPreset,
      numVoices: nil,                                    // default 12 spatial slots
      octave: params.upperVoiceLowOctave,
      voicing: .closed,
      sustainFraction: 1.0,
      gmProgram: upperVoiceGmProgram,                    // 89 = warm pad
      notes: upperNotes
    ))

    if let melodyTrack = buildMelodyTrack(
      params, chordSize: chordSize, chordCount: chordCount,
      timeline: timeline, bpc: bpc, rng: &rng
    ) {
      tracks.append(melodyTrack)
    }
    return tracks
  }

  // MARK: - Melody

  // Build an optional melody track for `params.melody`. Returns nil for
  // `.none` or when the melody doesn't apply to the current chord size.
  // swiftlint:disable:next function_parameter_count
  private static func buildMelodyTrack(
    _ params: GeneratorSyntax,
    chordSize: Int,
    chordCount: Int,
    timeline: HarmonyTimeline,
    bpc: Double,
    rng: inout SeededRNG
  ) -> ScoreTrackSyntax? {
    switch params.melody ?? .none {
    case .none:
      return nil
    case .pluckedArpeggio:
      return buildPluckedArpeggioTrack(
        chordSize: chordSize, chordCount: chordCount,
        timeline: timeline, bpc: bpc, rng: &rng
      )
    }
  }

  /// Fractional onset times inside each chord window for the plucked arpeggio,
  /// keyed by chord size. 2/3/4 chord tones map to 2/3/4 equally or
  /// user-specified fractional positions summing well inside [0, 1].
  private static func arpeggioFractions(chordSize: Int) -> [Double] {
    switch chordSize {
    case 2: return [0.3, 0.6]
    case 3: return [0.25, 0.5, 0.75]
    case 4: return [0.2, 0.4, 0.6, 0.8]
    default: return []
    }
  }

  private static func buildPluckedArpeggioTrack(
    chordSize: Int, chordCount: Int,
    timeline: HarmonyTimeline, bpc: Double,
    rng: inout SeededRNG
  ) -> ScoreTrackSyntax? {
    let fractions = arpeggioFractions(chordSize: chordSize)
    guard !fractions.isEmpty else { return nil }

    let arpeggioOctave = 4
    let melodyVelocity = rng.nextInt(in: melodyVelocityRange)
    var notes: [ScoreNoteSyntax] = []

    for i in 0..<chordCount {
      let beat = bpc * Double(i)
      let (key, chord) = timeline.state(at: beat, loop: false)
      let hierarchy = PitchHierarchy(key: key, chord: chord)
      let midis = arpeggioMidis(hierarchy: hierarchy, octave: arpeggioOctave)
      guard !midis.isEmpty else { continue }

      // Initial rest from chord onset to the first arp attack.
      let firstFraction = fractions[0]
      if firstFraction > 0 {
        notes.append(ScoreNoteSyntax(type: .rest, durationBeats: firstFraction * bpc))
      }
      // Emit each arp note with onset-to-onset duration equal to the gap to
      // the next fraction (or to 1.0 for the last note).
      for (j, fraction) in fractions.enumerated() {
        let nextFraction: Double = (j + 1 < fractions.count) ? fractions[j + 1] : 1.0
        let duration = (nextFraction - fraction) * bpc
        let midi = midis[min(j, midis.count - 1)]
        notes.append(ScoreNoteSyntax(
          type: .absolute, durationBeats: duration, midi: midi, velocity: melodyVelocity
        ))
      }
    }

    return ScoreTrackSyntax(
      name: "Arpeggio",
      presetFilename: nil,                                // → random pad with piano constraints
      numVoices: 2,
      octave: arpeggioOctave,
      voicing: .closed,
      sustainFraction: 1.0,
      gmProgram: arpeggioPianoGmProgram,                  // 0 = acoustic grand
      pluckedOrStruck: true,                              // fast attack, short decay, narrow chorus, slight stretch
      notes: notes
    )
  }

  /// Non-inverted chord-tone MIDI values in the given octave, ascending.
  /// Octave-bumps any successive pitch that would otherwise fall at or below
  /// its predecessor, so scale-wrap chord degrees (e.g. T-powers past the
  /// octave) still produce a monotonic arpeggio.
  private static func arpeggioMidis(hierarchy: PitchHierarchy, octave: Int) -> [Int] {
    let intervals = hierarchy.key.scale.intervals
    let scaleSize = intervals.count
    guard scaleSize > 0 else { return [] }
    let rootPC = Int(hierarchy.key.root.canonicalNote.noteNumber) % 12
    let baseMidi = (octave + 1) * 12
    let perturbs = hierarchy.chord.perturbations
    var lastMidi = Int.min
    var result: [Int] = []
    for (idx, degree) in hierarchy.chord.degrees.enumerated() {
      let normDegree = ((degree % scaleSize) + scaleSize) % scaleSize
      var semitones = intervals[normDegree].semitones
      if let perturbs, idx < perturbs.count, case .chromatic(let delta) = perturbs[idx] {
        semitones += delta
      }
      var midi = baseMidi + rootPC + semitones
      while midi <= lastMidi { midi += 12 }
      lastMidi = midi
      result.append(max(0, min(127, midi)))
    }
    return result
  }

  // GM program defaults: bass family (32–39) carries noDetune/subOctaveSine
  // constraints; synth pad family (88–95) gets slow attacks and soft filters;
  // piano family (0–7) carries the plucked/struck constraint bundle.
  private static let bassGmProgram = 33                  // Electric Bass (finger)
  private static let upperVoiceGmProgram = 89            // Warm Pad
  private static let arpeggioPianoGmProgram = 0          // Acoustic Grand

  // Per-track MIDI velocity ranges. Each track draws ONE velocity at
  // generation time (via SeededRNG.nextInt) and uses it for every note.
  private static let bassVelocityRange: ClosedRange<Int> = 70...85
  private static let upperVoiceVelocityRange: ClosedRange<Int> = 50...70
  private static let melodyVelocityRange: ClosedRange<Int> = 90...110

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

  /// Figured-bass suffix that turns a plain Roman numeral into a chord of the
  /// given size. Empty for triad (the parser's default). "7" for seventh.
  /// Dyads have no standard figured-bass suffix; left empty until we teach
  /// the parser about "5" (power-chord) notation.
  private static func figuredBassSuffix(for chordType: GeneratorChordType) -> String {
    switch chordType {
    case .seventh: return "7"
    case .triad, .dyad: return ""
    }
  }

  private static func appendRomanSequence(
    _ romans: [String], chordType: GeneratorChordType,
    bpc: Double, startBeat: Double,
    to events: inout [ChordEventSyntax]
  ) {
    events.removeAll { $0.beat == 0 }
    let suffix = figuredBassSuffix(for: chordType)
    for (i, roman) in romans.enumerated() {
      events.append(ChordEventSyntax(
        beat: startBeat + bpc * Double(i), op: "setRoman", roman: roman + suffix
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

}
