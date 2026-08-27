import XCTest
@testable import BackTrackCore

final class SetlistLoaderTests: XCTestCase {
    func testLoadMixedSetlist() {
        let result = SetlistLoader.loadAll(from: fixtureURL("Setlists"))
        let mixed = result.setlists.first { $0.name == "Mixed Setlist" }
        XCTAssertNotNil(mixed)
        XCTAssertEqual(mixed?.items.count, 4)
    }

    private func fixtureURL(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(relative)
    }
}
