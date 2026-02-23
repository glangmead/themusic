//
//  ArrowWithHandles.swift
//  Orbital
//
//  Extracted from ToneGenerator.swift
//

import Foundation

class ArrowWithHandles: Arrow11 {
  // the handles are dictionaries with values that give access to arrows within the arrow
  var namedBasicOscs     = [String: [BasicOscillator]]()
  var namedLowPassFilter = [String: [LowPassFilter2]]()
  var namedConsts        = [String: [ValHaver]]()
  var namedADSREnvelopes = [String: [ADSR]]()
  var namedChorusers     = [String: [Choruser]]()
  var namedCrossfaders   = [String: [ArrowCrossfade]]()
  var namedCrossfadersEqPow = [String: [ArrowEqualPowerCrossfade]]()
  var namedEventUsing = [String: [EventUsingArrow]]()
  var namedEmitterValues = [String: [ArrowConst]]()
  var wrappedArrow: Arrow11
  private var wrappedArrowUnsafe: Unmanaged<Arrow11>
  
  init(_ wrappedArrow: Arrow11) {
    // has an arrow
    self.wrappedArrow = wrappedArrow
    self.wrappedArrowUnsafe = Unmanaged.passUnretained(wrappedArrow)
    // does not participate in its superclass arrowness
    super.init()
  }
  
  override func setSampleRateRecursive(rate: CoreFloat) {
    wrappedArrow.setSampleRateRecursive(rate: rate)
    super.setSampleRateRecursive(rate: rate)
  }

  override func process(inputs: [CoreFloat], outputs: inout [CoreFloat]) {
    wrappedArrowUnsafe._withUnsafeGuaranteedRef { $0.process(inputs: inputs, outputs: &outputs) }
  }

  func withMergeDictsFromArrow(_ arr2: ArrowWithHandles) -> ArrowWithHandles {
    namedADSREnvelopes.merge(arr2.namedADSREnvelopes) { (a, b) in return a + b }
    namedConsts.merge(arr2.namedConsts) { (a, b) in
      return a + b
    }
    namedBasicOscs.merge(arr2.namedBasicOscs) { (a, b) in return a + b }
    namedLowPassFilter.merge(arr2.namedLowPassFilter) { (a, b) in return a + b }
    namedChorusers.merge(arr2.namedChorusers) { (a, b) in return a + b }
    namedCrossfaders.merge(arr2.namedCrossfaders) { (a, b) in return a + b }
    namedCrossfadersEqPow.merge(arr2.namedCrossfadersEqPow) { (a, b) in return a + b }
    namedEventUsing.merge(arr2.namedEventUsing) { (a, b) in return a + b }
    namedEmitterValues.merge(arr2.namedEmitterValues) { (a, b) in return a + b }
    return self
  }
  
  func withMergeDictsFromArrows(_ arrs: [ArrowWithHandles]) -> ArrowWithHandles {
    for arr in arrs {
      let _ = withMergeDictsFromArrow(arr)
    }
    return self
  }
}
