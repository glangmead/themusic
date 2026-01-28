//
//  PresetListView.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/28/26.
//

import SwiftUI

struct PresetListView: View {
  @Environment(SyntacticSynth.self) private var synth
  @Binding var isPresented: Bool
  
  struct PresetOption: Identifiable {
    var id: String { fileName }
    let fileName: String
    let spec: PresetSyntax
  }

  var presets: [PresetOption] {
    let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "presets") ?? []
    return urls.compactMap { url -> PresetOption? in
      let fileName = url.lastPathComponent
      let spec = Bundle.main.decode(PresetSyntax.self, from: fileName, subdirectory: "presets")
      return PresetOption(fileName: fileName, spec: spec)
    }.sorted { $0.spec.name < $1.spec.name }
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Select a preset file to load.")
        .font(.headline)
        .padding()
      
      List(presets) { preset in
        Button(preset.spec.name) {
          synth.loadPreset(preset.spec)
          isPresented = false
        }
      }
    }
  }
}

#Preview {
  PresetListView(isPresented: .constant(true))
    .environment(SyntacticSynth(engine: SpatialAudioEngine(), presetSpec: Bundle.main.decode(PresetSyntax.self, from: "saw1_preset.json")))
}
