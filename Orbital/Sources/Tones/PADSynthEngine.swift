//
//  PADSynthEngine.swift
//  Orbital
//

import Accelerate
import Foundation

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

  // SHARC instrument selection (nil = use baseShape formulas)
  var selectedInstrument: String?

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
  nonisolated static let wavetableSize = 262_144
  nonisolated static let sampleRate: CoreFloat = 44_100.0
  nonisolated static let displayPoints = 500
  nonisolated static let minFreq: CoreFloat = 20.0
  nonisolated static let maxFreq: CoreFloat = 40_000.0

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
  func generateFreqAmp(
    fundamentalHz: CoreFloat, sharcHarmonics: [CoreFloat]? = nil
  ) -> [CoreFloat] {
    let n = Self.wavetableSize
    let halfN = n / 2
    let sr = Self.sampleRate
    var maxHarmonic = Int(sr / fundamentalHz)
    if let sharc = sharcHarmonics {
      maxHarmonic = min(maxHarmonic, sharc.count)
    }
    var freqAmp = [CoreFloat](repeating: 0, count: halfN)

    for nh in 1...maxHarmonic {
      let relF = pow(CoreFloat(nh), stretch)
      let harmonicFreq = fundamentalHz * relF
      guard harmonicFreq < sr / 2.0 else { break }

      let baseAmp: CoreFloat
      if let sharc = sharcHarmonics, nh <= sharc.count {
        baseAmp = sharc[nh - 1]
      } else {
        baseAmp = baseShape.amplitude(harmonic: nh)
      }
      let a = baseAmp * pow(CoreFloat(nh), tilt)
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

    // Inverse FFT (in-place) — use withUnsafeMutableBufferPointer so the
    // pointers handed to DSPDoubleSplitComplex outlive the call.
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

    // Unpack interleaved result
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

  // MARK: - Parameter snapshots

  /// Creates a snapshot of current parameters for off-main-thread use.
  func currentParams() -> ParamSnapshot {
    ParamSnapshot(
      baseShape: baseShape, tilt: tilt, bandwidthCents: bandwidthCents,
      bwScale: bwScale, profileShape: profileShape, stretch: stretch,
      envelopeCoefficients: envelopeCoefficients,
      sharcHarmonics: nil
    )
  }

  /// Creates a ParamSnapshot with SHARC harmonics resolved for a specific MIDI note.
  func paramsForNote(midiNote: UInt8) -> ParamSnapshot {
    let harmonics: [CoreFloat]?
    if let instId = selectedInstrument,
       let inst = SharcDatabase.shared.instrument(id: instId) {
      harmonics = inst.harmonicsForMidiNote(Int(midiNote))
    } else {
      harmonics = nil
    }
    return ParamSnapshot(
      baseShape: baseShape, tilt: tilt, bandwidthCents: bandwidthCents,
      bwScale: bwScale, profileShape: profileShape, stretch: stretch,
      envelopeCoefficients: envelopeCoefficients,
      sharcHarmonics: harmonics
    )
  }

  // MARK: - Display recomputation

  /// Recomputes all display data. Call after parameter changes.
  /// Heavy computation runs off the main thread; only the final assignment is on MainActor.
  func recomputeDisplay() async {
    // Resolve SHARC harmonics for C4 (MIDI 60), the display fundamental
    let sharcHarmonics: [CoreFloat]?
    if let instId = selectedInstrument,
       let inst = SharcDatabase.shared.instrument(id: instId) {
      sharcHarmonics = inst.harmonicsForMidiNote(60)
    } else {
      sharcHarmonics = nil
    }
    let params = ParamSnapshot(
      baseShape: baseShape, tilt: tilt, bandwidthCents: bandwidthCents,
      bwScale: bwScale, profileShape: profileShape, stretch: stretch,
      envelopeCoefficients: envelopeCoefficients,
      sharcHarmonics: sharcHarmonics
    )

    let result = await Task.detached(priority: .userInitiated) {
      Self.computeDisplay(params: params)
    }.value

    freqAmp = result.rawFreqAmp
    displayFreqAmp = result.displayFreqAmp
    displayEnvelope = result.displayEnvelope
    displayProduct = result.displayProduct
    displayVersion += 1
  }
}
