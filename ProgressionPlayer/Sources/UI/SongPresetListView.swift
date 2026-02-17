//
//  SongPresetListView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct SongPresetListView: View {
    let song: Song

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
                PresetFormView(presetSpec: preset.spec)
            } label: {
                Text(preset.spec.name)
            }
        }
        .navigationTitle(song.name)
    }
}
