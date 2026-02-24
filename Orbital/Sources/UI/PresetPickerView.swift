//
//  PresetPickerView.swift
//  Orbital
//
//  Created by Greg Langmead on 2/18/26.
//

import SwiftUI

/// Lists all available presets with a checkmark on the current one.
/// Tapping a preset replaces the track's preset and pops the navigation stack.
struct PresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SongDocument.self) private var playbackState
    let trackId: Int
    let currentPresetName: String

    private var presets: [PresetOption] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "presets") ?? []
        return urls.compactMap { url -> PresetOption? in
            let fileName = url.lastPathComponent
            let spec = Bundle.main.decode(PresetSyntax.self, from: fileName, subdirectory: "presets")
            return PresetOption(fileName: fileName, spec: spec)
        }.sorted { $0.spec.name < $1.spec.name }
    }

    var body: some View {
        List(presets) { preset in
            Button {
                playbackState.replacePreset(trackId: trackId, newPresetSpec: preset.spec)
                dismiss()
            } label: {
                HStack {
                    Text(preset.spec.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if preset.spec.name == currentPresetName {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle("Choose Preset")
    }
}

private struct PresetOption: Identifiable {
    var id: String { fileName }
    let fileName: String
    let spec: PresetSyntax
}
