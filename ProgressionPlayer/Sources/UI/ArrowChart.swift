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
  @State private var numSamplesToPlot = 600
  let sampleRate = 44100
  var data: [Sample] {
    let now = Date.now.timeIntervalSince1970
    return (0...numSamplesToPlot).map { i in
      let t = CoreFloat(i) / CoreFloat(sampleRate)
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
      .chartYScale(domain: -1...1)
      
      TextField("Samples", value: $numSamplesToPlot, format: .number)
        .textFieldStyle(.roundedBorder)
        .padding()
    }
  }
}

#Preview {
  let osc = ArrowSmoothStep(sampleFreq: 200)
  osc.innerArr = ArrowProd(innerArrs: [ArrowConst(value: 440), ArrowIdentity()])
  return ArrowChart(arrow: osc)
}
