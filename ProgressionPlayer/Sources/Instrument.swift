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

class ControlArrow: Arrow11 {
  var lastTimeEmitted = 0.0
  var lastEmission = 0.0
  let timeBetweenEmissions = 1000.0 / 44100.0
  init(of arrow: Arrow11) {
    weak var fself: ControlArrow? = nil
    super.init(of: { t in
      if t - fself!.lastTimeEmitted >= fself!.timeBetweenEmissions {
        fself!.lastEmission = arrow.of(t)
      }
      return fself!.lastEmission
    })
    fself = self
  }
}

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
  var factor: Double {
    didSet {
      integratedFactor = factor
    }
  }
  var arrow: Arrow11
  var modulation: Arrow11
  var integratedFactor: Double
  init(factor: Double, arrow: Arrow11, modulation: Arrow11) {
    self.factor = factor
    self.integratedFactor = factor
    self.arrow = arrow
    self.modulation = modulation
    weak var fself: ModulatedPreMult? = nil // future self
    super.init(of: { x in
      fself!.integratedFactor += fself!.modulation.of(x)
      return fself!.arrow.of( fself!.integratedFactor * x)
    })
    fself = self
  }
}
