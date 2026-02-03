//
//  ArrowChart.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 1/25/26.
//

import Accelerate
import Charts
import SwiftUI

struct ArrowChart: View {
  struct Sample {
    var time: CoreFloat
    var amp: CoreFloat
  }
  
  var arrow: Arrow11
  @State private var numSamplesToPlot = 512
  let sampleRate = 44100
  var ymin: Int = -1
  var ymax: Int = 1
  var data: [Sample] {
    let now: CoreFloat = 0
    let dt: CoreFloat = 1.0 / CoreFloat(sampleRate)
    var times = [CoreFloat](repeating: 0, count: 512)
    var amps = [CoreFloat](repeating: 0, count: 512)
    vDSP.formRamp(withInitialValue: now, increment: dt, result: &times)
    // process will use times.count which is MAX_BUFFER_SIZE
    arrow.process(inputs: times, outputs: &amps)
    
    let plotCount = min(numSamplesToPlot, MAX_BUFFER_SIZE)
    return (0..<plotCount).map { i in
      return Sample(time: times[i], amp: amps[i])
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
  let arr = Sawtooth()
  arr.innerArr = ArrowProd(innerArrs: [ArrowConst(value: 300), ArrowIdentity()])
  return ArrowChart(arrow: arr, ymin: -1, ymax: 1)
}
