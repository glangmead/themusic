//
//  OrbitalView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/17/26.
//

import SwiftUI

struct OrbitalView: View {
    @Environment(SyntacticSynth.self) private var synth
    @Environment(SongLibrary.self) private var library

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
                    ForEach(library.songs) { song in
                        SongCell(song: song)
                    }
                }
                .padding()
            }
            .navigationTitle("Orbital")
        }
    }
}
