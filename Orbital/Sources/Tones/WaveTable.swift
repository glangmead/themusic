//
//  WaveTable.swift
//  Orbital
//
//  Created by Greg Langmead on 10/29/25.
//

import AVFAudio
import Foundation

func loadAudioSignal(audioURL: URL) -> (signal: [Float], rate: Double, frameCount: Int) {
  // also:
  // from scipy.io import wavfile
  // d = wavfile.read("dx117.wav")
  // list(d[1]) <-- python list of floats
  // swiftlint:disable:next force_try
  let file = try! AVAudioFile(forReading: audioURL)
  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate, channels: file.fileFormat.channelCount, interleaved: false)!
  let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(file.length))
  // swiftlint:disable:next force_try
  try! file.read(into: buf!) // You probably want better error handling
  let floatArray = Array(UnsafeBufferPointer(start: buf?.floatChannelData![0], count: Int(buf!.frameLength)))
  return (signal: floatArray, rate: file.fileFormat.sampleRate, frameCount: Int(file.length))
}

// MARK: - Wavetable Library

// All tables are 2048 samples, one complete cycle, amplitude range -1..1.
// Look up a table by name via WavetableLibrary.table(named:).
enum WavetableLibrary {
  static let tableSize = 2048

  // FM synthesis: outer = sin(x + sin(x * ratio) * depth)
  // The outer sin clamps to -1..1, so no normalization needed.
  static func fm(ratio: CoreFloat, depth: CoreFloat) -> [CoreFloat] {
    (0..<tableSize).map { i in
      let x = 2.0 * CoreFloat.pi * CoreFloat(i) / CoreFloat(tableSize)
      return sin(x + sin(x * ratio) * depth)
    }
  }

  // Additive synthesis: sum of harmonics [(harmonic number, amplitude)], normalized to -1..1.
  static func additive(harmonics: [(Int, CoreFloat)]) -> [CoreFloat] {
    var tbl = [CoreFloat](repeating: 0, count: tableSize)
    let step = 2.0 * CoreFloat.pi / CoreFloat(tableSize)
    for (h, amp) in harmonics {
      for i in 0..<tableSize {
        tbl[i] += amp * sin(CoreFloat(h) * CoreFloat(i) * step)
      }
    }
    let peak = tbl.map(abs).max() ?? 1.0
    if peak > 0 { tbl = tbl.map { $0 / peak } }
    return tbl
  }

  // Named built-in tables, computed once at startup.
  static let tables: [String: [CoreFloat]] = {
    var t = [String: [CoreFloat]]()
    t["fm_bell"] = fm(ratio: 3.5, depth: 0.7)       // classic FM bell
    t["fm_electric"] = fm(ratio: 2.0, depth: 1.5)   // electric piano character
    t["fm_metallic"] = fm(ratio: 2.756, depth: 1.0) // metallic (irrational ratio)
    t["fm_shallow"] = fm(ratio: 2.0, depth: 0.4)    // subtle FM warmth
    t["fm_deep"] = fm(ratio: 3.0, depth: 2.0)       // aggressive FM distortion
    t["bright"] = additive(harmonics: (1...8).map { ($0, 1.0 / CoreFloat($0)) })
    t["warm"] = additive(harmonics: [(1, 1.0), (2, 0.5), (3, 0.15)])
    t["organ"] = additive(harmonics: [(1, 1.0), (2, 0.8), (4, 0.6), (8, 0.3)])
    t["hollow"] = additive(harmonics: [(1, 1.0), (3, 0.5), (5, 0.2), (7, 0.1)])
    return t
  }()

  // Mutable store for externally loaded tables (e.g. from WAV files on disk).
  // Keys registered here override built-in tables.
  // Must only be written from the main thread (writers are `@MainActor`);
  // ArrowSyntax.compile() reads this from async Tasks, which is safe because
  // reads happen after the one-shot startup writes and dictionary reads don't
  // overlap with mutation in practice. `nonisolated(unsafe)` tells Swift 6 to
  // trust the documented contract instead of requiring a lock on every read.
  nonisolated(unsafe) static var userTables: [String: [CoreFloat]] = [:]

  // Returns the named table, checking userTables first, then built-ins, then a pure sine fallback.
  // Does NOT auto-load from disk — callers must pre-populate userTables (e.g. via loadCuratedTable).
  static func table(named name: String) -> [CoreFloat] {
    userTables[name] ?? tables[name] ?? fm(ratio: 1.0, depth: 0.0)
  }

  // Sorted names of all curated wavetable files in the app bundle (presets/curated_wavetables/).
  // These are the canonical keys used in userTables and in PadOscDescriptor.file.
  static let curatedTableNames: [String] = curatedTableURLs.keys.sorted()

  // URL map for curated wavetable files, keyed by display name (filename without extension).
  // Scanned once at startup from the app bundle. Use these URLs with loadCuratedTable(_:).
  static let curatedTableURLs: [String: URL] = {
    guard let dir = Bundle.main.resourceURL?
      .appendingPathComponent("presets")
      .appendingPathComponent("curated_wavetables"),
      let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    else { return [:] }
    var urls = [String: URL]()
    for file in files where file.pathExtension.lowercased() == "wav" {
      urls[file.deletingPathExtension().lastPathComponent] = file
    }
    return urls
  }()

  // Load a curated wavetable by name into userTables if not already present.
  // Call from the main thread before triggering an async preset rebuild.
  @MainActor
  static func loadCuratedTable(_ name: String) {
    guard userTables[name] == nil, let url = curatedTableURLs[name] else { return }
    userTables[name] = fromFile(url: url)
  }

  // Pre-loads every curated wavetable into userTables.
  // Call once at app startup so makeRandomPadPreset can freely pick any curated table name.
  @MainActor
  static func loadAllCuratedTables() {
    for name in curatedTableNames {
      loadCuratedTable(name)
    }
  }

  // Number of 2048-sample wavetable frames a WAV file contains.
  // Opens the file metadata only — does not decode audio.
  static func frameCount(url: URL) -> Int {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    return Int(file.length) / tableSize
  }

  // Load one wavetable frame (0-based frameIndex) from a WAV file into a [CoreFloat] table.
  // Mono-mixes by reading channel 0, normalises to ±1, falls back to a pure sine on any error.
  static func fromFile(url: URL, frameIndex: Int = 0) -> [CoreFloat] {
    guard
      let file = try? AVAudioFile(forReading: url),
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: file.fileFormat.sampleRate,
        channels: 1,
        interleaved: false
      ),
      let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(file.length)),
      (try? file.read(into: buf)) != nil,
      let data = buf.floatChannelData
    else { return fm(ratio: 1.0, depth: 0.0) }
    let signal = UnsafeBufferPointer(start: data[0], count: Int(buf.frameLength))
    let start = frameIndex * tableSize
    guard start + tableSize <= signal.count else { return fm(ratio: 1.0, depth: 0.0) }
    var slice = (0..<tableSize).map { CoreFloat(signal[start + $0]) }
    let peak = slice.map(abs).max() ?? 1.0
    if peak > 0 { slice = slice.map { $0 / peak } }
    return slice
  }
}
