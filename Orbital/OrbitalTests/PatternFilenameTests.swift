import Testing
@testable import Orbital

@Suite(.serialized)
struct PatternFilenameTests {
  @Test("displayName strips .json and unescapes")
  func displayNameBasic() {
    #expect(PatternFilename.displayName(from: "Aurora Arpeggio.json") == "Aurora Arpeggio")
    #expect(PatternFilename.displayName(from: "plain") == "plain")
  }

  @Test("displayName unescapes fraction slash and modifier colon")
  func displayNameUnescapes() {
    // U+2215 FRACTION SLASH → /
    #expect(PatternFilename.displayName(from: "AC\u{2215}DC.json") == "AC/DC")
    // U+A789 MODIFIER LETTER COLON → :
    #expect(PatternFilename.displayName(from: "Track 1\u{A789} Intro.json") == "Track 1: Intro")
  }

  @Test("filename escapes dangerous characters and appends .json")
  func filenameEscapes() {
    #expect(PatternFilename.filename(from: "Aurora Arpeggio") == "Aurora Arpeggio.json")
    #expect(PatternFilename.filename(from: "AC/DC") == "AC\u{2215}DC.json")
    #expect(PatternFilename.filename(from: "Track 1: Intro") == "Track 1\u{A789} Intro.json")
  }

  @Test("round-trip preserves display name")
  func roundTrip() {
    let names = ["Hello World", "AC/DC", "Suite: No. 1", "Plain"]
    for name in names {
      #expect(PatternFilename.displayName(from: PatternFilename.filename(from: name)) == name)
    }
  }
}
