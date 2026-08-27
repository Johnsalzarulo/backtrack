import BackTrackCore
import Combine
import Foundation

@MainActor
final class PadCoordinator: ObservableObject {
    let state = AppState()
    let audio = AudioEngineController()
    lazy var clock = Clock(state: state, audio: audio)
    lazy var show = ShowController(state: state, clock: clock)

    private let store: SandboxContentStore
    @Published var libraryImported = false
    @Published var importError: String?

    init() {
        let root = LibraryImporter.defaultSandboxRoot()
        store = SandboxContentStore(rootURL: root)
        state.platformCapabilities = .performOnly
        audio.state = state
        state.advanceLineupCursor = { [weak self] in
            self?.show.advanceAfterSongEnd()
        }
        if FileManager.default.fileExists(atPath: store.songsDirectory().path) {
            libraryImported = true
            bootstrap()
        }
    }

    var setlistIsEmpty: Bool {
        guard let setlist = state.currentSetlist else { return false }
        return LineupBuilder.performOnlySetlistIsEmpty(
            LineupBuilder.Input(
                songs: state.songs,
                countdowns: state.countdowns,
                interstitials: state.interstitials,
                audienceInteractives: state.audienceInteractives,
                activeSetlist: setlist,
                capabilities: .performOnly
            )
        )
    }

    func bootstrap() {
        audio.loadAllSamples(from: store.samplesDirectory())
        Generators.loadPatterns(from: store.patternsURL())
        reloadContent()
    }

    func reloadContent() {
        state.songs = SongLoader.loadAll(from: store.songsDirectory()).songs
        state.songIssues = SongLoader.loadAll(from: store.songsDirectory()).issues
        let setlistResult = SetlistLoader.loadAll(from: store.setlistsDirectory())
        state.setlists = setlistResult.setlists
        state.setlistIssues = setlistResult.issues
        state.rebuildLineup()
    }

    func importLibrary(from source: URL) {
        importError = nil
        do {
            try LibraryImporter.importLibrary(from: source, to: store.rootURL)
            libraryImported = true
            bootstrap()
        } catch {
            importError = error.localizedDescription
        }
    }

    func updateLibrary(from source: URL) {
        importLibrary(from: source)
    }
}
