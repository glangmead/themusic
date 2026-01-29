//
//  Player.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/21/26.
//

import Foundation
import Tonic
import AVFAudio

// This layer doesn't know about synths or sequencers, only the Sequence protocol and Arrow* classes.
// The client of MusicPattern would own concepts like beats and absolute time.
// Our job here is to own an arrow that has generators in some of its slots, and then instantiate those.

// a musical utterance to play at one point in time, a set of simultaneous noteOns
struct MusicEvent {
  // could the PoolVoice wrapping these presets be sent in, and with modulation already provided?
  var presets: [Preset]
  let notes: [MidiNote]
  let sustain: CoreFloat // time between noteOn and noteOff in seconds
  let gap: CoreFloat // time reserved for this event, before next event is played
  let modulators: [String: Arrow11]
  let timeOrigin: Double
  var cleanup: (() async -> Void)? = nil
  
  private(set) var voice: PoolVoice? = nil
  
  mutating func play() async throws {
    // wrap my designated presets (sound+FX generators) in a PoolVoice
    let noteHandlers = presets.map { EnvelopeHandlePlayer(arrow: $0.sound) }
    self.voice = PoolVoice(voices: noteHandlers)
    
    // Apply modulation
    let now = CoreFloat(Date.now.timeIntervalSince1970 - timeOrigin)
    for (key, modulatingArrow) in modulators {
      if voice!.namedConsts[key] != nil {
        for arrowConst in voice!.namedConsts[key]! {
          arrowConst.val = modulatingArrow.of(now)
        }
      }
      for preset in presets {
        preset.positionLFO?.phase = CoreFloat.random(in: 0...(2.0 * .pi))
      }
    }

    notes.forEach {
      //print("pattern note on, ostensibly for \(sustain) seconds")
      voice?.noteOn($0) }
    do {
      try await Task.sleep(for: .seconds(TimeInterval(sustain)))
    } catch {
      
    }
    notes.forEach {
      //print("pattern note off")
      voice?.noteOff($0)
    }
    if let cleanup = cleanup {
      await cleanup()
    }
    self.voice = nil
  }
  
  mutating func cancel() async {
    notes.forEach { voice?.noteOff($0) }
    if let cleanup = cleanup {
      await cleanup()
    }
    self.voice = nil
  }
}

struct ListSampler<Element>: Sequence, IteratorProtocol {
  let items: [Element]
  init(_ items: [Element]) {
    self.items = items
  }
  func next() -> Element? {
    items.randomElement()
  }
}

struct ScaleSampler: Sequence, IteratorProtocol {
  typealias Element = [MidiNote]
  var scale: Scale

  init(scale: Scale = Scale.aeolian) {
    self.scale = scale
  }

  func next() -> [MidiNote]? {
    return [MidiNote(
      note: MidiValue(Note.A.shiftUp(scale.intervals.randomElement()!)!.noteNumber),
      velocity: (50...127).randomElement()!
    )]
  }
}

enum ProbabilityDistribution {
  case uniform
  case gaussian(avg: CoreFloat, stdev: CoreFloat)
}

struct FloatSampler: Sequence, IteratorProtocol {
  typealias Element = CoreFloat
  let distribution: ProbabilityDistribution
  let min: CoreFloat
  let max: CoreFloat
  init(min: CoreFloat, max: CoreFloat, dist: ProbabilityDistribution = .uniform) {
    self.distribution = dist
    self.min = min
    self.max = max
  }

  func next() -> CoreFloat? {
    CoreFloat.random(in: min...max)
  }
}

// the ingredients for generating music events
actor MusicPattern {
  var presetSpec: PresetSyntax
  var engine: SpatialAudioEngine
  var modulators: [String: Arrow11] // modulates constants in the preset
  var notes: any IteratorProtocol<[MidiNote]> // a sequence of chords
  var sustains: any IteratorProtocol<CoreFloat> // a sequence of sustain lengths
  var gaps: any IteratorProtocol<CoreFloat> // a sequence of sustain lengths
  var timeOrigin: Double
  
  private var presetPool = [Preset]()
  private let poolSize = 40

  deinit {
    for preset in presetPool {
      preset.detachAppleNodes(from: engine)
    }
  }

  init(
    presetSpec: PresetSyntax,
    engine: SpatialAudioEngine,
    modulators: [String : Arrow11],
    notes: any IteratorProtocol<[MidiNote]>,
    sustains: any IteratorProtocol<CoreFloat>,
    gaps: any IteratorProtocol<CoreFloat>
  ){
    self.presetSpec = presetSpec
    self.engine = engine
    self.modulators = modulators
    self.notes = notes
    self.sustains = sustains
    self.gaps = gaps
    self.timeOrigin = Date.now.timeIntervalSince1970
    
    // Initialize pool
    var avNodes = [AVAudioMixerNode]()
    for _ in 0..<poolSize {
      let preset = presetSpec.compile()
      presetPool.append(preset)
      let node = preset.wrapInAppleNodes(forEngine: engine)
      avNodes.append(node)
    }
    engine.connectToEnvNode(avNodes)
  }
  
  func leasePresets(count: Int) -> [Preset] {
    var leased = [Preset]()
    let toTake = min(count, presetPool.count)
    if toTake > 0 {
      leased.append(contentsOf: presetPool.suffix(toTake))
      presetPool.removeLast(toTake)
    }
    return leased
  }
  
  func returnPresets(_ presets: [Preset]) {
    presetPool.append(contentsOf: presets)
  }
  
  func next() async -> MusicEvent? {
    guard let notes = notes.next() else { return nil }
    guard let sustain = sustains.next() else { return nil }
    guard let gap = gaps.next() else { return nil }
    
    let presets = leasePresets(count: notes.count)
    if presets.isEmpty {
      print("Warning: MusicPattern starved for voices")
      return nil 
    }
    
    return MusicEvent(
      presets: presets,
      notes: notes,
      sustain: sustain,
      gap: gap,
      modulators: modulators,
      timeOrigin: timeOrigin,
      cleanup: { [weak self] in
        await self?.returnPresets(presets)
      }
    )
  }
  
  func play() async {
    await withTaskGroup(of: Void.self) { group in
      while !Task.isCancelled {
        guard var event = await next() else { return }
        group.addTask {
          try? await event.play()
        }
        do {
          try await Task.sleep(for: .seconds(TimeInterval(event.gap)))
        } catch {
          return
        }
      }
    }
  }
}
