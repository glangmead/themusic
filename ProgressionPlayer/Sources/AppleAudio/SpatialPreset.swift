//
//  SpatialPreset.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 2/14/26.
//

import AVFAudio

/// A spatial pool of Presets that manages spatial positioning and chord-level note playback.
/// Each Preset in the pool has its own effects chain and spatial position, allowing notes
/// to fly around independently.
///
/// SpatialPreset is the "top-level playable thing" that Sequencer and MusicPattern
/// assign notes to. It conforms to NoteHandler and routes notes to individual Presets
/// via a spatial VoiceLedger.
///
/// For Arrow-based presets: each Preset has 1 internal voice. The SpatialPreset-level
/// ledger assigns each note to a different Preset (different spatial position).
/// For Sampler-based presets: each Preset wraps an AVAudioUnitSampler which is
/// inherently polyphonic.
@Observable
class SpatialPreset: NoteHandler {
  let presetSpec: PresetSyntax
  let engine: SpatialAudioEngine
  let numVoices: Int
  private(set) var presets: [Preset] = []
  
  // Spatial voice management: routes notes to different Presets
  private var spatialLedger: VoiceLedger?
  private var _cachedHandles: ArrowWithHandles?
  
  var globalOffset: Int = 0 {
    didSet {
      for preset in presets { preset.globalOffset = globalOffset }
    }
  }
  
  /// Aggregated handles from all Presets for parameter editing (UI knobs, modulation)
  var handles: ArrowWithHandles? {
    if let cached = _cachedHandles { return cached }
    guard !presets.isEmpty else { return nil }
    let holder = ArrowWithHandles(ArrowIdentity())
    for preset in presets {
      if let h = preset.handles {
        let _ = holder.withMergeDictsFromArrow(h)
      }
    }
    _cachedHandles = holder
    return holder
  }
  
  init(presetSpec: PresetSyntax, engine: SpatialAudioEngine, numVoices: Int = 12) {
    self.presetSpec = presetSpec
    self.engine = engine
    self.numVoices = numVoices
    setup()
  }
  
  private func setup() {
    var avNodes = [AVAudioMixerNode]()
    _cachedHandles = nil
    
    if presetSpec.arrow != nil {
      // Independent spatial: N Presets x 1 voice each
      // Each note goes to a different Preset (different spatial position)
      for i in 0..<numVoices {
        let preset = presetSpec.compile(numVoices: 1)
        preset.name = "\(preset.name)[\(i)]"
        presets.append(preset)
        let node = preset.wrapInAppleNodes(forEngine: engine)
        avNodes.append(node)
      }
    } else if presetSpec.samplerFilenames != nil {
      // Sampler: 1 sampler per spatial slot, same as Arrow
      for _ in 0..<numVoices {
        let preset = presetSpec.compile(numVoices: 1)
        presets.append(preset)
        let node = preset.wrapInAppleNodes(forEngine: engine)
        avNodes.append(node)
      }
    }
    
    spatialLedger = VoiceLedger(voiceCount: numVoices)
    engine.connectToEnvNode(avNodes)
  }
  
  func cleanup() {
    for preset in presets {
      preset.detachAppleNodes(from: engine)
    }
    presets.removeAll()
    spatialLedger = nil
    _cachedHandles = nil
  }
  
  func reload(presetSpec: PresetSyntax) {
    cleanup()
    setup()
  }
  
  // MARK: - NoteHandler
  
  func noteOn(_ noteVelIn: MidiNote) {
    guard let ledger = spatialLedger else { return }
    
    // Re-trigger if note already playing on a Preset
    if let idx = ledger.voiceIndex(for: noteVelIn.note) {
      presets[idx].noteOn(noteVelIn)
    }
    // Allocate a new Preset for this note
    else if let idx = ledger.takeAvailableVoice(noteVelIn.note) {
      presets[idx].noteOn(noteVelIn)
    }
  }
  
  func noteOff(_ noteVelIn: MidiNote) {
    guard let ledger = spatialLedger else { return }
    
    if let idx = ledger.releaseVoice(noteVelIn.note) {
      presets[idx].noteOff(noteVelIn)
    }
  }
  
  // MARK: - Chord API
  
  /// Play multiple notes simultaneously.
  /// - Parameters:
  ///   - notes: The notes to play.
  ///   - independentSpatial: If true, each note gets its own Preset (own FX chain + spatial position).
  ///     If false, notes share a Preset (move as a unit). Currently only independent mode is implemented.
  func notesOn(_ notes: [MidiNote], independentSpatial: Bool = true) {
    for note in notes {
      noteOn(note)
    }
  }
  
  func notesOff(_ notes: [MidiNote]) {
    for note in notes {
      noteOff(note)
    }
  }
  
  // MARK: - Preset access
  
  func forEachPreset(_ body: (Preset) -> Void) {
    presets.forEach(body)
  }
}
