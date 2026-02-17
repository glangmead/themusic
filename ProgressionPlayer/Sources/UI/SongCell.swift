//
//  SongCell.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongCell: View {
    @Environment(SyntacticSynth.self) private var synth
    let song: Song

    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Error>? = nil
    @State private var musicPattern: MusicPattern? = nil
    @State private var patternSpatialPreset: SpatialPreset? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Play/Stop button
                Button {
                    if isPlaying {
                        stopPlayback()
                    } else {
                        startPlayback()
                    }
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(isPlaying ? Color.red : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Song name
                Text(song.name)
                    .font(.headline)

                Spacer()
            }

            HStack(spacing: 12) {
                // Pattern button (placeholder)
                Button {
                    // TODO: Pattern editor
                } label: {
                    Label("Pattern", systemImage: "waveform")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(true)

                // Presets button
                NavigationLink {
                    SongPresetListView(song: song)
                } label: {
                    Label("Presets", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                // Spatial button (placeholder)
                Button {
                    // TODO: Spatial editor
                } label: {
                    Label("Spatial", systemImage: "globe")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func startPlayback() {
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
            engine: synth.engine
        )
        musicPattern = pattern
        patternSpatialPreset = sp
        isPlaying = true
        playbackTask = Task.detached {
            await pattern.play()
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        patternSpatialPreset?.cleanup()
        patternSpatialPreset = nil
        musicPattern = nil
        isPlaying = false
    }
}
