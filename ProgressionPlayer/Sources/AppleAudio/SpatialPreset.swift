//
//  SpatialPreset.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/14/26.
//

import AVFAudio

/// A polyphonic pool of Presets that manages voice allocation, spatial positioning,
/// and chord-level note playback. Each Preset in the pool has its own effects chain
/// and spatial position, allowing notes to fly around independently.
///
/// SpatialPreset is the "top-level playable thing" that Sequencer and MusicPattern
/// assign notes to.
@Observable
class SpatialPreset {
  let presetSpec: PresetSyntax
  let engine: SpatialAudioEngine
  let numVoices: Int
  private(set) var presets: [Preset] = []
  
  // Voice management: one of these will be populated depending on preset type
  var arrowPool: PolyphonicArrowPool?
  var samplerHandler: PlayableSampler?
  
  /// The NoteHandler for this SpatialPreset (arrow pool or sampler handler)
  var noteHandler: NoteHandler? { arrowPool ?? samplerHandler }
  
  /// Access to the ArrowWithHandles dictionaries for parameter editing (Arrow-based only)
  var handles: ArrowWithHandles? { arrowPool }
  
  init(presetSpec: PresetSyntax, engine: SpatialAudioEngine, numVoices: Int = 12) {
    self.presetSpec = presetSpec
    self.engine = engine
    self.numVoices = numVoices
    setup()
  }
  
  private func setup() {
    var avNodes = [AVAudioMixerNode]()
    
    if presetSpec.arrow != nil {
      for _ in 1...numVoices {
        let preset = presetSpec.compile()
        presets.append(preset)
        let node = preset.wrapInAppleNodes(forEngine: engine)
        avNodes.append(node)
      }
      engine.connectToEnvNode(avNodes)
      arrowPool = PolyphonicArrowPool(presets: presets)
    } else if presetSpec.samplerFilenames != nil {
      for _ in 1...numVoices {
        let preset = presetSpec.compile()
        presets.append(preset)
        let node = preset.wrapInAppleNodes(forEngine: engine)
        avNodes.append(node)
      }
      engine.connectToEnvNode(avNodes)
      
      let handler = PlayableSampler(sampler: presets[0].sampler!)
      handler.preset = presets[0]
      samplerHandler = handler
    }
  }
  
  func cleanup() {
    for preset in presets {
      preset.detachAppleNodes(from: engine)
    }
    presets.removeAll()
    arrowPool = nil
    samplerHandler = nil
  }
  
  func reload(presetSpec: PresetSyntax) {
    cleanup()
    // presetSpec is let, so we create a new SpatialPreset for reloading.
    // This method is here for future use if presetSpec becomes var.
    setup()
  }
  
  // MARK: - Single-note API
  
  func noteOn(_ note: MidiNote) {
    noteHandler?.noteOn(note)
  }
  
  func noteOff(_ note: MidiNote) {
    noteHandler?.noteOff(note)
  }
  
  // MARK: - Chord API
  
  /// Play multiple notes simultaneously.
  /// - Parameters:
  ///   - notes: The notes to play.
  ///   - independentSpatial: If true, each note gets its own Preset (own FX chain + spatial position).
  ///     If false, notes share a Preset (move as a unit). In both cases, the VoiceLedger in
  ///     PolyphonicArrowPool handles voice assignment, so each noteOn is tracked individually.
  func notesOn(_ notes: [MidiNote], independentSpatial: Bool = true) {
    // The independentSpatial parameter is naturally handled by the pool:
    // - For Arrow pools: each noteOn assigns a different voice (= different Preset)
    //   via VoiceLedger, so notes are already independent.
    // - For Sampler: AVAudioUnitSampler is inherently polyphonic.
    // When independentSpatial is false, a future optimization could route multiple
    // notes to the same voice/Preset, but for now each note is independent.
    for note in notes {
      noteHandler?.noteOn(note)
    }
  }
  
  func notesOff(_ notes: [MidiNote]) {
    for note in notes {
      noteHandler?.noteOff(note)
    }
  }
  
  // MARK: - Preset access
  
  func forEachPreset(_ body: (Preset) -> Void) {
    presets.forEach(body)
  }
}
