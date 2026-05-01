import AppKit

// NSEvent local-monitor key handler for the entire app. Every hotkey
// lives in `handle(_:)` as a flat switch — keeping them all in one
// place instead of scattered across views makes the keybinding surface
// easy to audit (and the HUD's keybinding readout in ContentView stays
// in sync by eye).
//
// Monitor is installed once after bootstrap and torn down in deinit.
// Key events that the handler consumes return nil from the monitor
// closure so AppKit doesn't propagate them to the focused control
// (e.g. so Space doesn't get interpreted as a button click).
final class KeyboardHandler {
    let state: AppState
    let clock: Clock

    private var monitor: Any?

    init(state: AppState, clock: Clock) {
        self.state = state
        self.clock = clock
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
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.modifierFlags.contains(.command) { return false }

        switch event.keyCode {
        case 49: // Space
            toggleTransport()
            return true
        case 123: // Left — previous lineup item (stops playback)
            previousLineupItem()
            return true
        case 124: // Right — next lineup item
            nextLineupItem()
            return true
        case 125: // Down — previous part (only meaningful when current item is a song)
            if state.currentSong != nil { clock.previousPart() }
            return true
        case 126: // Up — next part (only meaningful when current item is a song)
            if state.currentSong != nil { clock.nextPart() }
            return true
        default:
            break
        }

        switch chars {
        case "l":
            state.loopCurrentPart.toggle()
            return true
        case "v":
            state.visualsOpen.toggle()
            return true
        case "f":
            toggleVisualsFullScreen()
            return true
        case "d":
            // Cycle the active setlist alphabetically. Stops any
            // in-flight transport, rebuilds the lineup against the
            // newly-active setlist, and resets the cursor to item 0.
            // No-op when fewer than 2 setlists exist.
            cycleSetlist()
            return true
        default:
            return false
        }
    }

    // MARK: - Lineup dispatch

    // Space — routes to whichever transport the current item uses.
    private func toggleTransport() {
        switch state.currentLineupItem {
        case .song?:
            clock.toggleTransport()
        case .countdown?:
            toggleCountdown()
        case nil:
            break
        }
    }

    // ←/→ — navigate the unified lineup.
    private func previousLineupItem() {
        selectLineupItem(at: state.currentLineupIndex - 1)
    }

    private func nextLineupItem() {
        selectLineupItem(at: state.currentLineupIndex + 1)
    }

    // Move the lineup cursor and tear down per-item state. Stops any
    // in-flight playback (regardless of item kind) and resets song-side
    // position fields. Wraps modulo at both ends.
    private func selectLineupItem(at index: Int) {
        guard !state.lineup.isEmpty else { return }
        if state.isPlaying { clock.stop() }
        stopCountdown()

        let n = state.lineup.count
        state.currentLineupIndex = ((index % n) + n) % n
        state.currentPartIndex = 0
        state.currentBar = 0
        state.pendingPartIndex = nil
    }

    // D — cycle to the next setlist alphabetically. Rebuilds the
    // lineup against the new setlist's refs and resets the cursor to
    // item 0. No-op with 0 or 1 setlist files.
    private func cycleSetlist() {
        guard state.setlists.count > 1 else { return }
        if state.isPlaying { clock.stop() }
        stopCountdown()

        let n = state.setlists.count
        state.currentSetlistIndex = (state.currentSetlistIndex + 1) % n
        state.rebuildLineup()

        state.currentLineupIndex = 0
        state.currentPartIndex = 0
        state.currentBar = 0
        state.pendingPartIndex = nil
    }

    // MARK: - Countdown transport

    // Space cycles stopped → running → paused → running → ... so the
    // performer can pause if something pops up mid-countdown without
    // losing their place. Hitting an arrow key resets to .stopped via
    // selectLineupItem.
    private func toggleCountdown() {
        guard state.currentCountdown != nil else { return }
        switch state.countdownTransport {
        case .stopped:
            state.countdownTransport = .running(startedAt: Date(), accumulated: 0)
        case .running(let startedAt, let accumulated):
            let elapsed = accumulated + Date().timeIntervalSince(startedAt)
            state.countdownTransport = .paused(elapsed: elapsed)
        case .paused(let elapsed):
            state.countdownTransport = .running(startedAt: Date(), accumulated: elapsed)
        }
    }

    private func stopCountdown() {
        state.countdownTransport = .stopped
    }

    // Put the visuals window into (or out of) macOS native full-screen.
    // The title bar auto-hides in full-screen and the window covers the
    // entire display, which is the cleanest answer for projector use.
    // Open the window first if it was closed.
    private func toggleVisualsFullScreen() {
        if !state.visualsOpen {
            state.visualsOpen = true
        }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "visuals" }) else { return }
            window.toggleFullScreen(nil)
        }
    }
}
