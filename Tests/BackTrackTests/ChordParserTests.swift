import XCTest
@testable import BackTrackCore

final class ChordParserTests: XCTestCase {
    func testParseSimpleChords() throws {
        let c = try ChordParser.parse("C")
        XCTAssertEqual(c.display, "C")
        let am = try ChordParser.parse("Am")
        XCTAssertEqual(am.display, "Am")
    }

    func testParseSharpsAndFlats() throws {
        let fSharp = try ChordParser.parse("F#")
        XCTAssertEqual(fSharp.display, "F#")
        let bb = try ChordParser.parse("Bb")
        XCTAssertEqual(bb.rootPitchClass, 10)
    }
}
