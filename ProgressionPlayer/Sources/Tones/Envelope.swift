//
//  ADSREnvelope.swift
//  ProgressionPlayer
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
  var timeOrigin: CoreFloat = 0
  var attackEnv: PiecewiseFunc<CoreFloat> = PiecewiseFunc<CoreFloat>(ifuncs: [])
  var releaseEnv: PiecewiseFunc<CoreFloat> = PiecewiseFunc<CoreFloat>(ifuncs: [])
  var state: EnvelopeState = .closed
  var previousValue: CoreFloat = 0
  var valueAtRelease: CoreFloat = 0
  var valueAtAttack: CoreFloat = 0

  init(envelope e: EnvelopeData) {
    self.env = e
    super.init()
    self.setFunctionsFromEnvelopeSpecs()
  }
  
  override func of(_ ime: CoreFloat) -> CoreFloat {
    var val: CoreFloat = 0
    switch state {
    case .closed:
      val = 0
    case .attack:
      val = attackEnv.val(CoreFloat(Date.now.timeIntervalSince1970) - timeOrigin)
    case .release:
      let time = CoreFloat(Date.now.timeIntervalSince1970) - timeOrigin
      if time > env.releaseTime {
        state = .closed
        val = 0
      } else {
        val = releaseEnv.val(time)
      }
    }
    previousValue = val
    return val
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
    timeOrigin = CoreFloat(Date.now.timeIntervalSince1970)
    valueAtAttack = previousValue
    state = .attack
  }
  
  func noteOff(_ note: MidiNote) {
    timeOrigin = CoreFloat(Date.now.timeIntervalSince1970)
    valueAtRelease = previousValue
    state = .release
  }
}

