//
//  SpatialPreset.swift
//  Orbital
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
///
/// `@unchecked Sendable`: SpatialPreset is an `@Observable` class that owns
/// AVAudioEngine nodes, a VoiceLedger, and a pool of Presets. All mutating
/// access happens from the main actor (`SongDocument`, SwiftUI form views),
/// while playback reads go through its own `NoteHandler` methods which are
/// serialized by the sequencer's task. The position-pump `Task.detached`
/// only mutates AVAudioMixerNode positions, which is internally synchronized
/// by AVFoundation.
@Observable
class SpatialPreset: NoteHandler, @unchecked Sendable {
  private(set) var presetSpec: PresetSyntax
  let engine: SpatialAudioEngine?
  let numVoices: Int
  let resourceBaseURL: URL?
  private(set) var presets: [Preset] = []

  // Spatial voice management: routes notes to different Presets
  private var spatialLedger: VoiceLedger?
  private var _cachedHandles: ArrowWithHandles?

  // Single position-pump task per SpatialPreset (replaces the previous
  // per-Preset task; one task drives all 12 spatial slots).
  // Lives only while playback is active so it doesn't run during compile().
  private var positionPumpTask: Task<Void, Never>?

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
        _ = holder.withMergeDictsFromArrow(h)
      }
    }
    _cachedHandles = holder
    return holder
  }

  /// True if any inner Preset's voices contain random-consuming Arrow nodes,
  /// or if the originating PresetSyntax was constructed from a padTemplate
  /// (random pads have render-thread randomness even after compile).
  var hasArrowRandomness: Bool {
    if presetSpec.padTemplate != nil { return true }
    return presets.contains { $0.hasArrowRandomness }
  }

  /// Apply per-node random seeds to every preset's voice graphs.
  /// Call on the main actor before engine.start().
  func resetRandomSeeds(songSeed: UInt64) {
    for preset in presets {
      preset.resetRandomSeeds(songSeed: songSeed)
    }
  }

  init(presetSpec: PresetSyntax, engine: SpatialAudioEngine, numVoices: Int = 12, resourceBaseURL: URL? = nil) async throws {
    self.presetSpec = presetSpec
    self.engine = engine
    self.numVoices = numVoices
    self.resourceBaseURL = resourceBaseURL
    try await setup()
  }

  /// Create a UI-only SpatialPreset: builds Preset objects (with positionLFO, handles, etc.)
  /// but skips audio node creation and engine connection. Useful for previews and settings screens.
  init(presetSpec: PresetSyntax, numVoices: Int = 12) {
    self.presetSpec = presetSpec
    self.engine = nil
    self.numVoices = numVoices
    self.resourceBaseURL = nil
    setupForUI()
  }

  private func setup() async throws {
    guard let engine else { return }
    var avNodes = [AVAudioMixerNode]()
    _cachedHandles = nil

    if presetSpec.arrow != nil || presetSpec.padTemplate != nil || presetSpec.padSynth != nil {
      // Independent spatial: N Presets x 1 voice each
      // Each note goes to a different Preset (different spatial position)
      let phaseStep = CoreFloat(2 * Double.pi) / CoreFloat(numVoices)
      for i in 0..<numVoices {
        let preset = presetSpec.compile(numVoices: 1, resourceBaseURL: resourceBaseURL)
        preset.name = "\(preset.name)[\(i)]"
        // Spread voices evenly around the rose curve
        preset.positionLFO?.phase += phaseStep * CoreFloat(i)
        presets.append(preset)
        let node = try await preset.wrapInAppleNodes(forEngine: engine)
        avNodes.append(node)
      }
    } else if presetSpec.samplerFilenames != nil {
      // Sampler: 1 sampler per spatial slot, same as Arrow
      let phaseStep = CoreFloat(2 * Double.pi) / CoreFloat(numVoices)
      for i in 0..<numVoices {
        let preset = presetSpec.compile(numVoices: 1, resourceBaseURL: resourceBaseURL)
        // Spread voices evenly around the rose curve
        preset.positionLFO?.phase += phaseStep * CoreFloat(i)
        presets.append(preset)
        let node = try await preset.wrapInAppleNodes(forEngine: engine)
        avNodes.append(node)
      }
    }

    spatialLedger = VoiceLedger(voiceCount: numVoices)

    // Register each inner Preset's ampEnv envelopes with the spatial ledger
    // so it can auto-release voices when the envelope release completes.
    for (i, preset) in presets.enumerated() {
      if let sound = preset.sound, let ampEnvs = sound.namedADSREnvelopes["ampEnv"] {
        spatialLedger?.registerEnvelopes(forVoice: i, envelopes: ampEnvs)
      }
    }

    engine.connectToEnvNode(avNodes)
  }

  /// Build Preset objects for UI display only — no audio nodes, no engine connection.
  private func setupForUI() {
    _cachedHandles = nil

    let phaseStep = CoreFloat(2 * Double.pi) / CoreFloat(numVoices)
    // Create a single Preset (enough for UI to read positionLFO, presetSpec, handles)
    let preset = presetSpec.compile(numVoices: 1, initEffects: false)
    preset.positionLFO?.phase += phaseStep * 0
    presets.append(preset)
  }

  /// Detach audio nodes from the engine but keep the Preset objects
  /// (and their positionLFO values) alive for UI access.
  func detachNodes() {
    stopPositionPump()
    if let engine {
      for preset in presets {
        preset.detachAppleNodes(from: engine)
      }
    }
    spatialLedger = nil
  }

  func cleanup() {
    detachNodes()
    presets.removeAll()
    _cachedHandles = nil
  }

  /// Start the single per-SpatialPreset position pump. The pump loops at the
  /// throttle rate, calling `setPosition` on every internal Preset; idle slots
  /// (no active note) short-circuit cheaply inside `setPosition`. Marked
  /// `.medium` priority deliberately to throttle CPU/thermal load from the
  /// HRTF recompute that each `mixerNode.position =` triggers; the audio
  /// render thread runs at real-time priority and is unaffected by this.
  /// Detached so structured-concurrency priority escalation can't lift it.
  func startPositionPump() {
    stopPositionPump()
    let presetsRef = presets
    positionPumpTask = Task.detached(priority: .medium) {
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(25))
        } catch {
          return
        }
        let now = Date.now.timeIntervalSince1970
        for preset in presetsRef {
          preset.setPosition(CoreFloat(now - preset.timeOrigin))
        }
      }
    }
  }

  func stopPositionPump() {
    positionPumpTask?.cancel()
    positionPumpTask = nil
  }

  func reload(presetSpec: PresetSyntax? = nil) {
    cleanup()
    if let presetSpec { self.presetSpec = presetSpec }
    Task { try? await setup() }
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

    if let idx = ledger.beginRelease(noteVelIn.note) {
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

  /// Play notes and apply modulators only to the allocated voice for each note.
  func notesOnWithModulators(_ notes: [MidiNote], modulators: [String: Arrow11], now: CoreFloat) {
    guard let ledger = spatialLedger else { return }
    for note in notes {
      let idx: Int?
      if let existing = ledger.voiceIndex(for: note.note) {
        idx = existing
      } else {
        idx = ledger.takeAvailableVoice(note.note)
      }
      guard let voiceIdx = idx else { continue }
      // Apply modulators to just this voice's handles
      if let voiceHandles = presets[voiceIdx].handles {
        for (key, modulatingArrow) in modulators {
          if let arrowConsts = voiceHandles.namedConsts[key] {
            let value = modulatingArrow.of(now)
            for arrowConst in arrowConsts {
              arrowConst.val = value
            }
          }
        }
      }
      presets[voiceIdx].noteOn(note)
    }
  }

  func notesOff(_ notes: [MidiNote]) {
    for note in notes {
      noteOff(note)
    }
  }

  /// Immediately silence all currently sounding notes.
  func allNotesOff() {
    guard let ledger = spatialLedger else { return }
    let activeNotes = ledger.noteToVoiceIdx.keys
    for note in activeNotes {
      noteOff(MidiNote(note: note, velocity: 0))
    }
  }

  // MARK: - Preset access

  func forEachPreset(_ body: (Preset) -> Void) {
    presets.forEach(body)
  }
}
