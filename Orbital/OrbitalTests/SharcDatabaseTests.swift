//
//  SharcDatabaseTests.swift
//  OrbitalTests
//

import Testing
@testable import Orbital

@Suite("SharcDatabase", .serialized)
struct SharcDatabaseTests {

  @Test("Database loads instruments and contains known SHARC entries")
  func loadsAllInstruments() {
    let db = SharcDatabase.shared
    // The SHARC instrument list grows over time as new analyses are imported.
    // Don't pin an exact count here — assert a sane lower bound and verify a
    // handful of well-known instruments are present.
    #expect(db.instruments.count >= 47, "expected at least 47 instruments, got \(db.instruments.count)")
    let knownIDs: Set<String> = [
      "oboe", "violin_vibrato", "cello_vibrato", "French_horn",
      "Bb_clarinet", "flute_vibrato", "trombone", "tuba"
    ]
    let actualIDs = Set(db.instruments.map(\.id))
    let missing = knownIDs.subtracting(actualIDs)
    #expect(missing.isEmpty, "missing known SHARC instruments: \(missing.sorted())")
  }

  @Test("Each instrument has at least one note")
  func instrumentsHaveNotes() {
    let db = SharcDatabase.shared
    for inst in db.instruments {
      #expect(!inst.notes.isEmpty, "\(inst.id) has no notes")
    }
  }

  @Test("Oboe A4 harmonics are normalized to 1.0 peak")
  func oboeA4Normalized() {
    let db = SharcDatabase.shared
    let oboe = db.instruments.first { $0.id == "oboe" }!
    let a4 = oboe.notes.first { $0.midiNote == 69 }!
    let peak = a4.harmonics.max() ?? 0
    #expect(abs(peak - 1.0) < 0.001, "Peak should be 1.0, got \(peak)")
  }

  @Test("Nearest note lookup finds exact match")
  func nearestNoteExactMatch() {
    let db = SharcDatabase.shared
    let oboe = db.instruments.first { $0.id == "oboe" }!
    let harmonics = oboe.harmonicsForMidiNote(69)
    #expect(!harmonics.isEmpty)
    // Oboe A4 fundamental is weaker than 2nd harmonic
    #expect(
      harmonics[0] < harmonics[1],
      "Oboe A4: fundamental (\(harmonics[0])) should be weaker than 2nd harmonic (\(harmonics[1]))"
    )
  }

  @Test("Nearest note lookup finds closest when exact not available")
  func nearestNoteInterpolates() {
    let db = SharcDatabase.shared
    let oboe = db.instruments.first { $0.id == "oboe" }!
    // MIDI 70 (A#4/Bb4) — oboe should find the nearest analyzed note
    let harmonics = oboe.harmonicsForMidiNote(70)
    #expect(!harmonics.isEmpty, "Should return harmonics for nearest available note")
  }

  @Test("Nearest note returns empty for instrument with no data")
  func emptyInstrumentReturnsEmpty() {
    let emptyInst = SharcInstrument(id: "test", displayName: "Test", notes: [])
    let harmonics = emptyInst.harmonicsForMidiNote(69)
    #expect(harmonics.isEmpty)
  }

  @Test("Instrument lookup by ID works")
  func instrumentLookupById() {
    let db = SharcDatabase.shared
    let violin = db.instrument(id: "violin_vibrato")
    #expect(violin != nil)
    #expect(violin?.displayName == "Violin")
  }

  @Test("Instrument lookup returns nil for unknown ID")
  func instrumentLookupUnknown() {
    let db = SharcDatabase.shared
    #expect(db.instrument(id: "kazoo") == nil)
  }
}
