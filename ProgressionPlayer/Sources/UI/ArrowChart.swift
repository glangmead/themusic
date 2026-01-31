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
  @State private var numSamplesToPlot = 200
  let sampleRate = 44100
  var ymin: Int = -1
  var ymax: Int = 1
  var data: [Sample] {
    let now: CoreFloat = 0
    let dt: CoreFloat = 1.0 / CoreFloat(sampleRate)
    return (0...numSamplesToPlot).map { i in
      let t = now + (CoreFloat(i) * dt)
      return Sample(time: t, amp: arrow.of(now + t))
    }
  }
  
  var body: some View {
    GroupBox("Oscillator 1") {
      Chart(data, id: \.time) { sample in
        LineMark(
          x: .value("Time", sample.time),
          y: .value("Amplitude", sample.amp)
        )
      }
      .chartXScale(domain: 0...Double(numSamplesToPlot)/Double(sampleRate))
      .chartYScale(domain: ymin...ymax)
      
      TextField("Samples", value: $numSamplesToPlot, format: .number)
        .textFieldStyle(.roundedBorder)
        .padding()
    }
  }
}

#Preview {
  let arr = LowPassFilter2(cutoff: ArrowConst(value: 70000.0), resonance: ArrowConst(value: 1.1))
  arr.innerArr = ArrowImpulse(fireTime: 2.0/44100.0)
  return ArrowChart(arrow: arr, ymin: -1, ymax: 1)
}
