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

  // Returns the named table, falling back to a pure sine if name is unknown.
  static func table(named name: String) -> [CoreFloat] {
    tables[name] ?? fm(ratio: 1.0, depth: 0.0)
  }
}
