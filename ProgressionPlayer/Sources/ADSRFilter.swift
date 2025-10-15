//
//  ADSREnvelope.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/14/25.
//

//
//  ADSRFilter.swift
//  Harmonicity
//
//  Created by Sergey on 29.05.2025.
//

import Foundation
import Overture

typealias CoreFloat = Double

struct EnvelopeData {
  var attackTime: CoreFloat = 0.2
  var decayTime: CoreFloat = 0.5
  var sustainLevel: CoreFloat = 0.3
  var releaseTime: CoreFloat = 1.0
}

class ADSR: NoteHandler, SampleProcessor {
  var timeOrigin: CoreFloat = 0
  var attackEnv = PiecewiseFunc<CoreFloat>(ifuncs: [IntervalFunc<CoreFloat>(interval: Interval<CoreFloat>(start: nil, end: nil), f: {_ in 1})])
  var decayEnv = PiecewiseFunc<CoreFloat>(ifuncs: [IntervalFunc<CoreFloat>(interval: Interval<CoreFloat>(start: nil, end: nil), f: {_ in 1})])
  var attack = true
  
  init(envelope e: EnvelopeData) {
    attackEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: e.attackTime),
        f: { $0 / e.attackTime }),
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: e.attackTime, end: e.attackTime + e.decayTime),
        f: { ($0 * ((e.sustainLevel - 1.0)/(e.decayTime))) + (1.0 + (e.attackTime) * ((1.0 - e.sustainLevel)/(e.decayTime)))}),
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: e.attackTime + e.decayTime, end: nil),
        f: {_ in e.sustainLevel})
    ])
    decayEnv = PiecewiseFunc<CoreFloat>(ifuncs: [
      IntervalFunc<CoreFloat>(
        interval: Interval<CoreFloat>(start: 0, end: e.releaseTime),
        f: {$0 * -1.0 * (e.sustainLevel / e.releaseTime) + e.sustainLevel})
    ])
  }
  
  func process(_ sample: CoreFloat, time: Double) -> CoreFloat {
    return sample * (attack ? attackEnv.val(Date.now.timeIntervalSince1970 - timeOrigin) : decayEnv.val(Date.now.timeIntervalSince1970 - timeOrigin))
  }
  
  func noteOn(_ note: MidiNote) {
    timeOrigin = Date.now.timeIntervalSince1970
    attack = true
  }
  
  func noteOff(_ note: MidiNote) {
    timeOrigin = Date.now.timeIntervalSince1970
    attack = false
  }
}

