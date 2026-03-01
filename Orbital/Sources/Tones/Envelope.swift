//
//  ADSREnvelope.swift
//  Orbital
//
//  Created by Greg Langmead on 10/14/25.
//

import Foundation

struct EnvelopeData {
  var attackTime: CoreFloat = 0.2
  var decayTime: CoreFloat = 0.5
  var sustainLevel: CoreFloat = 0.3
  var releaseTime: CoreFloat = 1.0
  var scale: CoreFloat = 1.0
}

/// An envelope is an arrow with more of a sense of absolute time. It has a beginning, evolution, and ending.
/// Hence it is also a NoteHandler, so we can tell it when to begin to attack, and when to begin to decay.
/// Within that concept, ADSR is a specific family of functions. This is a linear one.
class ADSR: Arrow11, NoteHandler {
  var globalOffset: Int = 0
  enum EnvelopeState {
    case closed
    case attack
    case release
  }
  var env: EnvelopeData {
    didSet {
      setFunctionsFromEnvelopeSpecs()
    }
  }
  var newAttack = false
  var newRelease = false
  var timeOrigin: CoreFloat = 0
  var attackEnv: PiecewiseFunc<CoreFloat> = PiecewiseFunc<CoreFloat>(ifuncs: [])
  var releaseEnv: PiecewiseFunc<CoreFloat> = PiecewiseFunc<CoreFloat>(ifuncs: [])
  var state: EnvelopeState = .closed
  var previousValue: CoreFloat = 0
  var valueAtRelease: CoreFloat = 0
  var valueAtAttack: CoreFloat = 0
  var startCallback: (() -> Void)?
  /// Callbacks fired when the release phase completes and the envelope
  /// closes. Multiple listeners (audio gate lifecycle, voice ledger
  /// recycling, etc.) can each append a callback.
  var finishCallbacks: [() -> Void] = []

  init(envelope e: EnvelopeData) {
    self.env = e
    super.init()
    self.setFunctionsFromEnvelopeSpecs()
  }

  func env(_ time: CoreFloat) -> CoreFloat {
    if newAttack || newRelease {
      timeOrigin = time
      newAttack = false
      newRelease = false
    }
    var val: CoreFloat = 0
    switch state {
    case .closed:
      val = 0
    case .attack:
      val = attackEnv.val(time - timeOrigin)
    case .release:
      let time = time - timeOrigin
      if time > env.releaseTime {
        state = .closed
        val = 0
        let callbacks = finishCallbacks
        finishCallbacks = []
        for cb in callbacks { cb() }
      } else {
        val = releaseEnv.val(time)
      }
    }
    previousValue = val
    return val
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    inputs.withUnsafeBufferPointer { inBuf in
      outputs.withUnsafeMutableBufferPointer { outBuf in
        guard let inBase = inBuf.baseAddress,
              let outBase = outBuf.baseAddress else { return }
        for i in 0..<inputs.count {
          outBase[i] = self.env(inBase[i])
        }
      }
    }
  }

  func setFunctionsFromEnvelopeSpecs() {
    attackEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: self.env.attackTime),
        f: { self.valueAtAttack + ((self.env.scale - self.valueAtAttack) * $0 / self.env.attackTime) }
      ),
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: self.env.attackTime, end: self.env.attackTime + self.env.decayTime),
        f: { self.env.scale * ( ((self.env.sustainLevel - 1.0)/self.env.decayTime) * ($0 - self.env.attackTime) + 1.0 ) }
      ),
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: self.env.attackTime + self.env.decayTime, end: nil),
        f: {_ in self.env.scale * self.env.sustainLevel}
      )
    ])
    releaseEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: self.env.releaseTime),
        f: {
          self.valueAtRelease + ($0 * -1.0 * (self.valueAtRelease / self.env.releaseTime))
        })
    ])
  }

  func noteOn(_ note: MidiNote) {
    newAttack = true
    valueAtAttack = previousValue
    state = .attack
    startCallback?()
  }

  func noteOff(_ note: MidiNote) {
    newRelease = true
    valueAtRelease = previousValue
    state = .release
  }
}
