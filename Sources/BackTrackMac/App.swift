import BackTrackCore
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Top-level wiring. Owns the single instances of AppState,
// AudioEngineController, Clock, KeyboardHandler, and the FileWatcher
// for hot-reloading song JSONs and patterns.json.
//
// BackTrackApp (the SwiftUI App) holds one Coordinator via @StateObject
// and exposes its state to views as an @EnvironmentObject. bootstrap()
// is called from .onAppear on ContentView so that initial sample /
// pattern / song load happens once the UI is ready, rather than in
// init() where failures would be harder to surface.
final class Coordinator: ObservableObject {
    let state: AppState
    let audio: AudioEngineController
    let clock: Clock
    let keyboard: KeyboardHandler

    private var fileWatcher: FileWatcher?

    init() {
        let state = AppState()
        let audio = AudioEngineController()
        audio.state = state
        let clock = Clock(state: state, audio: audio)
        let keyboard = KeyboardHandler(state: state, clock: clock, audio: audio)
        self.state = state
        self.audio = audio
        self.clock = clock
        self.keyboard = keyboard
    }

    func bootstrap() {
        audio.loadAllSamples()
        Generators.loadPatterns()
        reloadSongs()
        reloadCountdowns()
        reloadInterstitials()
        reloadAudienceInteractives()
        reloadSetlists()
        rebuildLineup()
        state.visualsLibrary = VisualsLibrary.scanAll()
        // Ensure the VideoClips directory exists so the user has an
        // obvious place to drop files. Then scan it.
        try? FileManager.default.createDirectory(
            at: VideoClipsLibrary.directory(),
            withIntermediateDirectories: true
        )
        state.videoClipsLibrary = VideoClipsLibrary.scanAll()
        // Same for Interstitials/ — created on first launch so the
        // user has a clear place to drop interstitial JSONs.
        try? FileManager.default.createDirectory(
            at: InterstitialLoader.defaultDirectory(),
            withIntermediateDirectories: true
        )
        // And AudienceInteractives/ — fourth lineup-item kind, same
        // first-launch placement.
        try? FileManager.default.createDirectory(
            at: AudienceInteractiveLoader.defaultDirectory(),
            withIntermediateDirectories: true
        )
        keyboard.install()
        state.outputDevice = AudioDevices.defaultOutputName()

        // Poll song JSONs + countdown JSONs + setlist JSONs +
        // patterns.json for edits so the app picks up changes without
        // a restart. Samples only load at launch (changing them rarely
        // happens, and reloading is expensive).
        fileWatcher = FileWatcher(
            paths: {
                var urls: [URL] = []
                let fm = FileManager.default
                for dir in [
                    SongLoader.defaultDirectory(),
                    CountdownLoader.defaultDirectory(),
                    InterstitialLoader.defaultDirectory(),
                    AudienceInteractiveLoader.defaultDirectory(),
                    SetlistLoader.defaultDirectory(),
                ] {
                    if let entries = try? fm.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: nil
                    ) {
                        urls.append(contentsOf: entries.filter { $0.pathExtension.lowercased() == "json" })
                    }
                }
                urls.append(Generators.defaultPatternsURL())
                return urls
            },
            onChange: { [weak self] in
                self?.onWatchedFilesChanged()
            }
        )
        fileWatcher?.start()
    }

    private func onWatchedFilesChanged() {
        Generators.loadPatterns()
        reloadSongs()
        reloadCountdowns()
        reloadInterstitials()
        reloadAudienceInteractives()
        reloadSetlists()
        rebuildLineup()
    }

    func reloadCountdowns() {
        let result = CountdownLoader.loadAll()
        state.countdowns = result.countdowns
        state.countdownIssues = result.issues
    }

    func reloadInterstitials() {
        let result = InterstitialLoader.loadAll()
        state.interstitials = result.interstitials
        state.interstitialIssues = result.issues
    }

    func reloadAudienceInteractives() {
        let result = AudienceInteractiveLoader.loadAll()
        state.audienceInteractives = result.interactives
        state.audienceInteractiveIssues = result.issues
    }

    func reloadSetlists() {
        let result = SetlistLoader.loadAll()
        state.setlists = result.setlists
        state.setlistIssues = result.issues
        if state.currentSetlistIndex >= state.setlists.count {
            state.currentSetlistIndex = max(0, state.setlists.count - 1)
        }
    }

    // Resolves the active setlist's refs (or falls back to all songs
    // + all countdowns when no setlist is active) and writes the
    // result to state.lineup. Called after any inventory reload and
    // after the active-setlist cursor moves.
    func rebuildLineup() {
        state.rebuildLineup()
    }

    func reloadSongs() {
        let result = SongLoader.loadAll()
        state.songs = result.songs
        state.songIssues = result.issues

        // Keep the user's current part selection if still valid. The
        // lineup-level cursor (`currentLineupIndex`) is clamped by
        // rebuildLineup() — that's invoked after this method returns.
        if let song = state.currentSong {
            if state.currentPartIndex >= song.structure.count {
                state.currentPartIndex = 0
                state.currentBar = 0
            }
        } else {
            state.currentPartIndex = 0
            state.currentBar = 0
        }
    }
}

@main
struct BackTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coord = Coordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coord.state)
                .onAppear { coord.bootstrap() }
        }
        // .contentMinSize lets the window resize freely while honoring
        // ContentView's minWidth / minHeight as the floor. Combined
        // with the maxWidth: .infinity / maxHeight: .infinity on the
        // root frame, the HUD scales up to whatever size the user
        // drags the window to.
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)

        Window("BackTrack Visuals", id: "visuals") {
            VisualsView()
                .environmentObject(coord.state)
        }
        .defaultSize(width: 800, height: 600)
    }
}
