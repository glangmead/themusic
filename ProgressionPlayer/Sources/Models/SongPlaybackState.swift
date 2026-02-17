//
//  SongPlaybackState.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import Foundation

/// Shared playback state for a song, passed through the Orbital navigation stack
/// so that drill-down views (preset list, preset editor) can show play/pause controls.
@MainActor @Observable
class SongPlaybackState {
    let song: Song
    let engine: SpatialAudioEngine

    private(set) var isPlaying = false
    private var playbackTask: Task<Void, Error>? = nil
    private var musicPattern: MusicPattern? = nil
    private var patternSpatialPreset: SpatialPreset? = nil

    init(song: Song, engine: SpatialAudioEngine) {
        self.song = song
        self.engine = engine
    }

    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    func play() {
        guard !isPlaying else { return }
        if !engine.audioEngine.isRunning {
            try! engine.start()
        }
        let patternSpec = Bundle.main.decode(
            PatternSyntax.self,
            from: song.patternFileName,
            subdirectory: "patterns"
        )
        let presetFileName = patternSpec.presetName + ".json"
        let presetSpec = Bundle.main.decode(
            PresetSyntax.self,
            from: presetFileName,
            subdirectory: "presets"
        )
        let (pattern, sp) = patternSpec.compile(
            presetSpec: presetSpec,
            engine: engine
        )
        musicPattern = pattern
        patternSpatialPreset = sp
        isPlaying = true
        playbackTask = Task.detached {
            await pattern.play()
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        patternSpatialPreset?.cleanup()
        patternSpatialPreset = nil
        musicPattern = nil
        isPlaying = false
    }
}
