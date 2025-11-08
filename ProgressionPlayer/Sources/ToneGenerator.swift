//
//  Instrument.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 10/30/25.
//

import Foundation

/// This is a software instrument: a function that can be called to generate floats. Doesn't have effects.

// Factors of 2 * .pi are so as to have the wavelength be 1 and the frequency 1 Hz

let Sine = Arrow11(of: {
  sin(2 * .pi * fmod($0, 1.0))
})

let Triangle = Arrow11(of: { x in
  2 * (abs((2 * fmod(x, 1.0)) - 1.0) - 0.5)
})

let Sawtooth = Arrow11(of: { x in
  (2 * fmod(x, 1.0)) - 1.0
})

let Square = Arrow11(of: { x in
  fmod(x, 1) <= 0.5 ? 1.0 : -1.0
})

// see https://en.wikipedia.org/wiki/Rose_(mathematics)
func Rose(leafFactor k: Double, frequency freq: Double, startingPhase sp: Double) -> Arrow13 {
  Arrow13(of: { x in
    let domain = (freq * x) + sp
    return ( sin(k * domain) * cos(domain), 2 * sin(k * domain) * sin(domain), 2 * sin(domain) )
  })
}

protocol HasFactor {
  var factor: Double { get set }
  var arrow: Arrow11 { get set }
}

class PreMult: Arrow11, HasFactor {
  var factor: Double
  var arrow: Arrow11
  init(factor: Double, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    weak var futureSelf: PreMult? = nil
    super.init(of: { x in
      //print("\(futureSelf!.factor) \(x)")
      return futureSelf!.arrow.of(futureSelf!.factor * x)
    })
    futureSelf = self
  }
}

class PostMult: Arrow11, HasFactor {
  var factor: Double
  var arrow: Arrow11
  init(factor: Double, arrow: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    weak var fself: PostMult? = nil
    super.init(of: { x in
      return fself!.factor * fself!.arrow.of(x)
    })
    fself = self
  }
}

class ModulatedPreMult: Arrow11, HasFactor {
  var factor: Double
  var arrow: Arrow11
  var modulation: Arrow11
  init(factor: Double, arrow: Arrow11, modulation: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    self.modulation = modulation
    weak var fself: ModulatedPreMult? = nil // future self
    super.init(of: { x in
      let result = fself!.arrow.of( (fself!.factor * x) + fself!.modulation.of(x))
      return result
    })
    fself = self
  }
}

// from https://en.wikipedia.org/wiki/Low-pass_filter#Simple_infinite_impulse_response_filter
class LowPassFilter: Arrow11 {
  var previousOutput: Double = 0.0
  var previousTime: Double = 0.0
  var cutoff: Double
  init(of input: Arrow11, cutoff: Double, resonance: Double) {
    self.cutoff = cutoff

    weak var fself: LowPassFilter? = nil
    super.init(of: { t in
      let rc = 1.0 / (2 * .pi * cutoff)
      let dt = t - fself!.previousTime
      let alpha = dt / (rc + dt)
      let output = (alpha * input.of(t)) + (1 - alpha) * fself!.previousOutput
      fself!.previousOutput = output
      fself!.previousTime = t
      return output
    })
    fself = self
  }
}
