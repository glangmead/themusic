//
//  PADSynthWavetableArrowTests.swift
//  OrbitalTests
//

import Foundation
import Testing
@testable import Orbital

@Suite(.serialized)
struct PADSynthWavetableArrowTests {
  private func defaultParams() -> PADSynthSyntax {
    PADSynthSyntax(
      baseShape: .oneOverNSquared,
      tilt: 0.0,
      bandwidthCents: 50.0,
      bwScale: 1.0,
      profileShape: .gaussian,
      stretch: 1.0,
      selectedInstrument: nil,
      envelopeCoefficients: nil
    )
  }

  @Test func generatesNonEmptyWavetable() throws {
    let table = PADSynthWavetableCompiler.generateTable(params: defaultParams())
    #expect(table.count == WavetableLibrary.tableSize)
    let hasNonZero = table.contains { abs($0) > 1e-10 }
    #expect(hasNonZero)
  }

  @Test func arrowSyntaxRoundTrip() throws {
    let syntax: ArrowSyntax = .padSynthWavetable(
      name: "testOsc",
      params: defaultParams(),
      width: .const(name: "w", val: 1)
    )
    let data = try JSONEncoder().encode(syntax)
    let decoded = try JSONDecoder().decode(ArrowSyntax.self, from: data)
    #expect(decoded == syntax)
  }
}
