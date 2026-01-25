//
//  OscillatorChart.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/25/26.
//

import Charts
import SwiftUI

struct ArrowChart: View {
  struct Sample {
    var time: CoreFloat
    var amp: CoreFloat
  }
  
  var arrow: Arrow11
  var numSamplesToPlot = 200
  let sampleRate = 44100
  var data: [Sample] {
    return (0...numSamplesToPlot).map { i in
      let t = CoreFloat(i) / CoreFloat(sampleRate)
      return Sample(time: t, amp: arrow.of(t))
    }
  }
  
  var body: some View {
    Chart(data, id: \.time) { sample in
      LineMark(
        x: .value("Time", sample.time),
        y: .value("Amplitude", sample.amp)
      )
    }
    .chartXScale(domain: 0...Double(numSamplesToPlot)/Double(sampleRate))
    .chartYScale(domain: -1...1)
  }

}
