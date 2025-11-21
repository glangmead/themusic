//
//  Arrow.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

import AVFAudio
import Overture
import SwiftUI

/// High-level architecture: [Instrument -> AVAudioUnitEffect_1 -> ... -> AVAudioUnitEffect_n -> AVAudioEnvironmentNode] => AVAudioEngine
///                               ^                 ^                             ^                         ^
///                             [LFO]             [LFO]                         [LFO]                     [LFO]
///
/// AVAudioSourceNode per _instrument_
///   - the render block callback for this obtains all the outputs of all oscillators of that instrument
///   - polyphony in this instrument
///   - envelopes
///   - tremolo
///   - filter envelopes
///   - chain of AVAudioUnitEffects
///   - AVAudioEnvironmentNode (the famous spatializer)
///   - The output node is the AVAudioEngine outputNode
///
/// The Instrument is an Arrow and is a static formula of
///   - the oscillator
///   - amplitude envelope
///   - frequency
///   - modulation of frequency
///   - no nontrivial mixing, we just sum these to obtain polyphony
///
/// AVAudioUnitEffect nodes need some way to be modulated by an LFO, or so I am saying.
///   - AVAudioUnitDelay
///       * delayTime, feedback, lowPassCutoff, wetDryMix
///   - AVAudioUnitDistortion
///       * loadFactoryPreset, preGain, wetDryMix
///   - AVAudioUnitEQ
///       * AVAudioUnitEQFilterParameters, bands, globalGain
///   - AVAudioUnitReverb
///       * loadFactoryPreset, wetDryMix
///   - AU plugins!
///
/// AVAudioEnvironmentNode
///   - position, listenerPosition, listenerAngularOrientation, listenerVectorOrientation,
///     distanceAttenuationParameters, reverbParameters, outputVolume, outputType, applicableRenderingAlgorithms,
///     isListenerHeadTrackingEnabled, nextAvailableInputBus
///
/// An LFO is a coupling of two arrows.
///   - arrow1 is a target to be modulated, e.g. a sin wave whose frequency we shall modulate
///   - arrow2 is an LFO without knowledge of where it's being plugged in
///   - in real time we can do a few things
///       * couple and uncouple (a binary change -- maybe the wire is there statically and we just set the coupling constant to 0)
///       * change arrow1's variables
///       * change arrow2's variables
///
/// What is an arrow?
///   - A collection of sub-arrows composed together statically
///   - A single arrow has exposed parameters that can be changed in real time
///   - So in fullness, and arrow is a wiring diagram (the static part) with a few knobs attached (the real-time part)
///   - Compile-time wires and runtime wires?
///
/// Something should be called a Patch aka Preset. This would be a complete polyphonic instrument including all effects and spatialization?
///
/// Possible next steps:
///   ✓ Polyphony from the sequencer with a single arrow
///   - make a few Patches
///   - get two Presets to move spatially differently
///   - stand up a Wavetable
///   ✓ get the list of chords going again

// This is Double because an AVAudioSourceNodeRenderBlock sends the input (time) as a Float64
typealias CoreFloat = Double

class Arrow10 {
  var of: (CoreFloat) -> ()
  init(of: @escaping (CoreFloat) -> ()) {
    self.of = of
  }

  func asControl() -> Arrow10 {
    return ControlArrow10(of: self)
  }
}

class Arrow11 {
  var of: (CoreFloat) -> CoreFloat
  init(of: @escaping (CoreFloat) -> CoreFloat) {
    self.of = of
  }
  
  func withSidecars(_ sidecars: [Arrow10]) -> Arrow11 {
    return arrowWithSidecars(arr: self, sidecars: sidecars)
  }

  func withSidecar(_ sidecar: Arrow10) -> Arrow11 {
    return withSidecars([sidecar])
  }

  func asControl() -> Arrow11 {
    return ControlArrow11(of: self)
  }
}

//protocol SampleSource {
//  func sample(at time: CoreFloat) -> CoreFloat
//}

class Arrow21 {
  var of: (CoreFloat, CoreFloat) -> CoreFloat
  init(of: @escaping (CoreFloat, CoreFloat) -> CoreFloat) {
    self.of = of
  }
}

class Arrow13 {
  var of: (CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat)
  init(of: @escaping (CoreFloat) -> (CoreFloat, CoreFloat, CoreFloat)) {
    self.of = of
  }
}

class Arrow12 {
  var of: (CoreFloat) -> (CoreFloat, CoreFloat)
  init(of: @escaping (CoreFloat) -> (CoreFloat, CoreFloat)) {
    self.of = of
  }
}

// An arrow that wraps an arrow and limits how often the arrow gets called with a new time
// The name comes from the paradigm that control signals like LFOs don't need to fire as often
// as audio data.
class ControlArrow11: Arrow11 {
  var lastTimeEmitted = 0.0
  var lastEmission = 0.0
  let timeBetweenEmissions = 441.0 / 44100.0
  init(of arrow: Arrow11) {
    weak var fself: ControlArrow11? = nil
    super.init(of: { t in
      if t - fself!.lastTimeEmitted >= fself!.timeBetweenEmissions {
        fself!.lastEmission = arrow.of(t)
        fself!.lastTimeEmitted = t
      }
      return fself!.lastEmission
    })
    fself = self
  }
}

class ControlArrow10: Arrow10 {
  var lastTimeEmitted = 0.0
  let timeBetweenEmissions = 4410.0 / 44100.0
  init(of arrow: Arrow10) {
    weak var fself: ControlArrow10? = nil
    super.init(of: { t in
      if t - fself!.lastTimeEmitted >= fself!.timeBetweenEmissions {
        arrow.of(t)
        fself!.lastTimeEmitted = t
      }
    })
    fself = self
  }
}

// given an arrow that converts time into some CoreFloat, use that output to set a key path on some object
class KeyPathModulationArrow<T>: Arrow10 {
  init(using: Arrow11, for object: T, keyPath: ReferenceWritableKeyPath<T, CoreFloat>) {
    super.init(of: { t in
      object[keyPath: keyPath] = using.of(t)
    })
  }
}

func arrowPlus(a: Arrow11, b: Arrow11) -> Arrow11 {
  return Arrow11(of: { a.of($0) + b.of($0) })
}

func arrowSum(_ arrows: [Arrow11]) -> Arrow11 {
  return Arrow11(of: { x in
    arrows.map({$0.of(x)}).reduce(0, +)
  } )
}

func arrowTimes(a: Arrow11, b: Arrow11) -> Arrow11 {
  return Arrow11(of: { a.of($0) * b.of($0) })
}

func arrowCompose(outer: Arrow11, inner: Arrow11) -> Arrow11 {
  return Arrow11(of: { outer.of(inner.of($0)) })
}

@Observable
class ArrowConst: Arrow11 {
  var val: CoreFloat
  init(_ val: CoreFloat) {
    self.val = val
    weak var fself: ArrowConst? = nil
    super.init(of: { _ in
      fself!.val
    })
    fself = self
  }
}

@Observable
class ArrowConstF: Arrow11 {
  var val: Float
  init(_ val: Float) {
    self.val = val
    weak var fself: ArrowConstF? = nil
    super.init(of: { _ in
      Double(fself!.val)
    })
    fself = self
  }
}

func arrowWithSidecars(arr: Arrow11, sidecars: [Arrow10]) -> Arrow11 {
  return Arrow11(of: { x in
    for sidecar in sidecars {
      sidecar.of(x)
    }
    return arr.of(x)
  })
}

