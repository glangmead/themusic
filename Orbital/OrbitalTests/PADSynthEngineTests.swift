//
//  PADSynthEngineTests.swift
//  OrbitalTests
//

import Testing
import Foundation
@testable import Orbital

@Suite("PADSynthEngine", .serialized)
@MainActor
struct PADSynthEngineTests {

  // MARK: - Profile function

  @Test("Gaussian profile peaks at center")
  func gaussianProfilePeaksAtCenter() {
    let engine = PADSynthEngine()
    let center = engine.profile(fi: 0.0, bwi: 0.01, shape: .gaussian)
    let offset = engine.profile(fi: 0.005, bwi: 0.01, shape: .gaussian)
    #expect(center > offset, "Gaussian profile should peak at fi=0")
    #expect(center > 0)
  }

  @Test("Flat profile is constant within bandwidth")
  func flatProfileConstantWithinBand() {
    let engine = PADSynthEngine()
    let inside1 = engine.profile(fi: 0.0, bwi: 0.01, shape: .flat)
    let inside2 = engine.profile(fi: 0.005, bwi: 0.01, shape: .flat)
    let outside = engine.profile(fi: 0.02, bwi: 0.01, shape: .flat)
    #expect(inside1 > 0)
    #expect(inside1 == inside2)
    #expect(outside == 0)
  }

  // MARK: - freq_amp generation

  @Test("freq_amp has peaks at harmonic positions")
  func freqAmpHasPeaksAtHarmonics() {
    let engine = PADSynthEngine()
    engine.baseShape = .equal
    engine.tilt = 0.0
    engine.bandwidthCents = 50.0
    engine.bwScale = 1.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 440.0
    let freqAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)

    // Check that bins near harmonics 1, 2, 3 have higher amplitude than bins far from any harmonic
    let n = PADSynthEngine.wavetableSize
    let sr = PADSynthEngine.sampleRate
    for harmonic in 1...3 {
      let expectedBin = Int(round(fundamentalHz * CoreFloat(harmonic) / sr * CoreFloat(n)))
      let peakAmp = freqAmp[expectedBin]
      // A bin far from any harmonic — halfway between harmonic 1 and 2
      let farBin = Int(round(fundamentalHz * 1.5 / sr * CoreFloat(n)))
      let farAmp = freqAmp[farBin]
      #expect(peakAmp > farAmp, "Harmonic \(harmonic) peak should exceed midpoint amplitude")
    }
  }

  @Test("Higher harmonics have wider bandwidth in freq_amp")
  func higherHarmonicsHaveWiderBandwidth() {
    let engine = PADSynthEngine()
    engine.baseShape = .equal
    engine.tilt = 0.0
    engine.bandwidthCents = 100.0
    engine.bwScale = 1.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 200.0
    let freqAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    let n = PADSynthEngine.wavetableSize
    let sr = PADSynthEngine.sampleRate

    // Measure width at half-max for harmonics 1 and 4
    func halfMaxWidth(harmonic: Int) -> Int {
      let centerBin = Int(round(fundamentalHz * CoreFloat(harmonic) / sr * CoreFloat(n)))
      let halfMax = freqAmp[centerBin] / 2.0
      var width = 0
      for offset in 1..<5000 {
        let lo = centerBin - offset
        let hi = centerBin + offset
        if lo >= 0 && freqAmp[lo] >= halfMax { width += 1 }
        if hi < freqAmp.count && freqAmp[hi] >= halfMax { width += 1 }
        if (lo < 0 || freqAmp[lo] < halfMax) && (hi >= freqAmp.count || freqAmp[hi] < halfMax) {
          break
        }
      }
      return width
    }

    let width1 = halfMaxWidth(harmonic: 1)
    let width4 = halfMaxWidth(harmonic: 4)
    #expect(width4 > width1, "Harmonic 4 should be wider than harmonic 1 (got \(width4) vs \(width1))")
  }

  @Test("Narrow profile produces narrower peaks than Gaussian")
  func narrowProfileIsNarrower() {
    let engine = PADSynthEngine()
    engine.baseShape = .equal
    engine.bandwidthCents = 100.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 440.0
    let n = PADSynthEngine.wavetableSize
    let sr = PADSynthEngine.sampleRate

    engine.profileShape = .gaussian
    let gaussianAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    engine.profileShape = .narrow
    let narrowAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)

    // Compare amplitude 200 bins away from harmonic 1 center
    let centerBin = Int(round(fundamentalHz / sr * CoreFloat(n)))
    let offsetBin = centerBin + 200
    guard offsetBin < gaussianAmp.count else { return }

    // Narrow should have less energy far from center
    #expect(narrowAmp[offsetBin] < gaussianAmp[offsetBin],
            "Narrow profile should have less energy at offset than Gaussian")
  }

  @Test("Stretch > 1 shifts upper harmonics above integer multiples")
  func stretchShiftsHarmonicsUp() {
    let engine = PADSynthEngine()
    engine.baseShape = .equal
    engine.bandwidthCents = 25.0
    engine.bwScale = 1.0

    let fundamentalHz: CoreFloat = 200.0
    let n = PADSynthEngine.wavetableSize
    let sr = PADSynthEngine.sampleRate

    // Harmonic case: 5th harmonic at 1000 Hz
    engine.stretch = 1.0
    let harmonicAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    let harmonicBin5 = Int(round(1000.0 / sr * CoreFloat(n)))

    // Stretched case: 5th harmonic at 200 * 5^1.15 ≈ 1294 Hz
    engine.stretch = 1.15
    let stretchedAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    let stretchedExpectedFreq = fundamentalHz * pow(5.0, 1.15)
    let stretchedBin5 = Int(round(stretchedExpectedFreq / sr * CoreFloat(n)))

    #expect(stretchedBin5 > harmonicBin5,
            "Stretched 5th partial should be at a higher frequency")
    #expect(stretchedAmp[stretchedBin5] > stretchedAmp[harmonicBin5],
            "Stretched spectrum should peak near the stretched frequency, not the harmonic one")
  }

  @Test("Base shape 1/n produces decaying harmonic amplitudes")
  func baseShapeOneOverN() {
    let engine = PADSynthEngine()
    engine.baseShape = .oneOverN
    engine.tilt = 0.0
    engine.bandwidthCents = 25.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 440.0
    let freqAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    let n = PADSynthEngine.wavetableSize
    let sr = PADSynthEngine.sampleRate

    let bin1 = Int(round(fundamentalHz / sr * CoreFloat(n)))
    let bin3 = Int(round(3.0 * fundamentalHz / sr * CoreFloat(n)))
    #expect(freqAmp[bin1] > freqAmp[bin3],
            "Harmonic 1 should be louder than harmonic 3 with 1/n base shape")
  }

  @Test("Positive tilt brightens spectrum")
  func positiveTiltBrightens() {
    let engine = PADSynthEngine()
    engine.baseShape = .oneOverN
    engine.bandwidthCents = 25.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 440.0
    let n = PADSynthEngine.wavetableSize
    let sr = PADSynthEngine.sampleRate

    engine.tilt = 0.0
    let neutralAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    engine.tilt = 1.5
    let brightAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)

    // With positive tilt, higher harmonics should be relatively louder
    let bin5 = Int(round(5.0 * fundamentalHz / sr * CoreFloat(n)))
    let bin1 = Int(round(fundamentalHz / sr * CoreFloat(n)))
    let neutralRatio = neutralAmp[bin5] / neutralAmp[bin1]
    let brightRatio = brightAmp[bin5] / brightAmp[bin1]
    #expect(brightRatio > neutralRatio,
            "Positive tilt should increase the ratio of high to low harmonics")
  }

  // MARK: - Polynomial fitting

  @Test("Polynomial fit recovers known quadratic")
  func polynomialFitRecoversQuadratic() {
    // y = 0.5 - 0.3*x + 0.1*x^2, sampled at 50 points
    let points: [(x: CoreFloat, y: CoreFloat)] = (0..<50).map { i in
      let x = CoreFloat(i) / 49.0 * 10.0  // 0 to 10
      let y = 0.5 - 0.3 * x + 0.1 * x * x
      return (x: x, y: y)
    }

    let coeffs = PADSynthEngine.fitPolynomial(points: points, degree: 3)
    // With degree 3, the cubic and higher terms should be ~0
    #expect(abs(coeffs[0] - 0.5) < 0.01, "Constant term should be ~0.5, got \(coeffs[0])")
    #expect(abs(coeffs[1] - (-0.3)) < 0.01, "Linear term should be ~-0.3, got \(coeffs[1])")
    #expect(abs(coeffs[2] - 0.1) < 0.01, "Quadratic term should be ~0.1, got \(coeffs[2])")
    #expect(abs(coeffs[3]) < 0.01, "Cubic term should be ~0, got \(coeffs[3])")
  }

  @Test("Polynomial fit with degree 20 doesn't crash on small input")
  func polynomialFitSmallInput() {
    let points: [(x: CoreFloat, y: CoreFloat)] = [
      (x: 1.0, y: 0.8),
      (x: 5.0, y: 0.5),
      (x: 10.0, y: 0.3)
    ]
    // With fewer points than degree+1, should reduce degree gracefully
    let coeffs = PADSynthEngine.fitPolynomial(points: points, degree: 20)
    #expect(coeffs.count > 0, "Should return some coefficients")
    #expect(coeffs.count <= 3, "Should reduce degree to at most points.count - 1")
  }

  // MARK: - Envelope application

  @Test("Envelope controls amplitude ceiling at each frequency")
  func envelopeControlsAmplitudeCeiling() {
    let engine = PADSynthEngine()
    engine.bandwidthCents = 25.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 440.0

    // Constant envelope at 0.5 — max amplitude should be ~0.5
    engine.envelopeCoefficients = [0.5]
    let enveloped = engine.generateEnvelopedFreqAmp(fundamentalHz: fundamentalHz)

    let maxAmp = enveloped.max() ?? 0
    #expect(maxAmp > 0.4 && maxAmp < 0.6,
            "Constant 0.5 envelope should cap max amplitude near 0.5, got \(maxAmp)")
  }

  @Test("No envelope falls back to base shape")
  func noEnvelopeFallsBackToBaseShape() {
    let engine = PADSynthEngine()
    engine.baseShape = .oneOverSqrtN
    engine.bandwidthCents = 50.0
    engine.stretch = 1.0
    engine.envelopeCoefficients = nil

    let fundamentalHz: CoreFloat = 440.0
    let fromGenerate = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    let fromEnveloped = engine.generateEnvelopedFreqAmp(fundamentalHz: fundamentalHz)

    #expect(fromGenerate.count == fromEnveloped.count)
    for i in 0..<fromGenerate.count {
      #expect(fromGenerate[i] == fromEnveloped[i])
    }
  }

  // MARK: - Wavetable generation

  @Test("Generated wavetable has correct length and is normalized")
  func wavetableCorrectLengthAndNormalized() {
    let engine = PADSynthEngine()
    engine.baseShape = .oneOverSqrtN
    engine.bandwidthCents = 50.0
    engine.stretch = 1.0

    let wavetable = engine.generateWavetable(fundamentalHz: 261.63)

    #expect(wavetable.count == PADSynthEngine.wavetableSize,
            "Wavetable should have \(PADSynthEngine.wavetableSize) samples")
    let peak = wavetable.map { abs($0) }.max() ?? 0
    #expect(peak > 0.9 && peak <= 1.0,
            "Wavetable should be normalized to ~1.0, got peak \(peak)")
  }
}
