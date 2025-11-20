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
class ADSR: ControlArrow11, NoteHandler {
  var timeOrigin: CoreFloat = 0
  var attackEnv: PiecewiseFunc<CoreFloat>
  var decayEnv: PiecewiseFunc<CoreFloat>
  var attack = true
  
  init(envelope e: EnvelopeData) {
    attackEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: e.attackTime),
        f: { e.scale * $0 / e.attackTime }
      ),
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: e.attackTime, end: e.attackTime + e.decayTime),
        f: { e.scale * ( ((e.sustainLevel - 1.0)/e.decayTime) * ($0 - e.attackTime) + 1.0 ) }
      ),
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: e.attackTime + e.decayTime, end: nil),
        f: {_ in e.scale * e.sustainLevel}
      )
    ])
    decayEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: e.releaseTime),
        f: {e.scale * ($0 * -1.0 * (e.sustainLevel / e.releaseTime) + e.sustainLevel)})
    ])
    weak var futureSelf: ADSR? = nil
    super.init(of: Arrow11(of: { time in
      return (futureSelf!.attack ? futureSelf!.attackEnv.val(CoreFloat(Date.now.timeIntervalSince1970) - futureSelf!.timeOrigin) : futureSelf!.decayEnv.val(CoreFloat(Date.now.timeIntervalSince1970) - futureSelf!.timeOrigin))
    }))
    futureSelf = self
  }
  
  func noteOn(_ note: MidiNote) {
    timeOrigin = CoreFloat(Date.now.timeIntervalSince1970)
    attack = true
  }
  
  func noteOff(_ note: MidiNote) {
    timeOrigin = CoreFloat(Date.now.timeIntervalSince1970)
    attack = false
  }
}

