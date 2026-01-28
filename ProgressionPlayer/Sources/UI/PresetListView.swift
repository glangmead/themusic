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
  
  @State private var presets: [URL] = []
  
  var body: some View {
    VStack {
      Text("Select a preset file to load.")
        .font(.headline)
        .padding()
      
      List(presets, id: \.self) { url in
        Button(url.deletingPathExtension().lastPathComponent) {
          loadPreset(url)
          isPresented = false
        }
      }
      .onAppear {
        loadPresets()
      }
      
      Button("Cancel") {
        isPresented = false
      }
      .padding()
    }
  }
  
  private func loadPresets() {
    // Try to find presets in the "presets" subdirectory
    if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "presets") {
      presets = urls
    } else {
      // Fallback: look for specific known presets if subdirectory fails (e.g. if flattened)
      // or try to find all JSONs (might be risky)
      // Let's try finding all JSONs and filtering by known structure or name if possible.
      // For now, listing all JSONs in root might include other things.
      // But based on the file list, they are in a folder. If flattened, they are in root.
      if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
         // Filter out non-preset files if needed. For now, show all.
         // Common non-preset files might be 'Assets.json' (inside assets), but Bundle.main.urls usually doesn't recurse into .xcassets
         presets = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
      }
    }
  }
  
  private func loadPreset(_ url: URL) {
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let presetSpec = try decoder.decode(PresetSyntax.self, from: data)
      
      // Update the synth
      synth.loadPreset(presetSpec)
      
    } catch {
      print("Error loading preset: \(error.localizedDescription)")
    }
  }
}

#Preview {
  PresetListView(isPresented: .constant(true))
}
