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

final class Coordinator: ObservableObject {
    let state: AppState
    let audio: AudioEngineController
    let clock: Clock
    let keyboard: KeyboardHandler

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
        let result = SongLoader.loadAll()
        state.songs = result.songs
        state.songIssues = result.issues
        if let first = state.songs.first {
            state.tempo = first.bpm
        }
        audio.applyMixVolumes(from: state)
        keyboard.install()
        state.outputDevice = AudioDevices.defaultOutputName()
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
    }
}
