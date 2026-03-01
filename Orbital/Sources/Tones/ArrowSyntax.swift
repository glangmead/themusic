//
//  ArrowSyntax.swift
//  Orbital
//
//  Extracted from ToneGenerator.swift
//
//  Codable conformance → ArrowSyntax+Codable.swift
//  Compilation & tree ops → ArrowSyntax+Compile.swift
//

import Foundation

enum ArrowSyntax: Equatable {
  case const(name: String, val: CoreFloat)
  case constOctave(name: String, val: CoreFloat)
  case constCent(name: String, val: CoreFloat)
  case identity
  case control
  indirect case lowPassFilter(name: String, cutoff: ArrowSyntax, resonance: ArrowSyntax)
  indirect case combFilter(name: String, frequency: ArrowSyntax, feedback: ArrowSyntax)
  indirect case prod(of: [ArrowSyntax])
  indirect case compose(arrows: [ArrowSyntax])
  indirect case sum(of: [ArrowSyntax])
  indirect case crossfade(of: [ArrowSyntax], name: String, mixPoint: ArrowSyntax)
  indirect case crossfadeEqPow(of: [ArrowSyntax], name: String, mixPoint: ArrowSyntax)
  indirect case envelope(name: String, attack: CoreFloat, decay: CoreFloat, sustain: CoreFloat, release: CoreFloat, scale: CoreFloat)
  case choruser(name: String, valueToChorus: String, chorusCentRadius: Int, chorusNumVoices: Int)
  case noiseSmoothStep(noiseFreq: CoreFloat, min: CoreFloat, max: CoreFloat)
  case rand(min: CoreFloat, max: CoreFloat)
  case exponentialRand(min: CoreFloat, max: CoreFloat)
  case line(duration: CoreFloat, min: CoreFloat, max: CoreFloat)
  case reciprocalConst(name: String, val: CoreFloat)
  indirect case reciprocal(of: ArrowSyntax)
  case eventNote
  case eventVelocity
  case libraryArrow(name: String)
  case emitterValue(name: String)
  case quickExpression(String)

  indirect case osc(name: String, shape: BasicOscillator.OscShape, width: ArrowSyntax)
  indirect case wavetable(name: String, tableName: String, width: ArrowSyntax)
}

#if os(iOS)
import SwiftUI
#Preview {
  let osc = Triangle()
  osc.innerArr = ArrowIdentity()
  return ArrowChart(arrow: osc, ymin: -2, ymax: 2)
}
#endif
