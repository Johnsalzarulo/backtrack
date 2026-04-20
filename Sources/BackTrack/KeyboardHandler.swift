import AppKit

final class KeyboardHandler {
    let state: AppState
    let clock: Clock
    let audio: AudioEngineController

    private var monitor: Any?

    init(state: AppState, clock: Clock, audio: AudioEngineController) {
        self.state = state
        self.clock = clock
        self.audio = audio
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }

        switch event.keyCode {
        case 49: // Space
            clock.toggleTransport()
            return true
        case 123: // Left — previous song (stops playback)
            clock.previousSong()
            return true
        case 124: // Right — next song
            clock.nextSong()
            return true
        case 125: // Down — previous part (queued to next bar)
            clock.queuePreviousPart()
            return true
        case 126: // Up — next part (queued to next bar)
            clock.queueNextPart()
            return true
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch chars {
        case "t":
            clock.tapTempo()
            return true
        case "r":
            reloadEverything()
            return true
        case "k":
            state.kickLevel = AppState.cycleDown(state.kickLevel)
            audio.setKickVolume(level: state.kickLevel)
            return true
        case "s":
            state.snareLevel = AppState.cycleDown(state.snareLevel)
            audio.setSnareVolume(level: state.snareLevel)
            return true
        case "h":
            state.hhLevel = AppState.cycleDown(state.hhLevel)
            audio.setHhVolume(level: state.hhLevel)
            return true
        case "p":
            state.padVolume = AppState.cycleDown(state.padVolume)
            audio.setPadVolume(level: state.padVolume)
            return true
        case "b":
            state.bassVolume = AppState.cycleDown(state.bassVolume)
            audio.setBassVolume(level: state.bassVolume)
            return true
        default:
            return false
        }
    }

    private func reloadEverything() {
        audio.loadAllSamples()
        Generators.loadPatterns()
        let result = SongLoader.loadAll()
        state.songs = result.songs
        state.songIssues = result.issues
        state.outputDevice = AudioDevices.defaultOutputName()
        // Keep index in range.
        if state.currentSongIndex >= state.songs.count {
            state.currentSongIndex = max(0, state.songs.count - 1)
        }
    }
}
