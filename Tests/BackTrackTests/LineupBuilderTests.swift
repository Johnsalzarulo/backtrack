import XCTest
@testable import BackTrackCore

final class LineupBuilderTests: XCTestCase {
    func testPerformOnlySkipsNonSongs() throws {
        let dir = fixtureURL("Setlists")
        let songs = SongLoader.loadAll(from: fixtureURL("Songs")).songs
        let setlists = SetlistLoader.loadAll(from: dir).setlists
        let mixed = setlists.first { $0.name == "Mixed Setlist" }!

        let full = LineupBuilder.build(input(
            setlist: mixed,
            songs: songs,
            capabilities: .full
        ))
        XCTAssertEqual(full.lineup.count, 4)

        let perform = LineupBuilder.build(input(
            setlist: mixed,
            songs: songs,
            capabilities: .performOnly
        ))
        XCTAssertEqual(perform.lineup.count, 2)
        XCTAssertTrue(perform.lineup.allSatisfy {
            if case .song = $0 { return true }
            return false
        })
    }

    func testPerformOnlyEmptySetlistMessage() {
        let setlists = SetlistLoader.loadAll(from: fixtureURL("Setlists")).setlists
        let empty = setlists.first { $0.name == "Countdown Only" }!
        let built = LineupBuilder.build(input(
            setlist: empty,
            songs: [],
            capabilities: .performOnly
        ))
        XCTAssertTrue(built.lineup.isEmpty)
        XCTAssertTrue(LineupBuilder.performOnlySetlistIsEmpty(
            input(setlist: empty, songs: [], capabilities: .performOnly)
        ))
    }

    func testNextSongLineupIndex() throws {
        let dir = fixtureURL("Songs")
        let song = SongLoader.loadAll(from: dir).songs[0]
        let countdown = Countdown(
            sourceURL: URL(fileURLWithPath: "/tmp/c.json"),
            name: "c",
            duration: 10,
            label: Countdown.defaultLabel,
            messageInterval: Countdown.defaultMessageInterval,
            messages: [],
            style: .digital,
            visualEffect: .none,
            motif: nil
        )
        let lineup: [LineupItem] = [.countdown(countdown), .song(song)]
        XCTAssertNil(LineupBuilder.nextSongLineupIndex(in: lineup, after: 1))
        XCTAssertEqual(LineupBuilder.nextSongLineupIndex(in: [.song(song), .song(song)], after: 0), 1)
    }

    private func input(
        setlist: Setlist?,
        songs: [Song],
        capabilities: PlatformCapabilities
    ) -> LineupBuilder.Input {
        LineupBuilder.Input(
            songs: songs,
            countdowns: [],
            interstitials: [],
            audienceInteractives: [],
            activeSetlist: setlist,
            capabilities: capabilities
        )
    }

    private func fixtureURL(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(relative)
    }
}

final class PartNavigationTests: XCTestCase {
    func testWrappedIndex() {
        XCTAssertEqual(PartNavigation.wrappedIndex(current: 0, direction: 1, count: 3), 1)
        XCTAssertEqual(PartNavigation.wrappedIndex(current: 2, direction: 1, count: 3), 0)
        XCTAssertEqual(PartNavigation.wrappedIndex(current: 0, direction: -1, count: 3), 2)
    }
}
