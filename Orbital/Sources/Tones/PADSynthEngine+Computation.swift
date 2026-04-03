//
//  PADSynthEngine+Computation.swift
//  Orbital
//
//  Thread-safe static computation methods for PADSynthEngine.
//  All methods are nonisolated and operate on ParamSnapshot values.
//

import Accelerate
import Foundation

extension PADSynthEngine {

  /// Snapshot of parameters needed for off-main-thread computation.
  struct ParamSnapshot: Sendable {
    let baseShape: PADBaseShape
    let tilt: CoreFloat
    let bandwidthCents: CoreFloat
    let bwScale: CoreFloat
    let profileShape: PADProfileShape
    let stretch: CoreFloat
    let envelopeCoefficients: [CoreFloat]?
    let sharcHarmonics: [CoreFloat]?
  }

  struct DisplayPoint: Identifiable {
    let id: Int
    let frequency: CoreFloat
    let amplitude: CoreFloat
  }

  // MARK: - Polynomial fitting

  /// Least-squares polynomial fit using LAPACK dgels_.
  /// Input: array of (x, y) points. Output: polynomial coefficients [c0, c1, ..., cD]
  /// where y ≈ c0 + c1*x + c2*x^2 + ... + cD*x^D.
  /// If there are fewer points than degree+1, degree is reduced to points.count - 1.
  static func fitPolynomial(
    points: [(x: CoreFloat, y: CoreFloat)],
    degree: Int = 20
  ) -> [CoreFloat] {
    guard !points.isEmpty else { return [] }
    let m = points.count
    let effectiveDegree = min(degree, m - 1)
    let n = effectiveDegree + 1  // number of coefficients

    // Build Vandermonde matrix (column-major for LAPACK).
    // A[i, j] = x_i^j, stored column-major: A[i + j*m]
    var vandermonde = [Double](repeating: 0, count: m * n)
    for j in 0..<n {
      for i in 0..<m {
        vandermonde[i + j * m] = pow(points[i].x, Double(j))
      }
    }

    // Right-hand side: y values. dgels_ overwrites this with the solution.
    // Needs to be max(m, n) long.
    var rhs = [Double](repeating: 0, count: max(m, n))
    for i in 0..<m {
      rhs[i] = points[i].y
    }

    var mVar = __LAPACK_int(m)
    var nVar = __LAPACK_int(n)
    var nrhs: __LAPACK_int = 1
    var lda = __LAPACK_int(m)
    var ldb = __LAPACK_int(max(m, n))
    var info: __LAPACK_int = 0

    // Query optimal workspace size
    var workQuery: Double = 0
    var lworkQuery: __LAPACK_int = -1
    var trans = Int8(UInt8(ascii: "N"))
    dgels_(&trans, &mVar, &nVar, &nrhs, &vandermonde, &lda, &rhs, &ldb, &workQuery, &lworkQuery, &info)

    var lwork = __LAPACK_int(workQuery)
    var work = [Double](repeating: 0, count: Int(lwork))
    dgels_(&trans, &mVar, &nVar, &nrhs, &vandermonde, &lda, &rhs, &ldb, &work, &lwork, &info)

    guard info == 0 else { return [1.0] }  // fallback: constant 1.0

    return Array(rhs.prefix(n))
  }

  /// Evaluates polynomial with given coefficients at x.
  nonisolated static func evaluatePolynomial(_ coeffs: [CoreFloat], at x: CoreFloat) -> CoreFloat {
    var result: CoreFloat = 0
    var xPow: CoreFloat = 1.0
    for c in coeffs {
      result += c * xPow
      xPow *= x
    }
    return result
  }

  // MARK: - Static (thread-safe) computation methods

  /// Resolves SHARC harmonics for a MIDI note. Thread-safe, no actor isolation.
  nonisolated static func resolveSharcHarmonics(
    instrumentId: String?, midiNote: UInt8
  ) -> [CoreFloat]? {
    guard let instId = instrumentId,
          let inst = SharcDatabase.shared.instrument(id: instId) else {
      return nil
    }
    return inst.harmonicsForMidiNote(Int(midiNote))
  }

  /// Generates a wavetable from a parameter snapshot. Thread-safe, no actor isolation.
  nonisolated static func generateWavetableStatic(
    fundamentalHz: CoreFloat, params: ParamSnapshot
  ) -> [CoreFloat] {
    let n = wavetableSize
    let halfN = n / 2

    let freqAmpLocal: [CoreFloat]
    if params.envelopeCoefficients != nil {
      let flatParams = ParamSnapshot(
        baseShape: .equal, tilt: 0, bandwidthCents: params.bandwidthCents,
        bwScale: params.bwScale, profileShape: params.profileShape,
        stretch: params.stretch, envelopeCoefficients: nil,
        sharcHarmonics: params.sharcHarmonics
      )
      let flatFreqAmp = generateFreqAmpStatic(fundamentalHz: fundamentalHz, params: flatParams)
      let peak = flatFreqAmp.max() ?? 1.0
      guard peak > 1e-12 else { return [CoreFloat](repeating: 0, count: n) }
      let invPeak = 1.0 / peak
      let logMin = log2(minFreq)
      let logMax = log2(maxFreq)
      freqAmpLocal = flatFreqAmp.enumerated().map { i, amp in
        let freqHz = CoreFloat(i) / CoreFloat(n) * sampleRate
        guard freqHz >= minFreq && freqHz <= maxFreq else { return 0 }
        let logFreq = log2(freqHz)
        let normalizedLogFreq = (logFreq - logMin) / (logMax - logMin) * 10.0
        let envValue = max(0, min(1, evaluatePolynomial(params.envelopeCoefficients!, at: normalizedLogFreq)))
        return amp * invPeak * envValue
      }
    } else {
      freqAmpLocal = generateFreqAmpStatic(fundamentalHz: fundamentalHz, params: params)
    }

    // Random phases + IFFT
    var realParts = [CoreFloat](repeating: 0, count: halfN)
    var imagParts = [CoreFloat](repeating: 0, count: halfN)

    for i in 0..<halfN {
      let phase = CoreFloat.random(in: 0..<(2.0 * .pi))
      realParts[i] = freqAmpLocal[i] * cos(phase)
      imagParts[i] = freqAmpLocal[i] * sin(phase)
    }
    imagParts[0] = 0

    let log2n = vDSP_Length(log2(CoreFloat(n)))
    guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
      return [CoreFloat](repeating: 0, count: n)
    }
    defer { vDSP_destroy_fftsetupD(fftSetup) }

    var splitReal = [CoreFloat](repeating: 0, count: halfN)
    var splitImag = [CoreFloat](repeating: 0, count: halfN)
    splitReal[0] = realParts[0]
    splitImag[0] = realParts[halfN - 1]
    for i in 1..<halfN {
      splitReal[i] = realParts[i]
      splitImag[i] = imagParts[i]
    }

    var output = [CoreFloat](repeating: 0, count: n)
    splitReal.withUnsafeMutableBufferPointer { realBuf in
      splitImag.withUnsafeMutableBufferPointer { imagBuf in
        var splitComplex = DSPDoubleSplitComplex(
          realp: realBuf.baseAddress!,
          imagp: imagBuf.baseAddress!
        )
        vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))
      }
    }

    for i in 0..<halfN {
      output[2 * i] = splitReal[i]
      output[2 * i + 1] = splitImag[i]
    }

    var scale = 1.0 / CoreFloat(2 * n)
    output.withUnsafeMutableBufferPointer { buf in
      vDSP_vsmulD(buf.baseAddress!, 1, &scale, buf.baseAddress!, 1, vDSP_Length(n))
    }

    var peak: CoreFloat = 0
    vDSP_maxmgvD(output, 1, &peak, vDSP_Length(n))
    if peak > 0 {
      var invPeak = 1.0 / peak
      output.withUnsafeMutableBufferPointer { buf in
        vDSP_vsmulD(buf.baseAddress!, 1, &invPeak, buf.baseAddress!, 1, vDSP_Length(n))
      }
    }

    return output
  }

  nonisolated static func generateFreqAmpStatic(
    fundamentalHz: CoreFloat, params: ParamSnapshot
  ) -> [CoreFloat] {
    let n = wavetableSize
    let halfN = n / 2
    let sr = sampleRate
    var maxHarmonic = Int(sr / fundamentalHz)
    if let sharc = params.sharcHarmonics {
      maxHarmonic = min(maxHarmonic, sharc.count)
    }
    var freqAmp = [CoreFloat](repeating: 0, count: halfN)

    for nh in 1...maxHarmonic {
      let relF = pow(CoreFloat(nh), params.stretch)
      let harmonicFreq = fundamentalHz * relF
      guard harmonicFreq < sr / 2.0 else { break }

      let baseAmp: CoreFloat
      if let sharc = params.sharcHarmonics, nh <= sharc.count {
        baseAmp = sharc[nh - 1]
      } else {
        baseAmp = params.baseShape.amplitude(harmonic: nh)
      }
      let a = baseAmp * pow(CoreFloat(nh), params.tilt)
      guard a > 1e-12 else { continue }

      let bwHz = (pow(2.0, params.bandwidthCents / 1200.0) - 1.0) * fundamentalHz * pow(relF, params.bwScale)
      let bwi = bwHz / (2.0 * sr)
      let fi = fundamentalHz * relF / sr

      let profilePeak = profileStatic(fi: 0, bwi: bwi, shape: params.profileShape)
      guard profilePeak > 1e-12 else { continue }

      let spreadBins = max(Int(ceil(6.0 * bwi * CoreFloat(n))), 10)
      let centerBin = Int(round(fi * CoreFloat(n)))
      let lo = max(0, centerBin - spreadBins)
      let hi = min(halfN - 1, centerBin + spreadBins)

      for i in lo...hi {
        let binFreqNorm = CoreFloat(i) / CoreFloat(n)
        let hprofile = profileStatic(fi: binFreqNorm - fi, bwi: bwi, shape: params.profileShape)
        freqAmp[i] += (hprofile / profilePeak) * a
      }
    }

    return freqAmp
  }

  /// Pure computation, no actor isolation. Runs on any thread.
  nonisolated static func computeDisplay(
    params: ParamSnapshot
  ) -> (rawFreqAmp: [CoreFloat], displayFreqAmp: [DisplayPoint],
        displayEnvelope: [DisplayPoint], displayProduct: [DisplayPoint]) {
    let fundamentalHz: CoreFloat = 261.63

    let rawFreqAmp = generateFreqAmpStatic(fundamentalHz: fundamentalHz, params: params)
    let envelopedFreqAmp = generateEnvelopedFreqAmpStatic(
      fundamentalHz: fundamentalHz, params: params, rawGenerator: generateFreqAmpStatic
    )

    let dispFreqAmp = downsampleForDisplayStatic(rawFreqAmp)
    let blueMax = dispFreqAmp.map(\.amplitude).max() ?? 1.0
    let dispEnvelope = computeEnvelopeDisplayStatic(
      coefficients: params.envelopeCoefficients, scale: blueMax
    )
    let dispProduct = downsampleForDisplayStatic(envelopedFreqAmp.map { $0 * blueMax })

    return (rawFreqAmp, dispFreqAmp, dispEnvelope, dispProduct)
  }

  private nonisolated static func profileStatic(
    fi: CoreFloat, bwi: CoreFloat, shape: PADProfileShape
  ) -> CoreFloat {
    switch shape {
    case .gaussian:
      let x = fi / bwi
      return exp(-x * x) / bwi
    case .flat:
      return abs(fi) < bwi ? 1.0 / (2.0 * bwi) : 0.0
    case .detuned:
      let sigma = 0.1 * bwi
      let sigma2 = sigma * sigma
      let left = exp(-(fi - 0.5 * bwi) * (fi - 0.5 * bwi) / sigma2)
      let right = exp(-(fi + 0.5 * bwi) * (fi + 0.5 * bwi) / sigma2)
      return (left + right) / (2.0 * bwi)
    case .narrow:
      let narrowBwi = 0.25 * bwi
      let x = fi / narrowBwi
      return exp(-x * x) / (0.5 * bwi)
    }
  }

  private nonisolated static func generateEnvelopedFreqAmpStatic(
    fundamentalHz: CoreFloat,
    params: ParamSnapshot,
    rawGenerator: (CoreFloat, ParamSnapshot) -> [CoreFloat]
  ) -> [CoreFloat] {
    guard let coeffs = params.envelopeCoefficients else {
      return rawGenerator(fundamentalHz, params)
    }

    // Generate flat spectrum
    let flatParams = ParamSnapshot(
      baseShape: .equal, tilt: 0, bandwidthCents: params.bandwidthCents,
      bwScale: params.bwScale, profileShape: params.profileShape,
      stretch: params.stretch, envelopeCoefficients: nil,
      sharcHarmonics: params.sharcHarmonics
    )
    let flatFreqAmp = rawGenerator(fundamentalHz, flatParams)

    let peak = flatFreqAmp.max() ?? 1.0
    guard peak > 1e-12 else { return flatFreqAmp }
    let invPeak = 1.0 / peak

    let n = wavetableSize
    let sr = sampleRate
    let logMin = log2(minFreq)
    let logMax = log2(maxFreq)

    return flatFreqAmp.enumerated().map { i, amp in
      let freqHz = CoreFloat(i) / CoreFloat(n) * sr
      guard freqHz >= minFreq && freqHz <= maxFreq else { return 0 }
      let logFreq = log2(freqHz)
      let normalizedLogFreq = (logFreq - logMin) / (logMax - logMin) * 10.0
      let envValue = max(0, min(1, evaluatePolynomial(coeffs, at: normalizedLogFreq)))
      return amp * invPeak * envValue
    }
  }

  nonisolated static func downsampleForDisplayStatic(_ source: [CoreFloat]) -> [DisplayPoint] {
    let n = wavetableSize
    let sr = sampleRate
    let logMin = log2(minFreq)
    let logMax = log2(maxFreq)
    let pointCount = displayPoints

    return (0..<pointCount).map { idx in
      let t0 = CoreFloat(idx) / CoreFloat(pointCount)
      let t1 = CoreFloat(idx + 1) / CoreFloat(pointCount)
      let freqLo = pow(2.0, logMin + t0 * (logMax - logMin))
      let freqHi = pow(2.0, logMin + t1 * (logMax - logMin))
      let binLo = max(0, min(source.count - 1, Int(freqLo / sr * CoreFloat(n))))
      let binHi = max(binLo, min(source.count - 1, Int(freqHi / sr * CoreFloat(n))))

      var peak: CoreFloat = 0
      for bin in binLo...binHi where source[bin] > peak {
        peak = source[bin]
      }

      let centerFreq = pow(2.0, logMin + (t0 + t1) / 2.0 * (logMax - logMin))
      return DisplayPoint(id: idx, frequency: centerFreq, amplitude: peak)
    }
  }

  nonisolated static func computeEnvelopeDisplayStatic(
    coefficients: [CoreFloat]?, scale: CoreFloat
  ) -> [DisplayPoint] {
    guard let coeffs = coefficients else { return [] }
    let logMin = log2(minFreq)
    let logMax = log2(maxFreq)
    let pointCount = displayPoints

    return (0..<pointCount).map { idx in
      let t = (CoreFloat(idx) + 0.5) / CoreFloat(pointCount)
      let freq = pow(2.0, logMin + t * (logMax - logMin))
      let normalizedLogFreq = t * 10.0
      let envValue = max(0, min(1, evaluatePolynomial(coeffs, at: normalizedLogFreq)))
      return DisplayPoint(id: idx, frequency: freq, amplitude: envValue * scale)
    }
  }
}
