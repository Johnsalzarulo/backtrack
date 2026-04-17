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

    private func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }

        switch event.keyCode {
        case 49: // Space
            clock.toggleTransport()
            return true
        case 126: // Up arrow
            adjustTempo(by: 1)
            return true
        case 125: // Down arrow
            adjustTempo(by: -1)
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
            audio.loadSamples()
            state.inputDevice = AudioDevices.defaultInputName()
            state.outputDevice = AudioDevices.defaultOutputName()
            return true
        case "m":
            let next = !(state.pending.isMajor ?? state.isMajor)
            state.pending.isMajor = next
            state.keyIsMajor = next
            return true
        case "l":
            state.followDetection.toggle()
            return true
        case "1":
            state.pending.complexity = 1
            return true
        case "2":
            state.pending.complexity = 2
            return true
        case "3":
            state.pending.complexity = 3
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
            state.padLevel = AppState.cycleDown(state.padLevel)
            audio.setPadVolume(level: state.padLevel)
            return true
        case "a": setRoot(9); return true
        case "b": setRoot(11); return true
        case "c": setRoot(0); return true
        case "d": setRoot(2); return true
        case "e": setRoot(4); return true
        case "f": setRoot(5); return true
        case "g": setRoot(7); return true
        default:
            return false
        }
    }

    private func adjustTempo(by delta: Double) {
        state.tempo = max(40, min(240, state.tempo + delta))
    }

    private func setRoot(_ pc: Int) {
        state.pending.rootNote = pc
        state.keyRoot = pc
    }
}
