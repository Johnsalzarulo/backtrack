import XCTest
@testable import BackTrackCore

final class SongLoaderTests: XCTestCase {
    func testLoadValidSong() {
        let dir = fixtureURL("Songs")
        let result = SongLoader.loadAll(from: dir)
        XCTAssertEqual(result.songs.count, 1)
        XCTAssertEqual(result.songs[0].name, "Test Song")
        XCTAssertTrue(result.issues.isEmpty)
    }

    private func fixtureURL(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(relative)
    }
}
