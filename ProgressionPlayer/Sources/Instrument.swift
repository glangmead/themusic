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
  sin(2 * .pi * $0)
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
    return ( cos(k * domain) * cos(domain), cos(k * domain) * sin(domain), sin(domain) )
  })
}

protocol HasFactor {
  var factor: Double { get set }
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

class ModulatedPreMult: Arrow11, HasFactor {
  var factor: Double
  var arrow: Arrow11
  var modulation: Arrow11
  let epsilon: Double = 1e-9
  init(factor: Double, arrow: Arrow11, modulation: Arrow11) {
    self.factor = factor
    self.arrow = arrow
    self.modulation = modulation
    weak var futureSelf: ModulatedPreMult? = nil
    super.init(of: { x in
      //let debug = futureSelf!.modulation.of(x)
      //print("\(debug)")
      // The below sounds OK but only after sticking in that "/ 1000.0". Without that the frequency swings between obscene extremes.      
      return futureSelf!.arrow.of( (futureSelf!.factor + (futureSelf!.modulation.of(x) / 1000.0 )) * x)
    })
    futureSelf = self
  }
}
