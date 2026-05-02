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
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.modifierFlags.contains(.command) { return false }

        if state.tweakMode {
            return handleTweakMode(event: event, chars: chars)
        }

        // Belt-and-suspenders: tweak mode should already have routed
        // these via handleTweakMode above. The explicit guards here
        // are defense in depth — if anything ever causes the early
        // return at the top to be skipped, lineup nav still won't
        // fire while editing a song.
        switch event.keyCode {
        case 49: // Space
            toggleTransport()
            return true
        case 123: // Left — previous lineup item (stops playback)
            if state.tweakMode { return true }
            previousLineupItem()
            return true
        case 124: // Right — next lineup item
            if state.tweakMode { return true }
            nextLineupItem()
            return true
        case 125: // Down — previous part (only meaningful when current item is a song)
            if state.tweakMode { return true }
            if state.currentSong != nil { clock.previousPart() }
            return true
        case 126: // Up — next part (only meaningful when current item is a song)
            if state.tweakMode { return true }
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
        case "\\":
            toggleTweakMode()
            return true
        default:
            return false
        }
    }

    // Tweak mode key dispatch. Repurposes ←/→ and ↑/↓ from lineup /
    // part navigation to field cycling / cursor navigation. Space
    // and visuals controls (V, F, L) still pass through so the
    // performer can audition tweaks live. D (cycle setlist) and
    // lineup arrows are intentionally suppressed — exit tweak mode
    // first to navigate songs.
    private func handleTweakMode(event: NSEvent, chars: String) -> Bool {
        switch event.keyCode {
        case 49: // Space — still toggles transport for live preview
            toggleTransport()
            return true
        case 123: // Left — cycle focused field backwards
            cycleTweakField(forwards: false)
            return true
        case 124: // Right — cycle focused field forwards
            cycleTweakField(forwards: true)
            return true
        case 125: // Down — move cursor to next field
            moveTweakCursor(by: 1)
            return true
        case 126: // Up — move cursor to previous field
            moveTweakCursor(by: -1)
            return true
        default:
            break
        }
        switch chars {
        case "[":
            cycleTweakField(forwards: false)
            return true
        case "]":
            cycleTweakField(forwards: true)
            return true
        case "\\":
            toggleTweakMode()
            return true
        case "l":
            state.loopCurrentPart.toggle()
            return true
        case "v":
            state.visualsOpen.toggle()
            return true
        case "f":
            toggleVisualsFullScreen()
            return true
        default:
            return false
        }
    }

    // Tweak mode: structured field-list editor for the current song
    // (see ContentView's tweak column + AppState.tweakMode). Works
    // freely whether transport is playing or stopped — being able to
    // cycle values mid-playback and hear the result land is the core
    // workflow, so there's no entry guard.
    private func toggleTweakMode() {
        if state.tweakMode {
            state.tweakMode = false
            return
        }
        guard state.currentSong != nil else { return }
        state.tweakCursor = 0
        state.tweakMode = true
    }

    // MARK: - Tweak mode helpers

    private func moveTweakCursor(by delta: Int) {
        guard let song = state.currentSong else { return }
        let fields = TweakField.fields(for: song)
        guard !fields.isEmpty else { return }
        let n = fields.count
        // Clamp at both ends — wrapping the cursor would be disorienting
        // in a long field list (you'd suddenly jump from last to first).
        state.tweakCursor = max(0, min(n - 1, state.tweakCursor + delta))
    }

    private func cycleTweakField(forwards: Bool) {
        guard let song = state.currentSong else { return }
        let fields = TweakField.fields(for: song)
        guard !fields.isEmpty else { return }
        // Defensive: clamp the cursor in case an external JSON edit
        // shrunk the field count while we were on the last field.
        let cursor = max(0, min(fields.count - 1, state.tweakCursor))
        if cursor != state.tweakCursor { state.tweakCursor = cursor }
        let field = fields[cursor]
        let universe = TweakUniverse(
            kits: state.drumKitNames,
            padSounds: state.padSoundNames,
            bassSounds: state.bassSoundNames,
            visualsFiles: state.visualsLibrary
        )
        guard let updated = field.cycled(forwards: forwards, in: song, universe: universe) else { return }

        // Find the song in state.songs by source URL (a song's name
        // could in theory be ambiguous; the URL is unique).
        guard let idx = state.songs.firstIndex(where: { $0.sourceURL == song.sourceURL }) else { return }

        // Apply optimistically so the HUD reflects the change
        // immediately, then persist. Revert on save failure so the
        // disk and in-memory state stay in agreement.
        state.songs[idx] = updated
        // Rebuild the lineup right away so `state.currentSong`
        // (which reads via the lineup) returns the updated value
        // without waiting for the FileWatcher's ~1s poll cycle.
        state.rebuildLineup()
        // Swap the audio engine's loaded buffers for the field types
        // that affect playback right now (kit/pad/bass sounds). The
        // pad/bass complexity, visualizer, etc. don't need this —
        // they're read live from the song struct each tick.
        applyLiveAudioChange(field: field, song: updated)
        do {
            try SongLoader.save(updated)
            state.tweakLastSavedNote = "saved → \(field.label.lowercased()): \(field.displayValue(in: updated))"
            state.tweakLastSaved = Date()
        } catch {
            NSLog("BackTrack: tweak save failed for '\(updated.sourceURL.lastPathComponent)': \(error)")
            state.songs[idx] = song
            state.rebuildLineup()
            applyLiveAudioChange(field: field, song: song)
        }
    }

    // For sound-folder cycles (kit / padSound / bassSound), nudge
    // the audio engine to swap its loaded buffer immediately so the
    // performer hears the new sound on the very next trigger. Other
    // fields (levels, visuals, theme, etc.) don't need an explicit
    // notification — they're read off the song struct on each tick
    // (drums, pad, bass) or every render frame (visuals).
    //
    // Cycling a sound to nil ("(none)") doesn't unload the previously
    // loaded buffer; it just stops the engine from being told about a
    // new one. Matches Clock.start()'s "if let pad = song.padSound"
    // guard. The intended way to silence pad/bass is `padLevel: 0` /
    // `bassLevel: 0` per part.
    private func applyLiveAudioChange(field: TweakField, song: Song) {
        switch field {
        case .kit:
            audio.selectDrumKit(named: song.kit)
        case .padSound:
            if let pad = song.padSound { audio.selectPadSound(named: pad) }
        case .bassSound:
            if let bass = song.bassSound { audio.selectBassSound(named: bass) }
        default:
            break
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
    // Open the window first if it was closed; the small delay lets
    // SwiftUI actually materialize the NSWindow before we look it up.
    private func toggleVisualsFullScreen() {
        let wasClosed = !state.visualsOpen
        if wasClosed { state.visualsOpen = true }
        let delay: TimeInterval = wasClosed ? 0.15 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = VisualsWindow.find() else { return }
            // Belt-and-suspenders: SwiftUI's `Window` scene doesn't
            // always set the collectionBehavior + styleMask that
            // toggleFullScreen requires. WindowConfigurator inside
            // VisualsView sets these on appearance, but in case that
            // path missed (window already up before view materialized),
            // ensure they're set here too. Idempotent.
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.styleMask.insert(.resizable)
            window.toggleFullScreen(nil)
        }
    }
}

// SwiftUI's `Window` scene on macOS doesn't reliably populate
// `NSWindow.identifier` from the scene id, so identifier-based
// lookup misses the window. The title is set verbatim from the
// `Window("BackTrack Visuals", ...)` initializer and is unique in
// our app, so match on that. Identifier kept as a fallback.
enum VisualsWindow {
    static let title = "BackTrack Visuals"

    static func find() -> NSWindow? {
        NSApp.windows.first { window in
            window.title == title
                || window.identifier?.rawValue == "visuals"
        }
    }
}
