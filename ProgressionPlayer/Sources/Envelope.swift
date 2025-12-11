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
    case decay
  }
  var env: EnvelopeData {
    didSet {
      setFunctionsFromEnvelopeSpecs()
    }
  }
  var timeOrigin: CoreFloat = 0
  var attackEnv: PiecewiseFunc<CoreFloat> = PiecewiseFunc<CoreFloat>(ifuncs: [])
  var decayEnv: PiecewiseFunc<CoreFloat> = PiecewiseFunc<CoreFloat>(ifuncs: [])
  var state: EnvelopeState = .closed
  
  init(envelope e: EnvelopeData) {
    self.env = e
    super.init()
    self.setFunctionsFromEnvelopeSpecs()
  }
  
  override func of(_ ime: CoreFloat) -> CoreFloat {
    switch state {
    case .closed:
      return 0
    case .attack:
      return attackEnv.val(CoreFloat(Date.now.timeIntervalSince1970) - timeOrigin)
    case .decay:
      let time = CoreFloat(Date.now.timeIntervalSince1970) - timeOrigin
      if time > env.decayTime {
        state = .closed
        return 0
      } else {
        return decayEnv.val(time)
      }
    }
  }
  
  func setFunctionsFromEnvelopeSpecs() {
    attackEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: self.env.attackTime),
        f: { self.env.scale * $0 / self.env.attackTime }
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
    decayEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: self.env.releaseTime),
        f: {self.env.scale * ($0 * -1.0 * (self.env.sustainLevel / self.env.releaseTime) + self.env.sustainLevel)})
    ])
  }
  
  func noteOn(_ note: MidiNote) {
    timeOrigin = CoreFloat(Date.now.timeIntervalSince1970)
    state = .attack
  }
  
  func noteOff(_ note: MidiNote) {
    timeOrigin = CoreFloat(Date.now.timeIntervalSince1970)
    state = .decay
  }
}

