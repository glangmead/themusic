//
//  PADSynthEngine.swift
//  Orbital
//

import Accelerate
import Foundation

// MARK: - Parameter Types

enum PADBaseShape: String, CaseIterable, Identifiable {
  case oneOverN = "1/n"
  case oneOverSqrtN = "1/√n"
  case oddHarmonics = "Odd harmonics"
  case equal = "Equal"
  case oneOverNSquared = "1/n²"

  var id: String { rawValue }

  func amplitude(harmonic nh: Int) -> CoreFloat {
    let n = CoreFloat(nh)
    switch self {
    case .oneOverN: return 1.0 / n
    case .oneOverSqrtN: return 1.0 / sqrt(n)
    case .oddHarmonics: return (nh % 2 == 1) ? 1.0 / n : 0.0
    case .equal: return 1.0
    case .oneOverNSquared: return 1.0 / (n * n)
    }
  }
}

enum PADProfileShape: String, CaseIterable, Identifiable {
  case gaussian = "Gaussian"
  case flat = "Flat"
  case detuned = "Detuned"
  case narrow = "Narrow"

  var id: String { rawValue }
}

enum PADOvertonePreset: String, CaseIterable, Identifiable {
  case harmonic = "Harmonic"
  case piano = "Piano"
  case bell = "Bell"
  case metallic = "Metallic"
  case glass = "Glass"

  var id: String { rawValue }

  var stretchValue: CoreFloat {
    switch self {
    case .harmonic: return 1.0
    case .piano: return 1.01
    case .bell: return 1.15
    case .metallic: return 1.3
    case .glass: return 0.95
    }
  }
}

// MARK: - PADSynthEngine

@MainActor @Observable
final class PADSynthEngine {
  // Algorithm parameters
  var baseShape: PADBaseShape = .oneOverNSquared
  var tilt: CoreFloat = 0.0
  var bandwidthCents: CoreFloat = 50.0
  var bwScale: CoreFloat = 1.0
  var profileShape: PADProfileShape = .gaussian
  var overtonePreset: PADOvertonePreset = .harmonic
  var stretch: CoreFloat = 1.0

  // Envelope (polynomial coefficients in log-frequency space)
  var envelopeCoefficients: [CoreFloat]?

  // Computed state for display
  var freqAmp: [CoreFloat] = []
  var displayFreqAmp: [DisplayPoint] = []
  var displayEnvelope: [DisplayPoint] = []
  var displayProduct: [DisplayPoint] = []
  // Increments when display data changes, used to avoid re-rendering the chart
  var displayVersion: Int = 0

  // Constants
  static let wavetableSize = 262_144
  static let sampleRate: CoreFloat = 44_100.0
  static let displayPoints = 500
  static let minFreq: CoreFloat = 20.0
  static let maxFreq: CoreFloat = 40_000.0

  struct DisplayPoint: Identifiable {
    let id: Int
    let frequency: CoreFloat
    let amplitude: CoreFloat
  }

  // MARK: - Profile function

  /// Harmonic profile: returns the amplitude contribution at frequency offset `fi` from the
  /// harmonic center, given normalized bandwidth `bwi`.
  nonisolated func profile(fi: CoreFloat, bwi: CoreFloat, shape: PADProfileShape) -> CoreFloat {
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

  // MARK: - freq_amp generation

  /// Runs the PADsynth extended algorithm, returning the freq_amp array (N/2 entries).
  /// Does not apply the user-drawn envelope.
  func generateFreqAmp(fundamentalHz: CoreFloat) -> [CoreFloat] {
    let n = Self.wavetableSize
    let halfN = n / 2
    let sr = Self.sampleRate
    let maxHarmonic = Int(sr / fundamentalHz)
    var freqAmp = [CoreFloat](repeating: 0, count: halfN)

    for nh in 1...maxHarmonic {
      let relF = pow(CoreFloat(nh), stretch)
      let harmonicFreq = fundamentalHz * relF
      guard harmonicFreq < sr / 2.0 else { break }

      let a = baseShape.amplitude(harmonic: nh) * pow(CoreFloat(nh), tilt)
      guard a > 1e-12 else { continue }

      let bwHz = (pow(2.0, bandwidthCents / 1200.0) - 1.0) * fundamentalHz * pow(relF, bwScale)
      let bwi = bwHz / (2.0 * sr)
      let fi = fundamentalHz * relF / sr

      // Peak-normalize the profile so base shape directly controls peak height
      let profilePeak = profile(fi: 0, bwi: bwi, shape: profileShape)
      guard profilePeak > 1e-12 else { continue }

      // Only iterate over bins where the profile has significant energy.
      // For Gaussian, 6 standard deviations covers > 99.99%.
      let spreadBins = max(Int(ceil(6.0 * bwi * CoreFloat(n))), 10)
      let centerBin = Int(round(fi * CoreFloat(n)))
      let lo = max(0, centerBin - spreadBins)
      let hi = min(halfN - 1, centerBin + spreadBins)

      for i in lo...hi {
        let binFreqNorm = CoreFloat(i) / CoreFloat(n)
        let hprofile = profile(fi: binFreqNorm - fi, bwi: bwi, shape: profileShape)
        freqAmp[i] += (hprofile / profilePeak) * a
      }
    }

    return freqAmp
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

    var mVar = __CLPK_integer(m)
    var nVar = __CLPK_integer(n)
    var nrhs: __CLPK_integer = 1
    var lda = __CLPK_integer(m)
    var ldb = __CLPK_integer(max(m, n))
    var info: __CLPK_integer = 0

    // Query optimal workspace size
    var workQuery: Double = 0
    var lworkQuery: __CLPK_integer = -1
    var trans = Int8(UInt8(ascii: "N"))
    dgels_(&trans, &mVar, &nVar, &nrhs, &vandermonde, &lda, &rhs, &ldb, &workQuery, &lworkQuery, &info)

    var lwork = __CLPK_integer(workQuery)
    var work = [Double](repeating: 0, count: Int(lwork))
    dgels_(&trans, &mVar, &nVar, &nrhs, &vandermonde, &lda, &rhs, &ldb, &work, &lwork, &info)

    guard info == 0 else { return [1.0] }  // fallback: constant 1.0

    return Array(rhs.prefix(n))
  }

  // MARK: - Envelope application

  /// Generates an enveloped freq_amp where the drawn line controls the amplitude ceiling
  /// at each frequency. Works by:
  /// 1. Generating a "flat" spectrum (equal harmonics, peak-normalized) to establish
  ///    the maximum possible amplitude at each bin.
  /// 2. Normalizing to [0, 1].
  /// 3. Multiplying bin-by-bin by the envelope evaluated at each bin's frequency.
  /// This ensures the total amplitude (including overlapping harmonics) matches the drawn line.
  /// Returns the unenveloped freq_amp if no envelope is set.
  func generateEnvelopedFreqAmp(fundamentalHz: CoreFloat) -> [CoreFloat] {
    guard let coeffs = envelopeCoefficients else {
      return generateFreqAmp(fundamentalHz: fundamentalHz)
    }

    // Generate flat spectrum: all harmonics at equal amplitude with peak-normalized profiles
    let savedBaseShape = baseShape
    let savedTilt = tilt
    baseShape = .equal
    tilt = 0
    let flatFreqAmp = generateFreqAmp(fundamentalHz: fundamentalHz)
    baseShape = savedBaseShape
    tilt = savedTilt

    // Normalize to [0, 1]
    let peak = flatFreqAmp.max() ?? 1.0
    guard peak > 1e-12 else { return flatFreqAmp }
    let invPeak = 1.0 / peak

    // Multiply each bin by the envelope evaluated at that bin's frequency
    let n = Self.wavetableSize
    let sr = Self.sampleRate
    let logMin = log2(Self.minFreq)
    let logMax = log2(Self.maxFreq)

    return flatFreqAmp.enumerated().map { i, amp in
      let freqHz = CoreFloat(i) / CoreFloat(n) * sr
      guard freqHz >= Self.minFreq && freqHz <= Self.maxFreq else { return 0 }
      let logFreq = log2(freqHz)
      let normalizedLogFreq = (logFreq - logMin) / (logMax - logMin) * 10.0
      let envValue = max(0, min(1, Self.evaluatePolynomial(coeffs, at: normalizedLogFreq)))
      return amp * invPeak * envValue
    }
  }

  // MARK: - Wavetable generation (IFFT)

  /// Full pipeline: generate freq_amp, apply envelope, random phases, IFFT, normalize.
  /// Returns a wavetable of length `wavetableSize`.
  func generateWavetable(fundamentalHz: CoreFloat) -> [CoreFloat] {
    let n = Self.wavetableSize
    let halfN = n / 2

    let freqAmpLocal = generateEnvelopedFreqAmp(fundamentalHz: fundamentalHz)

    // Build split complex for real IFFT.
    // real[i] = freq_amp[i] * cos(phase[i])
    // imag[i] = freq_amp[i] * sin(phase[i])
    var realParts = [CoreFloat](repeating: 0, count: halfN)
    var imagParts = [CoreFloat](repeating: 0, count: halfN)

    for i in 0..<halfN {
      let phase = CoreFloat.random(in: 0..<(2.0 * .pi))
      realParts[i] = freqAmpLocal[i] * cos(phase)
      imagParts[i] = freqAmpLocal[i] * sin(phase)
    }
    // DC and Nyquist are purely real
    imagParts[0] = 0

    // vDSP real FFT setup
    let log2n = vDSP_Length(log2(CoreFloat(n)))
    guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
      return [CoreFloat](repeating: 0, count: n)
    }
    defer { vDSP_destroy_fftsetupD(fftSetup) }

    // Pack into vDSP packed format:
    // splitReal[0] = DC, splitImag[0] = Nyquist
    // splitReal[k] = Re(X[k]), splitImag[k] = Im(X[k]) for k = 1..halfN-1
    var splitReal = [CoreFloat](repeating: 0, count: halfN)
    var splitImag = [CoreFloat](repeating: 0, count: halfN)

    splitReal[0] = realParts[0]
    splitImag[0] = realParts[halfN - 1]
    for i in 1..<halfN {
      splitReal[i] = realParts[i]
      splitImag[i] = imagParts[i]
    }

    var splitComplex = DSPDoubleSplitComplex(
      realp: &splitReal,
      imagp: &splitImag
    )

    // Inverse FFT (in-place)
    vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))

    // Unpack interleaved result
    var output = [CoreFloat](repeating: 0, count: n)
    for i in 0..<halfN {
      output[2 * i] = splitReal[i]
      output[2 * i + 1] = splitImag[i]
    }

    // vDSP inverse FFT has a scale factor of 2. Normalize.
    var scale = 1.0 / CoreFloat(2 * n)
    output.withUnsafeMutableBufferPointer { buf in
      vDSP_vsmulD(buf.baseAddress!, 1, &scale, buf.baseAddress!, 1, vDSP_Length(n))
    }

    // Normalize to [-1, 1]
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

  // MARK: - Display data

  /// Downsamples freq_amp to displayPoints entries using peak-hold, for chart rendering.
  /// Frequency axis is logarithmic: each display point covers an equal range in log2(freq).
  func downsampleForDisplay(_ source: [CoreFloat]) -> [DisplayPoint] {
    let n = Self.wavetableSize
    let sr = Self.sampleRate
    let logMin = log2(Self.minFreq)
    let logMax = log2(Self.maxFreq)
    let pointCount = Self.displayPoints

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

  /// Computes envelope display points from the current polynomial coefficients,
  /// scaled to match the blue spectrum's amplitude range.
  func computeEnvelopeDisplay(scale: CoreFloat) -> [DisplayPoint] {
    guard let coeffs = envelopeCoefficients else { return [] }
    let logMin = log2(Self.minFreq)
    let logMax = log2(Self.maxFreq)
    let pointCount = Self.displayPoints

    return (0..<pointCount).map { idx in
      let t = (CoreFloat(idx) + 0.5) / CoreFloat(pointCount)
      let freq = pow(2.0, logMin + t * (logMax - logMin))
      let normalizedLogFreq = t * 10.0
      let envValue = max(0, min(1, Self.evaluatePolynomial(coeffs, at: normalizedLogFreq)))
      return DisplayPoint(id: idx, frequency: freq, amplitude: envValue * scale)
    }
  }

  /// Snapshot of parameters needed for off-main-thread computation.
  struct ParamSnapshot: Sendable {
    let baseShape: PADBaseShape
    let tilt: CoreFloat
    let bandwidthCents: CoreFloat
    let bwScale: CoreFloat
    let profileShape: PADProfileShape
    let stretch: CoreFloat
    let envelopeCoefficients: [CoreFloat]?
  }

  /// Creates a snapshot of current parameters for off-main-thread use.
  func currentParams() -> ParamSnapshot {
    ParamSnapshot(
      baseShape: baseShape, tilt: tilt, bandwidthCents: bandwidthCents,
      bwScale: bwScale, profileShape: profileShape, stretch: stretch,
      envelopeCoefficients: envelopeCoefficients
    )
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
        stretch: params.stretch, envelopeCoefficients: nil
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

    var splitComplex = DSPDoubleSplitComplex(realp: &splitReal, imagp: &splitImag)
    vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))

    var output = [CoreFloat](repeating: 0, count: n)
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

  /// Recomputes all display data. Call after parameter changes.
  /// Heavy computation runs off the main thread; only the final assignment is on MainActor.
  func recomputeDisplay() async {
    let params = currentParams()

    let result = await Task.detached(priority: .userInitiated) {
      Self.computeDisplay(params: params)
    }.value

    freqAmp = result.rawFreqAmp
    displayFreqAmp = result.displayFreqAmp
    displayEnvelope = result.displayEnvelope
    displayProduct = result.displayProduct
    displayVersion += 1
  }

  /// Pure computation, no actor isolation. Runs on any thread.
  private nonisolated static func computeDisplay(
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

  // MARK: - Static (thread-safe) computation methods

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

  private nonisolated static func generateFreqAmpStatic(
    fundamentalHz: CoreFloat, params: ParamSnapshot
  ) -> [CoreFloat] {
    let n = wavetableSize
    let halfN = n / 2
    let sr = sampleRate
    let maxHarmonic = Int(sr / fundamentalHz)
    var freqAmp = [CoreFloat](repeating: 0, count: halfN)

    for nh in 1...maxHarmonic {
      let relF = pow(CoreFloat(nh), params.stretch)
      let harmonicFreq = fundamentalHz * relF
      guard harmonicFreq < sr / 2.0 else { break }

      let a = params.baseShape.amplitude(harmonic: nh) * pow(CoreFloat(nh), params.tilt)
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

  private nonisolated static func generateEnvelopedFreqAmpStatic(
    fundamentalHz: CoreFloat,
    params: ParamSnapshot,
    rawGenerator: (CoreFloat, ParamSnapshot) -> [CoreFloat]
  ) -> [CoreFloat] {
    guard let coeffs = params.envelopeCoefficients else {
      return rawGenerator(fundamentalHz, params)
    }

    // Generate flat spectrum
    var flatParams = params
    flatParams = ParamSnapshot(
      baseShape: .equal, tilt: 0, bandwidthCents: params.bandwidthCents,
      bwScale: params.bwScale, profileShape: params.profileShape,
      stretch: params.stretch, envelopeCoefficients: nil
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

  private nonisolated static func downsampleForDisplayStatic(_ source: [CoreFloat]) -> [DisplayPoint] {
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

  private nonisolated static func computeEnvelopeDisplayStatic(
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
