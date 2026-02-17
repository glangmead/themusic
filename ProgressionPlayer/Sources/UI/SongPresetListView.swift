//
//  SongPresetListView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongPresetListView: View {
    @Environment(SyntacticSynth.self) private var synth
    let song: Song
    @Bindable var playbackState: SongPlaybackState
    @State private var isShowingVisualizer = false

    struct PresetOption: Identifiable {
        var id: String { fileName }
        let fileName: String
        let spec: PresetSyntax
    }

    var presets: [PresetOption] {
        song.presetFileNames.map { fileName in
            let spec = Bundle.main.decode(
                PresetSyntax.self,
                from: fileName,
                subdirectory: "presets"
            )
            return PresetOption(fileName: fileName, spec: spec)
        }
    }

    var body: some View {
        List(presets) { preset in
            NavigationLink {
                PresetFormView(presetSpec: preset.spec, playbackState: playbackState)
            } label: {
                Text(preset.spec.name)
            }
        }
        .navigationTitle(song.name)
        .toolbar {
            ToolbarItem {
                Button {
                    playbackState.togglePlayback()
                } label: {
                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            ToolbarItem {
                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isShowingVisualizer = true
                    }
                } label: {
                    Label("Visualizer", systemImage: "sparkles.tv")
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingVisualizer) {
            VisualizerView(synth: synth, isPresented: $isShowingVisualizer)
                .ignoresSafeArea()
        }
    }
}
