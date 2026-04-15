//
//  ScorePatternCompiler.swift
//  Orbital
//
//  Compiles a ScorePatternSyntax into a MusicPattern.
//
//  Steps:
//  1. Build a HarmonyTimeline from the chord events.
//  2. For each track, walk the note list:
//     a. Merge hold notes into the preceding note's sustain.
//     b. Resolve each note's pitch against the harmony at its absolute beat.
//     c. Build parallel (chords, sustains, gaps) arrays in seconds.
//  3. Create looping or one-shot iterators over those arrays.
//  4. Assemble MusicPattern.Track instances and return a CompileResult.
//

import Foundation
import Tonic

// MARK: - ScorePatternCompiler

enum ScorePatternCompiler {

    // MARK: - Public Entry Points

    /// Compile a ScorePatternSyntax into a full MusicPattern with audio nodes.
    static func compile(
        _ score: ScorePatternSyntax,
        engine: SpatialAudioEngine,
        clock: any Clock<Duration> = ContinuousClock(),
        resourceBaseURL: URL? = nil,
        songSeed: UInt64? = nil
    ) async throws -> PatternSyntax.CompileResult {
        let loopVal = score.loop ?? true
        let secondsPerBeat = 60.0 / score.bpm
        let timeline = buildTimeline(score)

        // Build beat-indexed chord labels for the UI chord label stream.
        let labelEvents: [(beat: Double, label: String)] = score.chordEvents
            .sorted { $0.beat < $1.beat }
            .compactMap { event in
                guard let label = HarmonyTimeline.formatLabel(for: event) else { return nil }
                return (beat: event.beat, label: label)
            }

        var musicTracks: [MusicPattern.Track] = []
        var trackInfos: [TrackInfo] = []
        var spatialPresets: [SpatialPreset] = []

        for (i, trackSyntax) in score.tracks.enumerated() {
            let (chords, sustains, gaps) = compileTrack(
                trackSyntax,
                timeline: timeline,
                secondsPerBeat: secondsPerBeat,
                loop: loopVal
            )
            let characteristicDuration = medianSustain(sustains)
            let presetSpec = resolvePresetSpec(
                filename: trackSyntax.presetFilename,
                gmProgram: trackSyntax.gmProgram,
                characteristicDuration: characteristicDuration,
                resourceBaseURL: resourceBaseURL
            )
            let voices = trackSyntax.numVoices ?? 12
            let sp = try await SpatialPreset(
                presetSpec: presetSpec,
                engine: engine,
                numVoices: voices,
                resourceBaseURL: resourceBaseURL
            )

            let iters = makeIterators(chords: chords, sustains: sustains, gaps: gaps, loop: loopVal)

            musicTracks.append(MusicPattern.Track(
                spatialPreset: sp,
                modulators: [:],
                notes: iters.notes,
                sustains: iters.sustains,
                gaps: iters.gaps,
                name: trackSyntax.name,
                emitterShadows: [:]
            ))
            trackInfos.append(TrackInfo(id: i, patternName: trackSyntax.name, presetSpec: presetSpec))
            spatialPresets.append(sp)
        }

        let pattern = MusicPattern(
            tracks: musicTracks,
            chordLabelEvents: labelEvents,
            secondsPerBeat: secondsPerBeat,
            totalBeats: score.totalBeats,
            loop: loopVal,
            clock: clock,
            songSeed: songSeed
        )
        return PatternSyntax.CompileResult(
            pattern: pattern,
            trackInfos: trackInfos,
            spatialPresets: spatialPresets
        )
    }

    /// Compile for UI-only display — no audio engine required.
    static func compileTrackInfoOnly(
        _ score: ScorePatternSyntax,
        resourceBaseURL: URL? = nil
    ) -> [TrackInfo] {
        let secondsPerBeat = 60.0 / score.bpm
        let timeline = buildTimeline(score)
        let loopVal = score.loop ?? true
        return score.tracks.enumerated().map { (i, trackSyntax) in
            let (_, sustains, _) = compileTrack(
                trackSyntax, timeline: timeline,
                secondsPerBeat: secondsPerBeat, loop: loopVal
            )
            let presetSpec = resolvePresetSpec(
                filename: trackSyntax.presetFilename,
                gmProgram: trackSyntax.gmProgram,
                characteristicDuration: medianSustain(sustains),
                resourceBaseURL: resourceBaseURL
            )
            return TrackInfo(id: i, patternName: trackSyntax.name, presetSpec: presetSpec)
        }
    }

    /// Median of nonzero sustains, in seconds. nil when the track has no sounding notes.
    private static func medianSustain(_ sustains: [CoreFloat]) -> CoreFloat? {
        let active = sustains.filter { $0 > 0 }.sorted()
        guard !active.isEmpty else { return nil }
        let mid = active.count / 2
        return active.count.isMultiple(of: 2)
            ? (active[mid - 1] + active[mid]) / 2
            : active[mid]
    }

    // MARK: - Timeline Construction

    /// Build a HarmonyTimeline from the ScorePatternSyntax chord events.
    static func buildTimeline(_ score: ScorePatternSyntax) -> HarmonyTimeline {
        let root = NoteGeneratorSyntax.resolveNoteClass(score.key.root)
        let scale = NoteGeneratorSyntax.resolveScale(score.key.scale)
        let initialKey = Key(root: root, scale: scale)

        let sorted = score.chordEvents.sorted { $0.beat < $1.beat }
        let events = sorted.map { HarmonyTimeline.Event(beat: $0.beat, op: $0) }

        return HarmonyTimeline(totalBeats: score.totalBeats, initialKey: initialKey, events: events)
    }

    // MARK: - Track Compilation

    /// Compile a single track into parallel (chords, sustains, gaps) arrays.
    ///
    /// Hold notes are merged into the preceding note's sustain time rather than
    /// generating a new attack event. Orphaned holds (no preceding note) produce
    /// a silent rest instead.
    static func compileTrack(
        _ track: ScoreTrackSyntax,
        timeline: HarmonyTimeline,
        secondsPerBeat: Double,
        loop: Bool
    ) -> (chords: [[MidiNote]], sustains: [CoreFloat], gaps: [CoreFloat]) {
        let sustainFraction = track.sustainFraction ?? 0.85
        let defaultVoicing = track.voicing ?? .closed

        var chords: [[MidiNote]] = []
        var sustains: [CoreFloat] = []
        var gaps: [CoreFloat] = []

        var beat = 0.0
        var i = 0
        let notes = track.notes

        while i < notes.count {
            let spec = notes[i]

            switch spec.type {
            case .rest:
                // Emit a silent event and advance the beat cursor.
                chords.append([])
                sustains.append(0)
                gaps.append(CoreFloat(spec.durationBeats * secondsPerBeat))
                beat += spec.durationBeats
                i += 1

            case .hold:
                // Orphaned hold: no preceding note to extend, treat as rest.
                chords.append([])
                sustains.append(0)
                gaps.append(CoreFloat(spec.durationBeats * secondsPerBeat))
                beat += spec.durationBeats
                i += 1

            default:
                // Regular note: scan forward for trailing holds, summing their durations.
                var totalDuration = spec.durationBeats
                var j = i + 1
                while j < notes.count && notes[j].type == .hold {
                    totalDuration += notes[j].durationBeats
                    j += 1
                }

                // Resolve pitch against the harmony timeline at this absolute beat.
                let (key, chord) = timeline.state(at: beat, loop: loop)
                let hierarchy = PitchHierarchy(key: key, chord: chord)
                let octave = spec.octave ?? track.octave
                let voicing = spec.voicing ?? defaultVoicing
                let vel = UInt8(min(127, max(0, spec.velocity ?? 80)))
                let midiNotes = resolveNote(
                    spec,
                    hierarchy: hierarchy,
                    octave: octave,
                    voicing: voicing,
                    velocity: vel
                )

                chords.append(midiNotes)
                sustains.append(CoreFloat(totalDuration * secondsPerBeat * sustainFraction))
                gaps.append(CoreFloat(totalDuration * secondsPerBeat))
                beat += totalDuration
                i = j
            }
        }

        return (chords, sustains, gaps)
    }

    // MARK: - Note Resolution

    /// Resolve a ScoreNoteSyntax to concrete MIDI notes given the current hierarchy.
    static func resolveNote(
        _ spec: ScoreNoteSyntax,
        hierarchy: PitchHierarchy,
        octave: Int,
        voicing: VoicingStyle,
        velocity: UInt8
    ) -> [MidiNote] {
        switch spec.type {
        case .rest, .hold:
            return []

        case .currentChord:
            let v = spec.voicing ?? voicing
            return hierarchy.voicedMidi(voicing: v, baseOctave: octave)
                .map { MidiNote(note: $0, velocity: velocity) }

        case .chordTone:
            let idx = spec.index ?? 0
            let oct = spec.octave ?? octave
            let voiced = hierarchy.chord.voicedDegrees
            let count = voiced.count
            guard count > 0 else { return [] }
            // Positive indices ≥ chord size wrap upward by one octave per wrap.
            // Negative indices wrap downward: -1 = top tone of octave below, -count = root below.
            let octaveShift = idx < 0 ? (idx + 1) / count - 1 : idx / count
            let wrappedIdx = ((idx % count) + count) % count
            let melNote = MelodyNote(chordToneIndex: wrappedIdx, perturbation: .none)
            if let midi = hierarchy.resolve(melNote, at: .chord, octave: oct + octaveShift) {
                return [MidiNote(note: midi, velocity: velocity)]
            }
            return []

        case .scaleDegree:
            let deg = spec.degree ?? 0
            let oct = spec.octave ?? octave
            let melNote = MelodyNote(chordToneIndex: deg, perturbation: .none)
            if let midi = hierarchy.resolve(melNote, at: .scale, octave: oct) {
                return [MidiNote(note: midi, velocity: velocity)]
            }
            return []

        case .absolute:
            if let midiVal = spec.midi {
                guard midiVal >= 0 && midiVal <= 127 else { return [] }
                return [MidiNote(note: UInt8(midiVal), velocity: velocity)]
            }
            if let noteName = spec.note, let midi = parseNoteName(noteName) {
                return [MidiNote(note: midi, velocity: velocity)]
            }
            return []

        case .absoluteChord:
            guard let midis = spec.midis else { return [] }
            return midis.compactMap { midiVal in
                guard midiVal >= 0 && midiVal <= 127 else { return nil }
                return MidiNote(note: UInt8(midiVal), velocity: velocity)
            }
        }
    }

    // MARK: - Iterator Assembly

    private static func makeIterators(
        chords: [[MidiNote]],
        sustains: [CoreFloat],
        gaps: [CoreFloat],
        loop: Bool
    ) -> (
        notes: any IteratorProtocol<[MidiNote]>,
        sustains: any IteratorProtocol<CoreFloat>,
        gaps: any IteratorProtocol<CoreFloat>
    ) {
        if loop {
            return (chords.cyclicIterator(), sustains.cyclicIterator(), gaps.cyclicIterator())
        } else {
            return (chords.makeIterator(), sustains.makeIterator(), gaps.makeIterator())
        }
    }

    // MARK: - Note Name Parsing

    /// Parse a note name like "C4", "Bb3", "F#5", "D5" to a MIDI number.
    ///
    /// Format: [A-G] [b|#]* [octave as Int]
    /// Examples: "C4" → 60, "Bb3" → 58, "F#5" → 78
    static func parseNoteName(_ name: String) -> UInt8? {
        var idx = name.startIndex

        // Must start with a letter (the note name A–G).
        guard idx < name.endIndex, name[idx].isLetter else { return nil }
        idx = name.index(after: idx)

        // Consume any accidental characters (b = flat, # = sharp).
        while idx < name.endIndex && (name[idx] == "b" || name[idx] == "#") {
            idx = name.index(after: idx)
        }

        let notePart = String(name[name.startIndex..<idx])
        let octavePart = String(name[idx...])
        guard let octave = Int(octavePart) else { return nil }

        let nc = NoteGeneratorSyntax.resolveNoteClass(notePart)
        // rootPC is the pitch class (0–11); MIDI formula matches PitchHierarchy.resolve
        let rootPC = Int(nc.canonicalNote.noteNumber) % 12
        let midi = rootPC + (octave + 1) * 12
        guard midi >= 0 && midi <= 127 else { return nil }
        return UInt8(midi)
    }
}
