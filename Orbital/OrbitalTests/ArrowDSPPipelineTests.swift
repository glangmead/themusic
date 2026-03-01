//
//  OrbitalTests.swift
//  OrbitalTests
//
//  Created by Greg Langmead on 9/9/25.
//

import Testing
import Foundation
@testable import Orbital

// MARK: - Test Utilities

/// A clock that returns immediately from sleep(), for use in tests.
/// This avoids real-time waits in MusicEvent.play() and MusicPattern.play().
struct ImmediateClock: Clock {
  typealias Duration = Swift.Duration
  struct Instant: InstantProtocol {
    var offset: Swift.Duration
    func advanced(by duration: Swift.Duration) -> Instant {
      Instant(offset: offset + duration)
    }
    func duration(to other: Instant) -> Swift.Duration {
      other.offset - offset
    }
    static func < (lhs: Instant, rhs: Instant) -> Bool {
      lhs.offset < rhs.offset
    }
  }
  var now: Instant { Instant(offset: .zero) }
  var minimumResolution: Swift.Duration { .zero }
  func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
    // Return immediately — no actual sleeping
  }
}

/// Renders an Arrow11 for a given number of samples, returning the output buffer.
/// Simulates the same windowed processing that ArrowChart and the real render callback use.
func renderArrow(
  _ arrow: Arrow11,
  sampleRate: CoreFloat = 44100,
  startTime: CoreFloat = 600,
  sampleCount: Int = 4410,
  windowSize: Int = 512
) -> [CoreFloat] {
  arrow.setSampleRateRecursive(rate: sampleRate)
  let dt = 1.0 / sampleRate
  var result = [CoreFloat](repeating: 0, count: sampleCount)
  var times = [CoreFloat](repeating: 0, count: sampleCount)
  for i in 0..<sampleCount {
    times[i] = startTime + CoreFloat(i) * dt
  }
  var processed = 0
  while processed < sampleCount {
    let end = min(sampleCount, processed + windowSize)
    let windowTimes = Array(times[processed..<end])
    var windowOutputs = [CoreFloat](repeating: 0, count: windowSize)
    arrow.process(inputs: windowTimes, outputs: &windowOutputs)
    for i in 0..<(end - processed) {
      result[processed + i] = windowOutputs[i]
    }
    processed = end
  }
  return result
}

/// Computes the RMS (root mean square) of a buffer.
func rms(_ buffer: [CoreFloat]) -> CoreFloat {
  guard !buffer.isEmpty else { return 0 }
  let sumOfSquares = buffer.reduce(0.0) { $0 + $1 * $1 }
  return sqrt(sumOfSquares / CoreFloat(buffer.count))
}

/// Counts zero crossings in a buffer.
func zeroCrossings(_ buffer: [CoreFloat]) -> Int {
  var count = 0
  for i in 1..<buffer.count {
    if (buffer[i - 1] >= 0 && buffer[i] < 0) || (buffer[i - 1] < 0 && buffer[i] >= 0) {
      count += 1
    }
  }
  return count
}

/// Loads a PresetSyntax from a JSON file in the OrbitalTests/Fixtures directory.
func loadPresetSyntax(_ filename: String, filePath: String = #filePath) throws -> PresetSyntax {
  let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
  let url = testsDir.appendingPathComponent("Fixtures").appendingPathComponent(filename)
  guard FileManager.default.fileExists(atPath: url.path) else {
    throw PresetLoadError.fileNotFound("Fixture not found: \(url.path)")
  }
  let data = try Data(contentsOf: url)
  return try JSONDecoder().decode(PresetSyntax.self, from: data)
}

/// Load a frozen preset fixture from OrbitalTests/Fixtures/.
func loadFixturePreset(_ filename: String, filePath: String = #filePath) throws -> PresetSyntax {
  let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
  let url = testsDir.appendingPathComponent("Fixtures").appendingPathComponent(filename)
  guard FileManager.default.fileExists(atPath: url.path) else {
    throw PresetLoadError.fileNotFound("Fixture not found: \(url.path)")
  }
  let data = try Data(contentsOf: url)
  return try JSONDecoder().decode(PresetSyntax.self, from: data)
}

enum PresetLoadError: Error {
  case fileNotFound(String)
}

/// All Arrow preset JSON filenames for structural tests (decode, compile).
let arrowPresetFiles = [
  "sine.json",
  "saw.json",
  "square.json",
  "triangle.json",
  "auroraBorealis.json",
  "5th_cluedo.json"
]

/// Presets whose sound fingerprint should remain stable.
/// auroraBorealis is tested separately via auroraBorealis_frozen.json so that
/// sound-design iteration on auroraBorealis.json doesn't break fingerprint assertions.
let fingerprintPresetFiles = [
  "sine.json",
  "saw.json",
  "square.json",
  "triangle.json",
  "5th_cluedo.json"
]

/// Build a minimal oscillator arrow: freq * t -> osc
func makeOscArrow(shape: BasicOscillator.OscShape, freq: CoreFloat = 440) -> ArrowWithHandles {
  let syntax: ArrowSyntax = .compose(arrows: [
    .prod(of: [.const(name: "freq", val: freq), .identity]),
    .osc(name: "osc", shape: shape, width: .const(name: "width", val: 1))
  ])
  return syntax.compile()
}

// MARK: - 1. Arrow Combinator Tests

@Suite("Arrow Combinators", .serialized)
struct ArrowCombinatorTests {

  @Test("ArrowConst outputs a constant value")
  func constOutput() {
    let c = ArrowConst(value: 42.0)
    let buffer = renderArrow(c, sampleCount: 10)
    for sample in buffer {
      #expect(sample == 42.0)
    }
  }

  @Test("ArrowIdentity passes through input times")
  func identityPassThrough() {
    let id = ArrowIdentity()
    let inputs: [CoreFloat] = [1.0, 2.0, 3.0, 4.0]
    var outputs = [CoreFloat](repeating: 0, count: 4)
    id.process(inputs: inputs, outputs: &outputs)
    for i in 0..<4 {
      #expect(abs(outputs[i] - inputs[i]) < 1e-10)
    }
  }

  @Test("ArrowSum adds two constants")
  func sumOfConstants() {
    let a = ArrowConst(value: 3.0)
    let b = ArrowConst(value: 7.0)
    let sum = ArrowSum(innerArrs: [a, b])
    let inputs: [CoreFloat] = [0, 0, 0]
    var outputs = [CoreFloat](repeating: 0, count: 3)
    sum.process(inputs: inputs, outputs: &outputs)
    for sample in outputs {
      #expect(abs(sample - 10.0) < 1e-10)
    }
  }

  @Test("ArrowProd multiplies two constants")
  func prodOfConstants() {
    let a = ArrowConst(value: 3.0)
    let b = ArrowConst(value: 7.0)
    let prod = ArrowProd(innerArrs: [a, b])
    let inputs: [CoreFloat] = [0, 0, 0]
    var outputs = [CoreFloat](repeating: 0, count: 3)
    prod.process(inputs: inputs, outputs: &outputs)
    for sample in outputs {
      #expect(abs(sample - 21.0) < 1e-10)
    }
  }

  @Test("AudioGate passes signal when open, silence when closed")
  func audioGateGating() {
    let c = ArrowConst(value: 5.0)
    let gate = AudioGate(innerArr: c)
    let inputs: [CoreFloat] = [0, 0, 0]
    var outputs = [CoreFloat](repeating: 0, count: 3)

    gate.isOpen = true
    gate.process(inputs: inputs, outputs: &outputs)
    #expect(outputs[0] == 5.0)

    gate.isOpen = false
    gate.process(inputs: inputs, outputs: &outputs)
    #expect(outputs[0] == 0.0)
  }

  @Test("ArrowConstOctave outputs 2^val")
  func constOctave() {
    let octave = ArrowConstOctave(value: 2.0) // 2^2 = 4
    let inputs: [CoreFloat] = [0]
    var outputs = [CoreFloat](repeating: 0, count: 1)
    octave.process(inputs: inputs, outputs: &outputs)
    #expect(abs(outputs[0] - 4.0) < 1e-10)
  }
}

// MARK: - 2. Per-Oscillator Waveform Sanity

@Suite("Oscillator Waveforms", .serialized)
struct OscillatorWaveformTests {

  @Test("Sine output is bounded to [-1, 1]")
  func sineBounded() {
    let arrow = makeOscArrow(shape: .sine)
    let buffer = renderArrow(arrow)
    let maxAbs = buffer.map { abs($0) }.max() ?? 0
    #expect(maxAbs <= 1.0001, "Sine should be in [-1,1], got max abs \(maxAbs)")
  }

  @Test("Triangle output is bounded to [-1, 1]")
  func triangleBounded() {
    let arrow = makeOscArrow(shape: .triangle)
    let buffer = renderArrow(arrow)
    let maxAbs = buffer.map { abs($0) }.max() ?? 0
    #expect(maxAbs <= 1.0001, "Triangle should be in [-1,1], got max abs \(maxAbs)")
  }

  @Test("Sawtooth output is bounded to [-1, 1]")
  func sawtoothBounded() {
    let arrow = makeOscArrow(shape: .sawtooth)
    let buffer = renderArrow(arrow)
    let maxAbs = buffer.map { abs($0) }.max() ?? 0
    #expect(maxAbs <= 1.0001, "Sawtooth should be in [-1,1], got max abs \(maxAbs)")
  }

  @Test("Square output is {-1, +1}")
  func squareValues() {
    let arrow = makeOscArrow(shape: .square)
    let buffer = renderArrow(arrow)
    for sample in buffer {
      #expect(abs(abs(sample) - 1.0) < 0.0001,
              "Square wave samples should be +/-1, got \(sample)")
    }
  }

  @Test("440 Hz sine has ~880 zero crossings per second")
  func sineZeroCrossingFrequency() {
    let arrow = makeOscArrow(shape: .sine, freq: 440)
    // Use 1 full second for accurate crossing count
    let buffer = renderArrow(arrow, sampleCount: 44100)
    let crossings = zeroCrossings(buffer)
    // 440 Hz = 880 crossings/sec (2 per cycle). Allow ±5 for edge effects.
    #expect(abs(crossings - 880) < 5,
            "Expected ~880 zero crossings, got \(crossings)")
  }

  @Test("220 Hz sine has half the zero crossings of 440 Hz")
  func frequencyDoublingHalvesCrossings() {
    let arrow220 = makeOscArrow(shape: .sine, freq: 220)
    let arrow440 = makeOscArrow(shape: .sine, freq: 440)
    let buf220 = renderArrow(arrow220, sampleCount: 44100)
    let buf440 = renderArrow(arrow440, sampleCount: 44100)
    let zc220 = zeroCrossings(buf220)
    let zc440 = zeroCrossings(buf440)
    let ratio = Double(zc440) / Double(zc220)
    #expect((ratio - 2.0) < 0.02 && (ratio - 2.0) > -0.02,
            "Expected 2:1 crossing ratio, got \(ratio)")
  }

  @Test("Noise output is in [0, 1] and has non-trivial RMS")
  func noiseBounded() {
    let arrow = makeOscArrow(shape: .noise)
    let buffer = renderArrow(arrow)
    let maxVal = buffer.max() ?? 0
    let minVal = buffer.min() ?? 0
    #expect(minVal >= -0.001, "Noise min should be >= 0, got \(minVal)")
    #expect(maxVal <= 1.001, "Noise max should be <= 1, got \(maxVal)")
    #expect(rms(buffer) > 0.1, "Noise should have non-trivial energy")
  }

  @Test("Changing freq const changes the pitch")
  func freqConstChangesPitch() {
    let syntax: ArrowSyntax = .compose(arrows: [
      .prod(of: [.const(name: "freq", val: 440), .identity]),
      .osc(name: "osc", shape: .sine, width: .const(name: "width", val: 1))
    ])
    let arrow = syntax.compile()
    let buf440 = renderArrow(arrow, sampleCount: 44100)
    let zc440 = zeroCrossings(buf440)

    // Change the freq const to 880
    arrow.namedConsts["freq"]!.first!.val = 880
    let buf880 = renderArrow(arrow, sampleCount: 44100)
    let zc880 = zeroCrossings(buf880)

    let ratio = Double(zc880) / Double(zc440)
    #expect(abs(ratio - 2.0) < 0.02,
            "Doubling freq should double zero crossings, got ratio \(ratio)")
  }
}

// MARK: - 3. ADSR Envelope Tests

@Suite("ADSR Envelope", .serialized)
struct ADSREnvelopeTests {

  @Test("ADSR starts closed at zero")
  func startsAtZero() {
    let env = ADSR(envelope: EnvelopeData(
      attackTime: 0.1, decayTime: 0.1, sustainLevel: 0.5, releaseTime: 0.1, scale: 1.0
    ))
    #expect(env.state == .closed)
    let val = env.env(0.0)
    #expect(val == 0.0)
  }

  @Test("ADSR attack ramps up from zero")
  func attackRamps() {
    let env = ADSR(envelope: EnvelopeData(
      attackTime: 1.0, decayTime: 0.5, sustainLevel: 0.5, releaseTime: 1.0, scale: 1.0
    ))
    env.noteOn(MidiNote(note: 60, velocity: 127))
    // First call sets timeOrigin; subsequent calls measure relative to it
    let originVal = env.env(100.0)  // timeOrigin = 100, relative t = 0
    let earlyVal = env.env(100.2)   // relative t = 0.2
    let midVal = env.env(100.5)     // relative t = 0.5
    let peakVal = env.env(101.0)    // relative t = 1.0 (end of attack)
    #expect(originVal == 0.0, "Should start at zero")
    #expect(earlyVal > 0, "Should ramp up during attack")
    #expect(midVal > earlyVal, "Should increase during attack")
    #expect(abs(peakVal - 1.0) < 0.01, "Should reach scale at end of attack")
  }

  @Test("ADSR sustain holds steady")
  func sustainHolds() {
    let env = ADSR(envelope: EnvelopeData(
      attackTime: 0.1, decayTime: 0.1, sustainLevel: 0.7, releaseTime: 0.5, scale: 1.0
    ))
    env.noteOn(MidiNote(note: 60, velocity: 127))
    _ = env.env(0.0)  // start
    _ = env.env(0.1)  // end of attack
    _ = env.env(0.2)  // end of decay
    let sustained1 = env.env(0.5)
    let sustained2 = env.env(1.0)
    #expect(abs(sustained1 - 0.7) < 0.05, "Sustain should hold at 0.7, got \(sustained1)")
    #expect(abs(sustained2 - 0.7) < 0.05, "Sustain should hold at 0.7, got \(sustained2)")
  }

  @Test("ADSR release decays to zero")
  func releaseDecays() {
    let env = ADSR(envelope: EnvelopeData(
      attackTime: 0.01, decayTime: 0.01, sustainLevel: 1.0, releaseTime: 1.0, scale: 1.0
    ))
    env.noteOn(MidiNote(note: 60, velocity: 127))
    _ = env.env(100.0)   // sets timeOrigin = 100
    _ = env.env(100.02)  // through attack+decay to sustain
    let sustainedVal = env.env(100.5)
    #expect(sustainedVal > 0.9, "Should be sustained near 1.0, got \(sustainedVal)")

    env.noteOff(MidiNote(note: 60, velocity: 0))
    // noteOff sets newRelease; next env() call resets timeOrigin
    let earlyRelease = env.env(200.0)  // new timeOrigin = 200, relative t = 0
    let midRelease = env.env(200.5)    // relative t = 0.5
    let lateRelease = env.env(200.9)   // relative t = 0.9
    #expect(midRelease < earlyRelease, "Release should decrease over time")
    #expect(lateRelease < midRelease, "Release should keep decreasing")
  }

  @Test("ADSR finishCallbacks fire after release completes")
  func finishCallbacksFire() {
    var finished = false
    let env = ADSR(envelope: EnvelopeData(
      attackTime: 0.01, decayTime: 0.01, sustainLevel: 1.0, releaseTime: 0.1, scale: 1.0
    ))
    env.finishCallbacks.append { finished = true }

    env.noteOn(MidiNote(note: 60, velocity: 127))
    _ = env.env(0.0)
    _ = env.env(0.02)
    env.noteOff(MidiNote(note: 60, velocity: 0))
    _ = env.env(0.03)
    #expect(!finished, "Should not be finished mid-release")
    // Process past release time
    _ = env.env(0.2)
    #expect(finished, "finishCallbacks should have fired after release completes")
  }
}

// MARK: - 4. Preset JSON Decoding and ArrowSyntax Compilation

@Suite("Preset Compilation", .serialized)
struct PresetCompilationTests {

  @Test("All arrow JSON presets decode without error",
        arguments: arrowPresetFiles)
  func presetDecodes(filename: String) throws {
    _ = try loadPresetSyntax(filename)
  }

  @Test("All arrow JSON presets compile to ArrowWithHandles with expected handles",
        arguments: arrowPresetFiles)
  func presetArrowCompiles(filename: String) throws {
    let syntax = try loadPresetSyntax(filename)
    guard let arrowSyntax = syntax.arrow else {
      Issue.record("\(filename) has no arrow field")
      return
    }
    let handles = arrowSyntax.compile(library: syntax.resolvedLibrary())
    // Every arrow preset should have an ampEnv and at least one freq const
    #expect(!handles.namedADSREnvelopes.isEmpty,
            "\(filename) should have ADSR envelopes")
    #expect(handles.namedADSREnvelopes["ampEnv"] != nil,
            "\(filename) should have an ampEnv")
    #expect(handles.namedConsts["freq"] != nil,
            "\(filename) should have a freq const")
  }

  @Test("Aurora Borealis has Chorusers in its graph")
  func auroraBorealisHasChoruser() throws {
    let syntax = try loadFixturePreset("auroraBorealis_frozen.json")
    let handles = syntax.arrow!.compile(library: syntax.resolvedLibrary())
    #expect(!handles.namedChorusers.isEmpty,
            "auroraBorealis should have at least one Choruser")
  }

  @Test("Multi-voice compilation produces merged freq consts")
  func multiVoiceHandles() throws {
    let syntax = try loadPresetSyntax("sine.json")
    // Check how many freq consts a single compile produces
    let single = syntax.arrow!.compile()
    let singleCount = single.namedConsts["freq"]?.count ?? 0
    #expect(singleCount > 0, "Should have at least one freq const")

    // Compile 4 times and merge, simulating what Preset does
    let voices = (0..<4).map { _ in syntax.arrow!.compile() }
    let merged = ArrowWithHandles(ArrowIdentity())
    _ = merged.withMergeDictsFromArrows(voices)
    let freqConsts = merged.namedConsts["freq"]
    #expect(freqConsts != nil)
    #expect(freqConsts!.count == singleCount * 4,
            "4 voices x \(singleCount) freq consts = \(singleCount * 4), got \(freqConsts!.count)")
  }
}

// MARK: - 5. Preset Sound Fingerprint Regression

@Suite("Preset Sound Fingerprints", .serialized)
struct PresetSoundFingerprintTests {

  /// Compile an ArrowSyntax from a preset, trigger envelopes, render audio.
  private func fingerprint(
    filename: String,
    freq: CoreFloat = 440,
    sampleCount: Int = 4410
  ) throws -> (rms: CoreFloat, zeroCrossings: Int) {
    let syntax = try loadPresetSyntax(filename)
    guard let arrowSyntax = syntax.arrow else {
      throw PresetLoadError.fileNotFound("No arrow in \(filename)")
    }
    let handles = arrowSyntax.compile(library: syntax.resolvedLibrary())

    // Set frequency
    if let freqConsts = handles.namedConsts["freq"] {
      for c in freqConsts { c.val = freq }
    }

    // Trigger envelopes
    let note = MidiNote(note: 69, velocity: 127)
    for (_, envs) in handles.namedADSREnvelopes {
      for env in envs { env.noteOn(note) }
    }

    let buffer = renderArrow(handles, sampleCount: sampleCount)
    return (rms: rms(buffer), zeroCrossings: zeroCrossings(buffer))
  }

  /// Fingerprint a preset loaded from any source.
  private func fingerprint(
    preset syntax: PresetSyntax,
    freq: CoreFloat = 440,
    sampleCount: Int = 4410
  ) throws -> (rms: CoreFloat, zeroCrossings: Int) {
    guard let arrowSyntax = syntax.arrow else {
      throw PresetLoadError.fileNotFound("No arrow in preset")
    }
    let handles = arrowSyntax.compile(library: syntax.resolvedLibrary())
    if let freqConsts = handles.namedConsts["freq"] {
      for c in freqConsts { c.val = freq }
    }
    let note = MidiNote(note: 69, velocity: 127)
    for (_, envs) in handles.namedADSREnvelopes {
      for env in envs { env.noteOn(note) }
    }
    let buffer = renderArrow(handles, sampleCount: sampleCount)
    return (rms: rms(buffer), zeroCrossings: zeroCrossings(buffer))
  }

  @Test("All arrow presets produce non-silent output when note is triggered",
        arguments: fingerprintPresetFiles)
  func presetProducesSound(filename: String) throws {
    let fp = try fingerprint(filename: filename)
    #expect(fp.rms > 0.001,
            "\(filename) should produce audible output, got RMS \(fp.rms)")
    #expect(fp.zeroCrossings > 10,
            "\(filename) should have zero crossings, got \(fp.zeroCrossings)")
  }

  @Test("Frozen auroraBorealis fixture produces non-silent output")
  func auroraFixtureProducesSound() throws {
    let syntax = try loadFixturePreset("auroraBorealis_frozen.json")
    let fp = try fingerprint(preset: syntax)
    #expect(fp.rms > 0.001,
            "auroraBorealis fixture should produce audible output, got RMS \(fp.rms)")
    #expect(fp.zeroCrossings > 10,
            "auroraBorealis fixture should have zero crossings, got \(fp.zeroCrossings)")
  }

  @Test("Sine preset is quieter than square preset at same frequency")
  func sineQuieterThanSquare() throws {
    let sineRMS = try fingerprint(filename: "sine.json").rms
    let squareRMS = try fingerprint(filename: "square.json").rms
    #expect(squareRMS > sineRMS,
            "Square RMS (\(squareRMS)) should exceed sine RMS (\(sineRMS))")
  }

  @Test("Choruser with multiple voices changes the output vs single voice")
  func choruserChangesSound() {
    let withoutChorus: ArrowSyntax = .compose(arrows: [
      .prod(of: [.const(name: "freq", val: 440), .identity]),
      .osc(name: "osc", shape: .sine, width: .const(name: "w", val: 1)),
      .choruser(name: "ch", valueToChorus: "freq", chorusCentRadius: 0, chorusNumVoices: 1)
    ])
    let withChorus: ArrowSyntax = .compose(arrows: [
      .prod(of: [.const(name: "freq", val: 440), .identity]),
      .osc(name: "osc", shape: .sine, width: .const(name: "w", val: 1)),
      .choruser(name: "ch", valueToChorus: "freq", chorusCentRadius: 30, chorusNumVoices: 5)
    ])
    let arrowWithout = withoutChorus.compile()
    let arrowWith = withChorus.compile()
    let bufWithout = renderArrow(arrowWithout)
    let bufWith = renderArrow(arrowWith)

    var maxDiff: CoreFloat = 0
    for i in 0..<bufWithout.count {
      maxDiff = max(maxDiff, abs(bufWith[i] - bufWithout[i]))
    }
    #expect(maxDiff > 0.01,
            "Chorus should change the waveform, max diff was \(maxDiff)")
  }

  @Test("LowPassFilter attenuates high-frequency content")
  func lowPassFilterAttenuates() {
    let rawSyntax: ArrowSyntax = .compose(arrows: [
      .prod(of: [.const(name: "freq", val: 440), .identity]),
      .osc(name: "osc", shape: .square, width: .const(name: "w", val: 1))
    ])
    let filteredSyntax: ArrowSyntax = .compose(arrows: [
      .prod(of: [.const(name: "freq", val: 440), .identity]),
      .osc(name: "osc", shape: .square, width: .const(name: "w", val: 1)),
      .lowPassFilter(name: "f", cutoff: .const(name: "cutoff", val: 500),
                     resonance: .const(name: "res", val: 0.7))
    ])
    let rawArrow = rawSyntax.compile()
    let filteredArrow = filteredSyntax.compile()
    let rawBuf = renderArrow(rawArrow)
    let filteredBuf = renderArrow(filteredArrow)

    let rawRMS = rms(rawBuf)
    let filteredRMS = rms(filteredBuf)
    #expect(filteredRMS < rawRMS,
            "Filtered RMS (\(filteredRMS)) should be less than raw RMS (\(rawRMS))")
  }
}

// MARK: - Sample Rate Sensitivity

@Suite("Sample Rate Sensitivity", .serialized)
struct SampleRateSensitivityTests {

  @Test("Aurora Borealis with fixed crossfade sounds similar at 44100 and 48000 Hz",
        arguments: [0.0, 0.5, 1.0, 1.5, 2.0])
  func auroraFixedCrossfadeAcrossSampleRates(crossfadePosition: Double) throws {
    let syntax = try loadFixturePreset("auroraBorealis_frozen.json")
    guard let arrowSyntax = syntax.arrow else {
      Issue.record("No arrow in auroraBorealis"); return
    }
    let library = syntax.resolvedLibrary()

    // Compile two independent copies
    let arrow44 = arrowSyntax.compile(library: library)
    let arrow48 = arrowSyntax.compile(library: library)

    // Set frequency and trigger envelopes
    let note = MidiNote(note: 69, velocity: 127)
    for a in [arrow44, arrow48] {
      if let freqConsts = a.namedConsts["freq"] {
        for c in freqConsts { c.val = 440 }
      }
      for (_, envs) in a.namedADSREnvelopes {
        for env in envs { env.noteOn(note) }
      }
      // Fix crossfade at the given position to eliminate NoiseSmoothStep randomness
      if let crossfaders = a.namedCrossfadersEqPow["oscCrossfade"] {
        for cf in crossfaders {
          cf.mixPointArr = ArrowConst(value: crossfadePosition)
        }
      }
    }

    // Render 0.5s at each sample rate
    let buf44 = renderArrow(arrow44, sampleRate: 44100, sampleCount: 22050)
    let buf48 = renderArrow(arrow48, sampleRate: 48000, sampleCount: 24000)

    let rms44 = rms(buf44)
    let rms48 = rms(buf48)

    // Guard against division by zero for silent buffers
    guard rms44 > 1e-10 else {
      #expect(rms48 < 1e-6, "If 44100 is silent, 48000 should also be silent")
      return
    }

    let rmsRatio = rms48 / rms44
    #expect(rmsRatio > 0.7 && rmsRatio < 1.4,
            "crossfade=\(crossfadePosition): RMS should be similar; 44100=\(rms44), 48000=\(rms48), ratio=\(rmsRatio)")
  }

  @Test("Aurora Borealis vibrato depth is similar at 44100 and 48000 Hz")
  func auroraVibratoDepthAcrossSampleRates() throws {
    let syntax = try loadFixturePreset("auroraBorealis_frozen.json")
    guard let arrowSyntax = syntax.arrow else {
      Issue.record("No arrow in auroraBorealis"); return
    }
    let library = syntax.resolvedLibrary()

    // Compile two independent copies
    let arrow44 = arrowSyntax.compile(library: library)
    let arrow48 = arrowSyntax.compile(library: library)

    let note = MidiNote(note: 69, velocity: 127)
    for a in [arrow44, arrow48] {
      if let freqConsts = a.namedConsts["freq"] {
        for c in freqConsts { c.val = 440 }
      }
      for (_, envs) in a.namedADSREnvelopes {
        for env in envs { env.noteOn(note) }
      }
      // Fix crossfade to 0.5 (square+sawtooth blend)
      if let crossfaders = a.namedCrossfadersEqPow["oscCrossfade"] {
        for cf in crossfaders {
          cf.mixPointArr = ArrowConst(value: 0.5)
        }
      }
      // Use clearly audible vibrato for diagnosis
      if let vibAmp = a.namedConsts["vibratoAmp"] {
        for c in vibAmp { c.val = 0.01 }
      }
      if let vibFreq = a.namedConsts["vibratoFreq"] {
        for c in vibFreq { c.val = 5.0 }
      }
    }

    // Render 1s starting at t=3.0 (past the 2.5s attack phase)
    let buf44 = renderArrow(arrow44, sampleRate: 44100, startTime: 3.0, sampleCount: 44100)
    let buf48 = renderArrow(arrow48, sampleRate: 48000, startTime: 3.0, sampleCount: 48000)

    // Measure RMS in ~50ms windows to capture vibrato modulation at 5 Hz (200ms period)
    func windowedRMSStats(_ buf: [CoreFloat], windowSize: Int) -> (min: CoreFloat, max: CoreFloat) {
      var minR: CoreFloat = .infinity
      var maxR: CoreFloat = 0
      var i = 0
      while i + windowSize <= buf.count {
        let window = Array(buf[i..<(i + windowSize)])
        let r = rms(window)
        if r < minR { minR = r }
        if r > maxR { maxR = r }
        i += windowSize
      }
      return (minR, maxR)
    }

    let stats44 = windowedRMSStats(buf44, windowSize: 2205)  // ~50ms at 44100
    let stats48 = windowedRMSStats(buf48, windowSize: 2400)   // ~50ms at 48000

    let depth44 = stats44.max - stats44.min
    let depth48 = stats48.max - stats48.min
    let rms44 = rms(buf44)
    let rms48 = rms(buf48)

    // RMS should be similar
    let rmsRatio = rms48 / rms44
    #expect(rmsRatio > 0.95 && rmsRatio < 1.05,
            "RMS: 44k=\(rms44), 48k=\(rms48), ratio=\(rmsRatio)")

    // Vibrato modulation depth should be similar
    if depth44 > 1e-6 {
      let depthRatio = depth48 / depth44
      #expect(depthRatio > 0.95 && depthRatio < 1.05,
              "Vibrato depth: 44k=\(depth44), 48k=\(depth48), ratio=\(depthRatio)")
    }

    // Zero crossings per second should be identical (same pitch)
    let zc44 = zeroCrossings(buf44)
    let zc48 = zeroCrossings(buf48)
    #expect(abs(zc48 - zc44) < 5,
            "Zero crossings/sec: 44k=\(zc44), 48k=\(zc48)")
  }

  @Test("NoiseSmoothStep uses correct sample rate at 48000 Hz")
  func noiseSmoothStepAt48000() {
    let nss = NoiseSmoothStep(noiseFreq: 0.5, min: 0, max: 2)

    // At default (44100), samplesPerSegment = 44100/0.5 = 88200
    var buf44 = [CoreFloat](repeating: 0, count: 1024)
    var times44 = [CoreFloat](repeating: 0, count: 1024)
    for i in 0..<1024 { times44[i] = CoreFloat(i) / 44100.0 }
    nss.process(inputs: times44, outputs: &buf44)

    // Set to 48000
    nss.setSampleRateRecursive(rate: 48000)
    var buf48 = [CoreFloat](repeating: 0, count: 1024)
    var times48 = [CoreFloat](repeating: 0, count: 1024)
    for i in 0..<1024 { times48[i] = CoreFloat(i) / 48000.0 }
    nss.process(inputs: times48, outputs: &buf48)

    // Both should produce smoothly varying values in [0, 2]
    let min48 = buf48.min() ?? 0
    let max48 = buf48.max() ?? 0
    #expect(min48 >= 0 && max48 <= 2, "NoiseSmoothStep output should be in [0, 2]")

    // At 0.5 Hz noise freq and 48000 sample rate, each segment should be 96000 samples.
    // Over 1024 samples, we should see very smooth (nearly constant) output.
    var maxDelta: CoreFloat = 0
    for i in 1..<1024 {
      maxDelta = Swift.max(maxDelta, abs(buf48[i] - buf48[i-1]))
    }
    // With 96000 samples per segment, 1024 samples is a tiny fraction,
    // so consecutive differences should be very small
    #expect(maxDelta < 0.05, "NoiseSmoothStep should be smooth within 1024 samples; maxDelta=\(maxDelta)")
  }
}

// MARK: - 7. Arrow Library Resolution

@Suite("Arrow Library", .serialized)
struct ArrowLibraryTests {

  @Test("resolveLibrary replaces a single reference")
  func singleReference() {
    let library: [String: ArrowSyntax] = [
      "myConst": .const(name: "x", val: 42)
    ]
    let arrow: ArrowSyntax = .prod(of: [
      .identity,
      .libraryArrow(name: "myConst")
    ])
    let resolved = arrow.resolveLibrary(library)
    if case .prod(let children) = resolved {
      if case .const(let name, let val) = children[1] {
        #expect(name == "x")
        #expect(val == 42)
      } else {
        Issue.record("Expected .const, got \(children[1])")
      }
    } else {
      Issue.record("Expected .prod, got \(resolved)")
    }
  }

  @Test("resolveLibrary handles transitive references")
  func transitiveReferences() {
    // A references B which references C
    let cDef: ArrowSyntax = .const(name: "c", val: 1)
    let bDef: ArrowSyntax = .prod(of: [.libraryArrow(name: "c")])
    let aDef: ArrowSyntax = .sum(of: [.libraryArrow(name: "b")])

    // Build dict in order, resolving each against the dict-so-far
    var dict = [String: ArrowSyntax]()
    dict["c"] = cDef.resolveLibrary(dict)
    dict["b"] = bDef.resolveLibrary(dict)
    dict["a"] = aDef.resolveLibrary(dict)

    // "a" should be fully resolved: sum(of: [prod(of: [const("c", 1)])])
    if case .sum(let sumChildren) = dict["a"] {
      if case .prod(let prodChildren) = sumChildren[0] {
        if case .const(let name, let val) = prodChildren[0] {
          #expect(name == "c")
          #expect(val == 1)
        } else {
          Issue.record("Expected .const")
        }
      } else {
        Issue.record("Expected .prod")
      }
    } else {
      Issue.record("Expected .sum")
    }
  }

  @Test("Library arrow compiles to working Arrow11 in one step")
  func libraryArrowCompiles() {
    let library: [String: ArrowSyntax] = [
      "osc1": .compose(arrows: [
        .prod(of: [.const(name: "freq", val: 440), .identity]),
        .osc(name: "osc", shape: .sine, width: .const(name: "w", val: 1))
      ])
    ]
    let arrow: ArrowSyntax = .prod(of: [
      .const(name: "amp", val: 1),
      .libraryArrow(name: "osc1")
    ])
    let compiled = arrow.compile(library: library)
    #expect(compiled.namedConsts["freq"] != nil, "Should have freq const from resolved library arrow")
    #expect(compiled.namedBasicOscs["osc"] != nil, "Should have osc from resolved library arrow")
  }

  @Test("auroraBorealis_frozen.json decodes and compiles with library")
  func tableKeeningLoadsAndCompiles() throws {
    let preset = try loadFixturePreset("auroraBorealis_frozen.json")
    #expect(preset.name == "Keening")
    #expect(preset.library != nil)
    #expect(preset.library?.count == 3)

    // Verify library entry names
    let names = preset.library!.flatMap { $0.keys }
    #expect(names == ["vibrato", "shapedVibrato", "freqWithVibratoTerm"])

    // Compile should succeed (resolves library + compiles arrow)
    let compiled = preset.compile(numVoices: 1, initEffects: false)
    #expect(compiled.name == "Keening")
    #expect(compiled.sound != nil, "Should have a compiled sound arrow")
  }

  @Test("Multiple references to same library entry produce independent instances")
  func independentInstances() {
    let library: [String: ArrowSyntax] = [
      "myConst": .const(name: "x", val: 10)
    ]
    let arrow: ArrowSyntax = .prod(of: [
      .libraryArrow(name: "myConst"),
      .libraryArrow(name: "myConst")
    ])
    let compiled = arrow.compile(library: library)
    // Should have two const entries for "x"
    let consts = compiled.namedConsts["x"]
    #expect(consts?.count == 2, "Two references should produce two independent const instances")
  }

  @Test("Presets without library still decode and compile")
  func presetWithoutLibrary() throws {
    let preset = try loadPresetSyntax("sine.json")
    #expect(preset.library == nil)
    let compiled = preset.compile(numVoices: 1, initEffects: false)
    #expect(compiled.sound != nil)
  }
}
