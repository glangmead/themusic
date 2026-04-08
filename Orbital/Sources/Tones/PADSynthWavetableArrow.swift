//
//  PADSynthWavetableArrow.swift
//  Orbital
//
//  Generates a wavetable from PADsynth parameters at compile time
//  and wraps it in a standard WavetableOscillator.
//

import Foundation

enum PADSynthWavetableCompiler {
  /// Reference pitch for wavetable generation (middle C).
  /// The phase accumulator handles actual pitch tracking.
  private static let referencePitch: CoreFloat = 261.63

  /// Generate a WavetableLibrary-compatible table (2048 samples) from PADsynth params.
  static func generateTable(params: PADSynthSyntax) -> [CoreFloat] {
    let sharcHarmonics = PADSynthEngine.resolveSharcHarmonics(
      instrumentId: params.selectedInstrument,
      midiNote: 60 // middle C
    )
    let snapshot = PADSynthEngine.ParamSnapshot(
      baseShape: params.baseShape,
      tilt: params.tilt,
      bandwidthCents: params.bandwidthCents,
      bwScale: params.bwScale,
      profileShape: params.profileShape,
      stretch: params.stretch,
      envelopeCoefficients: params.envelopeCoefficients,
      sharcHarmonics: sharcHarmonics
    )
    let fullTable = PADSynthEngine.generateWavetableStatic(
      fundamentalHz: referencePitch,
      params: snapshot
    )
    return downsampleToLibrarySize(fullTable)
  }

  /// Downsample a large PADsynth wavetable to WavetableLibrary.tableSize (2048).
  private static func downsampleToLibrarySize(_ source: [CoreFloat]) -> [CoreFloat] {
    let targetSize = WavetableLibrary.tableSize
    guard source.count > targetSize else { return source }
    let ratio = CoreFloat(source.count) / CoreFloat(targetSize)
    var result = [CoreFloat](repeating: 0, count: targetSize)
    for i in 0..<targetSize {
      let srcIndex = Int(CoreFloat(i) * ratio)
      result[i] = source[min(srcIndex, source.count - 1)]
    }
    return result
  }
}
