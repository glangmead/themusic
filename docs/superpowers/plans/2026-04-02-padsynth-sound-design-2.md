# PADsynth Sound Design 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Sound Design 2" tab implementing the PADsynth extended algorithm with an interactive frequency-domain envelope drawing feature and chord preview playback.

**Architecture:** Four new files: `PADSynthEngine.swift` (pure computation, `@Observable`), `PADSynthPlayer.swift` (AVAudioEngine playback), `PADSynthGraphView.swift` (Swift Charts with drawing overlay), `PADSynthFormView.swift` (tab layout with controls). Plus one test file and minor edits to `AppView.swift` for tab integration.

**Tech Stack:** Accelerate (vDSP FFT, LAPACK `dgels_`), Swift Charts, AVAudioEngine/AVAudioPlayerNode, SwiftUI

**Build command:** `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`

**Test command:** `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`

**Lint command:** `/opt/homebrew/bin/swiftlint --path <file> 2>&1`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Orbital/Sources/Tones/PADSynthEngine.swift` | Create | Algorithm parameters, freq_amp generation, profile functions, base shapes, polynomial fitting, IFFT, envelope application |
| `Orbital/Sources/AppleAudio/PADSynthPlayer.swift` | Create | AVAudioEngine with 4 AVAudioPlayerNodes, chord progression scheduling, 10s playback |
| `Orbital/Sources/UI/PADSynthGraphView.swift` | Create | Swift Charts frequency graph (3 layers), logarithmic axis, DragGesture drawing overlay via chartOverlay |
| `Orbital/Sources/UI/PADSynthFormView.swift` | Create | "Sound Design 2" tab — VStack with graph (60%) and Form controls (40%), Play/Clear buttons |
| `Orbital/Sources/AppView.swift` | Modify | Add 6th tab and sidebar category |
| `Orbital/OrbitalTests/PADSynthEngineTests.swift` | Create | Unit tests for engine: peaks, bandwidth, profiles, polynomial fit, envelope, wavetable |

---

### Task 1: PADSynthEngine — Parameter Types and Storage

**Files:**
- Create: `Orbital/Sources/Tones/PADSynthEngine.swift`

- [ ] **Step 1: Create PADSynthEngine.swift with enums and Observable class skeleton**

```swift
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
  var baseShape: PADBaseShape = .oneOverSqrtN
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

  // Constants
  static let wavetableSize = 262_144
  static let sampleRate: CoreFloat = 44_100.0
  static let displayPoints = 1000
  static let minFreq: CoreFloat = 20.0
  static let maxFreq: CoreFloat = 40_000.0

  struct DisplayPoint: Identifiable {
    let id: Int
    let frequency: CoreFloat
    let amplitude: CoreFloat
  }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/Tones/PADSynthEngine.swift 2>&1`
Expected: No errors. Fix any warnings.

- [ ] **Step 4: Commit**

```bash
git add Orbital/Sources/Tones/PADSynthEngine.swift
git commit -m "feat: add PADSynthEngine parameter types and Observable skeleton"
```

---

### Task 2: PADSynthEngine — Profile Function and freq_amp Generation

**Files:**
- Modify: `Orbital/Sources/Tones/PADSynthEngine.swift`
- Create: `Orbital/OrbitalTests/PADSynthEngineTests.swift`

- [ ] **Step 1: Write failing tests for profile function and freq_amp peak positions**

Create `Orbital/OrbitalTests/PADSynthEngineTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: FAIL — `profile` and `generateFreqAmp` methods don't exist yet.

- [ ] **Step 3: Implement profile function and generateFreqAmp**

Add to `PADSynthEngine` in `Orbital/Sources/Tones/PADSynthEngine.swift`:

```swift
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

      // Only iterate over bins where the profile has significant energy.
      // For Gaussian, 6 standard deviations covers > 99.99%.
      let spreadBins = max(Int(ceil(6.0 * bwi * CoreFloat(n))), 10)
      let centerBin = Int(round(fi * CoreFloat(n)))
      let lo = max(0, centerBin - spreadBins)
      let hi = min(halfN - 1, centerBin + spreadBins)

      for i in lo...hi {
        let binFreqNorm = CoreFloat(i) / CoreFloat(n)
        let hprofile = profile(fi: binFreqNorm - fi, bwi: bwi, shape: profileShape)
        freqAmp[i] += hprofile * a
      }
    }

    return freqAmp
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: All 4 tests PASS.

- [ ] **Step 5: Lint both files**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/Tones/PADSynthEngine.swift 2>&1 && /opt/homebrew/bin/swiftlint --path Orbital/OrbitalTests/PADSynthEngineTests.swift 2>&1`
Fix any issues.

- [ ] **Step 6: Commit**

```bash
git add Orbital/Sources/Tones/PADSynthEngine.swift Orbital/OrbitalTests/PADSynthEngineTests.swift
git commit -m "feat: PADSynthEngine profile functions and freq_amp generation with tests"
```

---

### Task 3: PADSynthEngine — Profile Shapes and Inharmonicity Tests

**Files:**
- Modify: `Orbital/OrbitalTests/PADSynthEngineTests.swift`

- [ ] **Step 1: Write tests for different profile shapes and inharmonicity**

Append to `PADSynthEngineTests`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: All 8 tests PASS (4 from Task 2 + 4 new).

- [ ] **Step 3: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/OrbitalTests/PADSynthEngineTests.swift 2>&1`
Fix any issues.

- [ ] **Step 4: Commit**

```bash
git add Orbital/OrbitalTests/PADSynthEngineTests.swift
git commit -m "test: add profile shape, inharmonicity, base shape, and tilt tests"
```

---

### Task 4: PADSynthEngine — Polynomial Fitting

**Files:**
- Modify: `Orbital/Sources/Tones/PADSynthEngine.swift`
- Modify: `Orbital/OrbitalTests/PADSynthEngineTests.swift`

- [ ] **Step 1: Write failing test for polynomial fitting**

Append to `PADSynthEngineTests`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: FAIL — `fitPolynomial` doesn't exist yet.

- [ ] **Step 3: Implement polynomial fitting using LAPACK**

Add to `PADSynthEngine` in `Orbital/Sources/Tones/PADSynthEngine.swift`:

```swift
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

  /// Evaluates polynomial with given coefficients at x.
  static func evaluatePolynomial(_ coeffs: [CoreFloat], at x: CoreFloat) -> CoreFloat {
    var result: CoreFloat = 0
    var xPow: CoreFloat = 1.0
    for c in coeffs {
      result += c * xPow
      xPow *= x
    }
    return result
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: All 10 tests PASS.

- [ ] **Step 5: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/Tones/PADSynthEngine.swift 2>&1`
Fix any issues.

- [ ] **Step 6: Commit**

```bash
git add Orbital/Sources/Tones/PADSynthEngine.swift Orbital/OrbitalTests/PADSynthEngineTests.swift
git commit -m "feat: polynomial fitting via LAPACK dgels_ with tests"
```

---

### Task 5: PADSynthEngine — Envelope Application and IFFT Wavetable Generation

**Files:**
- Modify: `Orbital/Sources/Tones/PADSynthEngine.swift`
- Modify: `Orbital/OrbitalTests/PADSynthEngineTests.swift`

- [ ] **Step 1: Write failing tests for envelope application and wavetable generation**

Append to `PADSynthEngineTests`:

```swift
  // MARK: - Envelope application

  @Test("Envelope multiplies freq_amp element-wise")
  func envelopeMultipliesFreqAmp() {
    let engine = PADSynthEngine()
    engine.baseShape = .equal
    engine.bandwidthCents = 50.0
    engine.stretch = 1.0

    let fundamentalHz: CoreFloat = 440.0
    let freqAmpBefore = engine.generateFreqAmp(fundamentalHz: fundamentalHz)

    // Envelope that is 0.5 everywhere: constant polynomial [0.5]
    engine.envelopeCoefficients = [0.5]
    let freqAmpAfter = engine.applyEnvelope(to: freqAmpBefore)

    // Every non-zero bin should be halved
    for i in 0..<freqAmpBefore.count where freqAmpBefore[i] > 1e-10 {
      let ratio = freqAmpAfter[i] / freqAmpBefore[i]
      #expect(abs(ratio - 0.5) < 0.01,
              "Envelope of 0.5 should halve amplitude at bin \(i)")
      break  // one check is enough
    }
  }

  @Test("No envelope leaves freq_amp unchanged")
  func noEnvelopeLeavesUnchanged() {
    let engine = PADSynthEngine()
    engine.baseShape = .oneOverSqrtN
    engine.bandwidthCents = 50.0
    engine.stretch = 1.0
    engine.envelopeCoefficients = nil

    let fundamentalHz: CoreFloat = 440.0
    let freqAmp = engine.generateFreqAmp(fundamentalHz: fundamentalHz)
    let afterEnvelope = engine.applyEnvelope(to: freqAmp)

    #expect(freqAmp.count == afterEnvelope.count)
    for i in 0..<freqAmp.count {
      #expect(freqAmp[i] == afterEnvelope[i])
    }
  }

  // MARK: - Wavetable generation

  @Test("Generated wavetable has correct length and is normalized")
  func wavetableCorrectLengthAndNormalized() async {
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: FAIL — `applyEnvelope` and `generateWavetable` don't exist yet.

- [ ] **Step 3: Implement applyEnvelope and generateWavetable (IFFT)**

Add to `PADSynthEngine` in `Orbital/Sources/Tones/PADSynthEngine.swift`:

```swift
  // MARK: - Envelope application

  /// Multiplies freqAmp by the user-drawn polynomial envelope.
  /// The polynomial is evaluated in log2-frequency space (matching the logarithmic UI axis).
  /// Returns the input unchanged if no envelope is set.
  func applyEnvelope(to freqAmp: [CoreFloat]) -> [CoreFloat] {
    guard let coeffs = envelopeCoefficients else { return freqAmp }
    let n = Self.wavetableSize
    let sr = Self.sampleRate
    let logMin = log2(Self.minFreq)
    let logMax = log2(Self.maxFreq)

    return freqAmp.enumerated().map { i, amp in
      let freqHz = CoreFloat(i) / CoreFloat(n) * sr
      guard freqHz >= Self.minFreq && freqHz <= Self.maxFreq else { return amp }
      let logFreq = log2(freqHz)
      let normalizedLogFreq = (logFreq - logMin) / (logMax - logMin) * 10.0  // map to 0..10 range
      let envValue = Self.evaluatePolynomial(coeffs, at: normalizedLogFreq)
      return amp * max(0, min(1, envValue))
    }
  }

  // MARK: - Wavetable generation (IFFT)

  /// Full pipeline: generate freq_amp, apply envelope, random phases, IFFT, normalize.
  /// Returns a wavetable of length `wavetableSize`.
  func generateWavetable(fundamentalHz: CoreFloat) -> [CoreFloat] {
    let n = Self.wavetableSize
    let halfN = n / 2

    var freqAmp = generateFreqAmp(fundamentalHz: fundamentalHz)
    freqAmp = applyEnvelope(to: freqAmp)

    // Build split complex for real IFFT
    // For vDSP real FFT: freq_amp[i] and freq_phase[i] → split complex
    // real[i] = freq_amp[i] * cos(phase[i])
    // imag[i] = freq_amp[i] * sin(phase[i])
    var realParts = [CoreFloat](repeating: 0, count: halfN)
    var imagParts = [CoreFloat](repeating: 0, count: halfN)

    for i in 0..<halfN {
      let phase = CoreFloat.random(in: 0..<(2.0 * .pi))
      realParts[i] = freqAmp[i] * cos(phase)
      imagParts[i] = freqAmp[i] * sin(phase)
    }
    // DC and Nyquist are purely real
    imagParts[0] = 0
    if halfN > 0 { imagParts[halfN - 1] = 0 }

    // vDSP real FFT setup
    let log2n = vDSP_Length(log2(CoreFloat(n)))
    guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
      return [CoreFloat](repeating: 0, count: n)
    }
    defer { vDSP_destroy_fftsetupD(fftSetup) }

    // Pack into split complex (vDSP packed format)
    var splitReal = [CoreFloat](repeating: 0, count: halfN)
    var splitImag = [CoreFloat](repeating: 0, count: halfN)

    // vDSP packed format: splitReal[0] = DC, splitImag[0] = Nyquist
    // splitReal[k] = Re(X[k]), splitImag[k] = Im(X[k]) for k = 1..halfN-1
    splitReal[0] = realParts[0]
    splitImag[0] = realParts[halfN - 1]  // Nyquist stored in imag[0]
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

    // Unpack interleaved result into output
    var output = [CoreFloat](repeating: 0, count: n)
    // After inverse real FFT, the result is stored interleaved in the split complex:
    // output[2*i] = splitReal[i], output[2*i+1] = splitImag[i]
    for i in 0..<halfN {
      output[2 * i] = splitReal[i]
      output[2 * i + 1] = splitImag[i]
    }

    // vDSP inverse FFT has a scale factor of 2. Normalize.
    var scale = 1.0 / CoreFloat(2 * n)
    vDSP_vsmulD(&output, 1, &scale, &output, 1, vDSP_Length(n))

    // Normalize to [-1, 1]
    var peak: CoreFloat = 0
    vDSP_maxmgvD(output, 1, &peak, vDSP_Length(n))
    if peak > 0 {
      var invPeak = 1.0 / peak
      vDSP_vsmulD(&output, 1, &invPeak, &output, 1, vDSP_Length(n))
    }

    return output
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' -only-testing OrbitalTests/PADSynthEngineTests 2>&1 | tail -40`
Expected: All 13 tests PASS.

- [ ] **Step 5: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/Tones/PADSynthEngine.swift 2>&1`
Fix any issues.

- [ ] **Step 6: Commit**

```bash
git add Orbital/Sources/Tones/PADSynthEngine.swift Orbital/OrbitalTests/PADSynthEngineTests.swift
git commit -m "feat: envelope application and IFFT wavetable generation with tests"
```

---

### Task 6: PADSynthEngine — Display Data and Debounced Recomputation

**Files:**
- Modify: `Orbital/Sources/Tones/PADSynthEngine.swift`

- [ ] **Step 1: Add display data computation and debouncing**

Add to `PADSynthEngine`:

```swift
  // MARK: - Display data

  /// Downsamples freq_amp to displayPoints entries using peak-hold, for chart rendering.
  /// Frequency axis is logarithmic: each display point covers an equal range in log2(freq).
  func downsampleForDisplay(_ freqAmp: [CoreFloat]) -> [DisplayPoint] {
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
      let binLo = max(0, Int(freqLo / sr * CoreFloat(n)))
      let binHi = min(freqAmp.count - 1, Int(freqHi / sr * CoreFloat(n)))

      var peak: CoreFloat = 0
      for bin in binLo...max(binLo, binHi) {
        if freqAmp[bin] > peak { peak = freqAmp[bin] }
      }

      let centerFreq = pow(2.0, logMin + (t0 + t1) / 2.0 * (logMax - logMin))
      return DisplayPoint(id: idx, frequency: centerFreq, amplitude: peak)
    }
  }

  /// Computes envelope display points from the current polynomial coefficients.
  func computeEnvelopeDisplay() -> [DisplayPoint] {
    guard let coeffs = envelopeCoefficients else { return [] }
    let logMin = log2(Self.minFreq)
    let logMax = log2(Self.maxFreq)
    let pointCount = Self.displayPoints

    return (0..<pointCount).map { idx in
      let t = (CoreFloat(idx) + 0.5) / CoreFloat(pointCount)
      let freq = pow(2.0, logMin + t * (logMax - logMin))
      let normalizedLogFreq = t * 10.0  // matches applyEnvelope mapping
      let envValue = max(0, min(1, Self.evaluatePolynomial(coeffs, at: normalizedLogFreq)))
      return DisplayPoint(id: idx, frequency: freq, amplitude: envValue)
    }
  }

  /// Recomputes all display data. Call after parameter changes.
  /// Runs the algorithm for a reference pitch (middle C = 261.63 Hz) for display purposes.
  func recomputeDisplay() async {
    let fundamentalHz: CoreFloat = 261.63
    let rawFreqAmp = generateFreqAmp(fundamentalHz: fundamentalHz)
    let envelopedFreqAmp = applyEnvelope(to: rawFreqAmp)

    freqAmp = rawFreqAmp
    displayFreqAmp = downsampleForDisplay(rawFreqAmp)
    displayEnvelope = computeEnvelopeDisplay()
    displayProduct = downsampleForDisplay(envelopedFreqAmp)
  }
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/Tones/PADSynthEngine.swift 2>&1`
Fix any issues.

- [ ] **Step 4: Commit**

```bash
git add Orbital/Sources/Tones/PADSynthEngine.swift
git commit -m "feat: display data computation with peak-hold downsampling"
```

---

### Task 7: PADSynthPlayer — Chord Progression Playback

**Files:**
- Create: `Orbital/Sources/AppleAudio/PADSynthPlayer.swift`

- [ ] **Step 1: Create PADSynthPlayer**

```swift
//
//  PADSynthPlayer.swift
//  Orbital
//

import AVFAudio
import Foundation

@MainActor @Observable
final class PADSynthPlayer {
  var isPlaying = false
  var secondsRemaining: Int = 0

  private var audioEngine: AVAudioEngine?
  private var playerNodes: [AVAudioPlayerNode] = []
  private var playbackTask: Task<Void, Never>?

  // Note fundamentals for the chord progression
  private static let noteFrequencies: [CoreFloat] = [
    261.63,  // C4
    329.63,  // E4
    392.00,  // G4
    523.25   // C5
  ]

  // Schedule: (startTime in seconds, which note indices are playing)
  private static let schedule: [(time: Double, noteIndices: [Int])] = [
    (0.0, [0]),           // C4 solo
    (2.0, [0, 1]),        // C4 + E4
    (4.0, [0, 1, 2]),     // C4 + E4 + G4
    (6.0, [0, 1, 2, 3])   // C4 + E4 + G4 + C5
  ]

  func play(engine: PADSynthEngine) {
    stop()
    isPlaying = true
    secondsRemaining = 10

    playbackTask = Task {
      // Generate wavetables for all 4 notes
      let wavetables = Self.noteFrequencies.map { freq in
        engine.generateWavetable(fundamentalHz: freq)
      }

      guard !Task.isCancelled else { return }
      await startPlayback(wavetables: wavetables)
    }
  }

  func stop() {
    playbackTask?.cancel()
    playbackTask = nil
    tearDownAudio()
    isPlaying = false
    secondsRemaining = 0
  }

  private func startPlayback(wavetables: [[CoreFloat]]) async {
    let avEngine = AVAudioEngine()
    let sampleRate = Double(PADSynthEngine.sampleRate)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let n = PADSynthEngine.wavetableSize

    var players: [AVAudioPlayerNode] = []

    for (noteIdx, wavetable) in wavetables.enumerated() {
      let player = AVAudioPlayerNode()
      avEngine.attach(player)
      avEngine.connect(player, to: avEngine.mainMixerNode, format: format)

      // Create stereo buffer: left starts at random position, right offset by N/2
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(n))!
      buffer.frameLength = UInt32(n)
      let leftChannel = buffer.floatChannelData![0]
      let rightChannel = buffer.floatChannelData![1]
      let randomStart = Int.random(in: 0..<n)

      for i in 0..<n {
        leftChannel[i] = Float(wavetable[(randomStart + i) % n])
        rightChannel[i] = Float(wavetable[(randomStart + n / 2 + i) % n])
      }

      // Schedule looping buffer but don't play yet — volume starts at 0
      player.volume = 0.0
      player.scheduleBuffer(buffer, at: nil, options: .loops)
      players.append(player)

      _ = noteIdx  // suppress unused warning
    }

    do {
      try avEngine.start()
    } catch {
      tearDownAudio()
      isPlaying = false
      return
    }

    // Start all players (volume 0 — they'll be unmuted per schedule)
    for player in players {
      player.play()
    }

    self.audioEngine = avEngine
    self.playerNodes = players

    // Run the schedule
    let startTime = ContinuousClock.now
    for entry in Self.schedule {
      let targetTime = startTime + .seconds(entry.time)
      let delay = targetTime - .now
      if delay > .zero {
        do {
          try await Task.sleep(for: delay)
        } catch { break }
      }
      guard !Task.isCancelled else { break }

      // Fade in new notes
      for idx in entry.noteIndices where players[idx].volume < 0.5 {
        players[idx].volume = 1.0
      }
    }

    // Sustain until 9.5s, then fade out
    let fadeStart = startTime + .seconds(9.5)
    let fadeDelay = fadeStart - .now
    if fadeDelay > .zero {
      do {
        try await Task.sleep(for: fadeDelay)
      } catch {
        stop()
        return
      }
    }

    guard !Task.isCancelled else { return }

    // Quick fade out (0.5s in 10 steps)
    for step in 1...10 {
      let vol = Float(1.0 - Double(step) / 10.0)
      for player in players {
        player.volume = vol
      }
      do {
        try await Task.sleep(for: .milliseconds(50))
      } catch { break }
    }

    stop()
  }

  // Countdown timer — call from a .task modifier on the view
  func startCountdown() async {
    while isPlaying && secondsRemaining > 0 {
      do {
        try await Task.sleep(for: .seconds(1))
      } catch { break }
      if isPlaying { secondsRemaining -= 1 }
    }
  }

  private func tearDownAudio() {
    for player in playerNodes {
      player.stop()
    }
    audioEngine?.stop()
    for player in playerNodes {
      audioEngine?.detach(player)
    }
    playerNodes.removeAll()
    audioEngine = nil
  }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/AppleAudio/PADSynthPlayer.swift 2>&1`
Fix any issues.

- [ ] **Step 4: Commit**

```bash
git add Orbital/Sources/AppleAudio/PADSynthPlayer.swift
git commit -m "feat: PADSynthPlayer with 4-note chord progression playback"
```

---

### Task 8: PADSynthGraphView — Swift Charts Frequency Graph with Drawing

**Files:**
- Create: `Orbital/Sources/UI/PADSynthGraphView.swift`

- [ ] **Step 1: Create PADSynthGraphView with three data layers and drawing overlay**

```swift
//
//  PADSynthGraphView.swift
//  Orbital
//

import Charts
import SwiftUI

struct PADSynthGraphView: View {
  var engine: PADSynthEngine
  @State private var touchPoints: [CGPoint] = []
  @State private var isDragging = false

  // Log-scale axis domain
  private static let freqDomain: ClosedRange<Double> = 20...40_000

  var body: some View {
    Chart {
      // Blue: raw PADsynth freq_amp
      ForEach(engine.displayFreqAmp) { point in
        AreaMark(
          x: .value("Frequency", point.frequency),
          y: .value("Amplitude", point.amplitude)
        )
        .foregroundStyle(.blue.opacity(0.3))
      }
      ForEach(engine.displayFreqAmp) { point in
        LineMark(
          x: .value("Frequency", point.frequency),
          y: .value("Amplitude", point.amplitude)
        )
        .foregroundStyle(.blue.opacity(0.7))
        .lineStyle(StrokeStyle(lineWidth: 1))
      }

      // Amber dashed: drawn envelope
      ForEach(engine.displayEnvelope) { point in
        LineMark(
          x: .value("Frequency", point.frequency),
          y: .value("Amplitude", point.amplitude)
        )
        .foregroundStyle(.orange)
        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
      }

      // Green: product (what will be heard)
      if !engine.displayProduct.isEmpty {
        ForEach(engine.displayProduct) { point in
          AreaMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(.green.opacity(0.2))
        }
        ForEach(engine.displayProduct) { point in
          LineMark(
            x: .value("Frequency", point.frequency),
            y: .value("Amplitude", point.amplitude)
          )
          .foregroundStyle(.green.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1))
        }
      }
    }
    .chartXScale(domain: Self.freqDomain, type: .log)
    .chartXAxis {
      AxisMarks(values: [20, 50, 200, 1000, 5000, 20_000, 40_000]) { value in
        AxisGridLine()
        AxisValueLabel {
          if let freq = value.as(Double.self) {
            Text(Self.formatFrequency(freq))
              .font(.caption2)
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading) { _ in
        AxisGridLine()
      }
    }
    .chartLegend(.hidden)
    .overlay(alignment: .topTrailing) {
      VStack(alignment: .leading, spacing: 4) {
        Label("PADsynth", systemImage: "minus")
          .foregroundStyle(.blue)
        Label("Envelope", systemImage: "minus")
          .foregroundStyle(.orange)
        Label("Result", systemImage: "minus")
          .foregroundStyle(.green)
      }
      .font(.caption2)
      .padding(8)
      .background(.ultraThinMaterial, in: .rect(cornerRadius: 6))
      .padding(8)
    }
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                isDragging = true
                touchPoints.append(value.location)
              }
              .onEnded { _ in
                isDragging = false
                fitEnvelopeFromTouchPoints(proxy: proxy, geometry: geometry)
              }
          )
          .overlay {
            // Show touch points during drag
            if isDragging {
              ForEach(touchPoints.indices, id: \.self) { idx in
                Circle()
                  .fill(.orange)
                  .frame(width: 4, height: 4)
                  .position(touchPoints[idx])
              }
            }
          }
      }
    }
  }

  private func fitEnvelopeFromTouchPoints(proxy: ChartProxy, geometry: GeometryProxy) {
    let plotFrame = geometry[proxy.plotFrame!]
    let logMin = log2(PADSynthEngine.minFreq)
    let logMax = log2(PADSynthEngine.maxFreq)

    let points: [(x: CoreFloat, y: CoreFloat)] = touchPoints.compactMap { point in
      // Convert screen x to frequency via chart proxy
      guard let freq: Double = proxy.value(atX: point.x - plotFrame.minX) else { return nil }
      guard freq >= PADSynthEngine.minFreq && freq <= PADSynthEngine.maxFreq else { return nil }

      // Convert screen y to amplitude (top = 1.0, bottom = 0.0)
      let normalizedY = 1.0 - ((point.y - plotFrame.minY) / plotFrame.height)
      let amplitude = max(0, min(1, normalizedY))

      // Map frequency to the 0..10 range used by the polynomial (log space)
      let logFreq = log2(freq)
      let normalizedLogFreq = (logFreq - logMin) / (logMax - logMin) * 10.0

      return (x: normalizedLogFreq, y: amplitude)
    }

    touchPoints.removeAll()

    guard points.count >= 2 else { return }
    engine.envelopeCoefficients = PADSynthEngine.fitPolynomial(points: points, degree: 20)

    Task {
      await engine.recomputeDisplay()
    }
  }

  private static func formatFrequency(_ freq: Double) -> String {
    if freq >= 1000 {
      return "\(Int(freq / 1000))k"
    }
    return "\(Int(freq))"
  }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/UI/PADSynthGraphView.swift 2>&1`
Fix any issues.

- [ ] **Step 4: Commit**

```bash
git add Orbital/Sources/UI/PADSynthGraphView.swift
git commit -m "feat: PADSynthGraphView with Swift Charts and drawing overlay"
```

---

### Task 9: PADSynthFormView — Tab Layout with Controls

**Files:**
- Create: `Orbital/Sources/UI/PADSynthFormView.swift`

- [ ] **Step 1: Create PADSynthFormView with graph and all parameter controls**

```swift
//
//  PADSynthFormView.swift
//  Orbital
//

import SwiftUI

struct PADSynthFormView: View {
  @State private var engine = PADSynthEngine()
  @State private var player = PADSynthPlayer()
  @State private var recomputeTask: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Top 60%: frequency graph
        PADSynthGraphView(engine: engine)
          .padding(8)
          .background(.black.opacity(0.05))
          .frame(maxHeight: .infinity)
          .layoutPriority(6)

        // Bottom 40%: controls
        controlsSection
          .frame(maxHeight: .infinity)
          .layoutPriority(4)
      }
      .navigationTitle("Sound Design 2")
      .task {
        await engine.recomputeDisplay()
      }
      .onChange(of: engine.baseShape) { scheduleRecompute() }
      .onChange(of: engine.tilt) { scheduleRecompute() }
      .onChange(of: engine.bandwidthCents) { scheduleRecompute() }
      .onChange(of: engine.bwScale) { scheduleRecompute() }
      .onChange(of: engine.profileShape) { scheduleRecompute() }
      .onChange(of: engine.stretch) { scheduleRecompute() }
    }
  }

  private var controlsSection: some View {
    Form {
      Section("Harmonics") {
        Picker("Base shape", selection: $engine.baseShape) {
          ForEach(PADBaseShape.allCases) { shape in
            Text(shape.rawValue).tag(shape)
          }
        }
        LabeledSlider(value: $engine.tilt, label: "Tilt", range: -2.0...2.0, step: 0.1)
      }

      Section("Bandwidth") {
        LabeledSlider(value: $engine.bandwidthCents, label: "Bandwidth (cents)", range: 1...200, step: 1)
        LabeledSlider(value: $engine.bwScale, label: "BW scale", range: 0.5...2.0, step: 0.05)
        Picker("Profile", selection: $engine.profileShape) {
          ForEach(PADProfileShape.allCases) { profile in
            Text(profile.rawValue).tag(profile)
          }
        }
      }

      Section("Overtones") {
        Picker("Preset", selection: $engine.overtonePreset) {
          ForEach(PADOvertonePreset.allCases) { preset in
            Text(preset.rawValue).tag(preset)
          }
        }
        .onChange(of: engine.overtonePreset) { _, newPreset in
          engine.stretch = newPreset.stretchValue
        }
        LabeledSlider(value: $engine.stretch, label: "Stretch", range: 0.9...1.5, step: 0.01)
      }

      Section {
        HStack {
          Button {
            if player.isPlaying {
              player.stop()
            } else {
              player.play(engine: engine)
            }
          } label: {
            Label(
              player.isPlaying ? "Stop (\(player.secondsRemaining)s)" : "Play 10s",
              systemImage: player.isPlaying ? "stop.fill" : "play.fill"
            )
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .task(id: player.isPlaying) {
            if player.isPlaying {
              await player.startCountdown()
            }
          }

          Button {
            engine.envelopeCoefficients = nil
            scheduleRecompute()
          } label: {
            Label("Clear", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
          .disabled(engine.envelopeCoefficients == nil)
        }
      }
    }
  }

  private func scheduleRecompute() {
    recomputeTask?.cancel()
    recomputeTask = Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      await engine.recomputeDisplay()
    }
  }
}

#Preview {
  PADSynthFormView()
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/UI/PADSynthFormView.swift 2>&1`
Fix any issues.

- [ ] **Step 4: Commit**

```bash
git add Orbital/Sources/UI/PADSynthFormView.swift
git commit -m "feat: PADSynthFormView tab with controls and debounced recomputation"
```

---

### Task 10: AppView Integration — Add Sound Design 2 Tab

**Files:**
- Modify: `Orbital/Sources/AppView.swift`

- [ ] **Step 1: Add the 6th tab to CompactAppLayout**

In `AppView.swift`, inside the `TabView` in `CompactAppLayout`, after the existing "Sound design" tab (line 53), add:

```swift
      Tab("Sound design 2", systemImage: "waveform.path.ecg") {
        PADSynthFormView()
      }
```

- [ ] **Step 2: Add to SidebarCategory enum**

Add a new case to the `SidebarCategory` enum:

```swift
  case soundDesign2 = "Sound Design 2"
```

And add its system image in the `systemImage` computed property:

```swift
    case .soundDesign2: "waveform.path.ecg"
```

- [ ] **Step 3: Add to RegularAppLayout detail view**

In the `detailForCategory` computed property, add a case:

```swift
    case .soundDesign2:
      PADSynthFormView()
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Lint**

Run: `/opt/homebrew/bin/swiftlint --path Orbital/Sources/AppView.swift 2>&1`
Fix any issues.

- [ ] **Step 6: Run all project tests to verify nothing is broken**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -40`
Expected: All tests PASS, including the new PADSynthEngineTests.

- [ ] **Step 7: Commit**

```bash
git add Orbital/Sources/AppView.swift
git commit -m "feat: add Sound Design 2 tab to AppView"
```

---

### Task 11: Final Verification and Cleanup

- [ ] **Step 1: Lint all new files**

```bash
/opt/homebrew/bin/swiftlint --path Orbital/Sources/Tones/PADSynthEngine.swift 2>&1
/opt/homebrew/bin/swiftlint --path Orbital/Sources/AppleAudio/PADSynthPlayer.swift 2>&1
/opt/homebrew/bin/swiftlint --path Orbital/Sources/UI/PADSynthGraphView.swift 2>&1
/opt/homebrew/bin/swiftlint --path Orbital/Sources/UI/PADSynthFormView.swift 2>&1
/opt/homebrew/bin/swiftlint --path Orbital/Sources/AppView.swift 2>&1
/opt/homebrew/bin/swiftlint --path Orbital/OrbitalTests/PADSynthEngineTests.swift 2>&1
```

Fix any remaining issues.

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild test -project Orbital/Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,id=242EF6EA-5B26-4E1E-AB66-ED5BDB6FF8C5' 2>&1 | tail -40`
Expected: All tests PASS.

- [ ] **Step 3: Verify new files are added to Xcode project**

If using Xcode's automatic file discovery, the new `.swift` files should be picked up. If not, they need to be added to the Orbital target in the `.xcodeproj`. Check that the build in Step 2 compiled them.

- [ ] **Step 4: Commit any cleanup**

```bash
git add -A
git commit -m "chore: final lint fixes and cleanup for PADsynth Sound Design 2"
```
