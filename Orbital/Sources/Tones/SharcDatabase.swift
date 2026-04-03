//
//  SharcDatabase.swift
//  Orbital
//
//  SHARC Timbre Dataset — per-harmonic amplitude data for 39 orchestral instruments.
//  Data from https://github.com/gregsandell/sharc, preprocessed into a single JSON.
//

import Foundation

struct SharcNote: Codable, Sendable {
  let midiNote: Int
  let harmonics: [CoreFloat]
}

struct SharcInstrument: Codable, Sendable, Identifiable {
  let id: String
  let displayName: String
  let notes: [SharcNote]

  /// Returns normalized harmonic amplitudes for the nearest analyzed pitch
  /// to the given MIDI note number. Returns empty array if no notes exist.
  func harmonicsForMidiNote(_ midi: Int) -> [CoreFloat] {
    guard let nearest = notes.min(by: {
      abs($0.midiNote - midi) < abs($1.midiNote - midi)
    }) else {
      return []
    }
    return nearest.harmonics
  }
}

struct SharcDatabase: Codable, Sendable {
  let instruments: [SharcInstrument]

  static let shared: SharcDatabase = Bundle.main.decode(
    SharcDatabase.self, from: "sharc_instruments.json"
  )

  func instrument(id: String) -> SharcInstrument? {
    instruments.first { $0.id == id }
  }
}
