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
        if let first = state.songs.first {
            state.tempo = first.bpm
        }
        audio.applyMixVolumes(from: state)
        keyboard.install()
        state.outputDevice = AudioDevices.defaultOutputName()

        // Poll song JSONs + countdown JSONs + patterns.json for edits so
        // the app picks up changes without a manual R press. Samples
        // are expensive to reload and change rarely, so they stay on R.
        fileWatcher = FileWatcher(
            paths: {
                var urls: [URL] = []
                let fm = FileManager.default
                for dir in [SongLoader.defaultDirectory(), CountdownLoader.defaultDirectory()] {
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
    }

    func reloadCountdowns() {
        let result = CountdownLoader.loadAll()
        state.countdowns = result.countdowns
        state.countdownIssues = result.issues
        if state.currentCountdownIndex >= state.countdowns.count {
            state.currentCountdownIndex = max(0, state.countdowns.count - 1)
        }
    }

    func reloadSongs() {
        let result = SongLoader.loadAll()
        state.songs = result.songs
        state.songIssues = result.issues

        // Re-apply in-memory pattern edits that haven't been saved yet, so
        // auto-reloads triggered by other file changes don't clobber them.
        for (key, pattern) in state.pendingPatternSaves {
            let parts = key.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let songName = String(parts[0])
            let partName = String(parts[1])
            applyPendingPattern(songName: songName, partName: partName, pattern: pattern)
        }

        // Keep the user's current song/part selection if still valid.
        if state.currentSongIndex >= state.songs.count {
            state.currentSongIndex = max(0, state.songs.count - 1)
        }
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

    private func applyPendingPattern(songName: String, partName: String, pattern: String) {
        guard let songIdx = state.songs.firstIndex(where: { $0.name == songName }),
              let existing = state.songs[songIdx].parts[partName] else { return }
        let updated = Part(
            name: existing.name,
            pattern: pattern,
            chords: existing.chords,
            repeats: existing.repeats,
            padLevel: existing.padLevel,
            bassLevel: existing.bassLevel,
            lyrics: existing.lyrics,
            visuals: existing.visuals,
            visualMode: existing.visualMode,
            visualizer: existing.visualizer
        )
        var newParts = state.songs[songIdx].parts
        newParts[partName] = updated
        let old = state.songs[songIdx]
        state.songs[songIdx] = Song(
            sourceURL: old.sourceURL,
            name: old.name,
            key: old.key,
            bpm: old.bpm,
            kit: old.kit,
            padSound: old.padSound,
            bassSound: old.bassSound,
            parts: newParts,
            structure: old.structure,
            theme: old.theme,
            visualizer: old.visualizer,
            countIn: old.countIn,
            visualEffect: old.visualEffect
        )
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
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Window("BackTrack Visuals", id: "visuals") {
            VisualsView()
                .environmentObject(coord.state)
        }
        .defaultSize(width: 800, height: 600)
    }
}
