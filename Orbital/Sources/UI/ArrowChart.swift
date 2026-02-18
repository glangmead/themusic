//
//  ArrowChart.swift
//  Orbital
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
  @State private var numSamplesToPlot = 48000
  let sampleRate = 48000
  let now: CoreFloat = 600
  var ymin: Int = -1
  var ymax: Int = 1
  var data: [Sample] {
    var result = [Sample]()
    let dt: CoreFloat = 1.0 / CoreFloat(sampleRate)
    var times = [CoreFloat](repeating: 0, count: numSamplesToPlot)
    vDSP.formRamp(withInitialValue: now, increment: dt, result: &times)
    var numSamplesProcessedByArrow = 0
    while numSamplesProcessedByArrow < numSamplesToPlot {
      let start: Int = numSamplesProcessedByArrow
      let endPlusOne: Int = min(numSamplesToPlot, numSamplesProcessedByArrow + 512)
      let windowTimes = Array(times[start..<endPlusOne])
      var windowAmps = [CoreFloat](repeating: 0, count: 512)
      arrow.process(inputs: windowTimes, outputs: &windowAmps)
      for i in 0..<windowTimes.count {
        //if i % 100 == 0 {
        //  print("sample at time \(windowTimes[i]) is \(windowAmps[i])")
        //}
        result.append(Sample(time: windowTimes[i], amp: windowAmps[i]))
      }
      numSamplesProcessedByArrow += 512
    }
    return result
  }
  
  var body: some View {
    GroupBox("Oscillator 1") {
      Chart(data, id: \.time) { sample in
        LineMark(
          x: .value("Time", sample.time),
          y: .value("Amplitude", sample.amp)
        )
      }
      .chartXScale(domain: now...now+Double(numSamplesToPlot)/Double(sampleRate))
      .chartYScale(domain: ymin...ymax)
      
      TextField("Samples", value: $numSamplesToPlot, format: .number)
        .textFieldStyle(.roundedBorder)
        .padding()
    }
  }
}

#Preview {
  let arr = NoiseSmoothStep(noiseFreq: 5, min: 0, max: 1)
  arr.sampleRate = 44000
  //arr.innerArr = ArrowProd(innerArrs: [ArrowConst(value: 300), ArrowIdentity()])
  return ArrowChart(arrow: arr, ymin: -1, ymax: 1)
}
