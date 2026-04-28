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
//
// For actions that mutate song JSON (Cmd+S, pattern audition via
// [ / ]), the writes go through SongLoader.save() which round-trips
// via SongJSON → pretty-printed JSON with sorted keys, so in-app saves
// produce a stable diff regardless of the source file's formatting.
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

        // Cmd+S saves unsaved in-memory pattern edits back to disk.
        if event.modifierFlags.contains(.command) {
            if chars == "s" {
                savePendingPatternEdits()
                return true
            }
            return false
        }

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
        case "l":
            state.loopCurrentPart.toggle()
            return true
        case "v":
            state.visualsOpen.toggle()
            return true
        case "f":
            toggleVisualsFullScreen()
            return true
        case "[":
            cyclePatternForCurrentPart(direction: -1)
            return true
        case "]":
            cyclePatternForCurrentPart(direction: 1)
            return true
        case "i":
            // Invert visuals theme (dark ↔ light). In-memory override;
            // resets when the user clears it or edits JSON directly.
            let current = state.effectiveTheme
            state.themeOverride = current == .dark ? .light : .dark
            return true
        case "m":
            // Cycle visualizer styles for whichever deck we're on.
            // Both decks share the +1-default-slot pattern: cycling
            // past the last named style lands on a "JSON default"
            // stop that clears the override. The visual effect of
            // clearing differs by deck — songs restore the part's
            // GIF/image/video if any; countdowns just go back to the
            // file's `style` field. Dispatch by current item kind:
            // M on a song cycles synth motifs; M on a countdown cycles
            // pie/hourglass/digital.
            switch state.currentLineupItem {
            case .song?:
                cycleSongVisualizer()
            case .countdown?:
                cycleCountdownStyle()
            case nil:
                break
            }
            return true
        case "e":
            // Cycle the post-processing visual effect. Same
            // +1-default-slot pattern as M: cycling past the last
            // named effect lands on a slot that clears the override
            // (so the active item's JSON `visualEffect` takes over
            // again).
            state.visualEffectOverride = nextStyleInCycle(
                styles: PostEffect.allCases,
                currentOverride: state.visualEffectOverride
            )
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

    // MARK: - Visualizer cycling (M key)

    // Generic +1-default-slot cycler. Given the list of known styles,
    // the index of the currently-active override (nil = sitting on
    // the default slot), it returns the next override value (nil
    // again to indicate the default slot, or one of the styles).
    private func nextStyleInCycle<T: Equatable>(
        styles: [T],
        currentOverride: T?
    ) -> T? {
        let cycleSize = styles.count + 1 // +1 for the JSON-default slot
        let currentIdx: Int
        if let current = currentOverride,
           let idx = styles.firstIndex(of: current) {
            currentIdx = idx
        } else {
            currentIdx = styles.count
        }
        let nextIdx = (currentIdx + 1) % cycleSize
        return nextIdx < styles.count ? styles[nextIdx] : nil
    }

    private func cycleSongVisualizer() {
        state.visualizerOverride = nextStyleInCycle(
            styles: VisualizerStyle.allCases,
            currentOverride: state.visualizerOverride
        )
    }

    private func cycleCountdownStyle() {
        state.countdownStyleOverride = nextStyleInCycle(
            styles: CountdownStyle.allCases,
            currentOverride: state.countdownStyleOverride
        )
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
    // in-flight playback (regardless of item kind), resets song-side
    // position fields, and clears the live overrides for visualizer /
    // theme / countdown style / visual effect — each item should play
    // as its JSON intends. Wraps modulo at both ends.
    private func selectLineupItem(at index: Int) {
        guard !state.lineup.isEmpty else { return }
        if state.isPlaying { clock.stop() }
        stopCountdown()

        let n = state.lineup.count
        state.currentLineupIndex = ((index % n) + n) % n
        state.currentPartIndex = 0
        state.currentBar = 0
        state.pendingPartIndex = nil

        // Reset tempo to the new song's BPM if applicable. Countdowns
        // don't have BPM; tempo just sits at whatever it was, which
        // doesn't matter while no song is playing.
        if let song = state.currentSong {
            state.tempo = song.bpm
        }

        clearItemOverrides()
    }

    // Clears all live per-item visual overrides. Called whenever the
    // lineup cursor moves to a new item — without this, an `M`-cycle
    // configured for one part of one song would carry over into the
    // next song / countdown, which isn't what the performer wants.
    private func clearItemOverrides() {
        state.visualizerOverride = nil
        state.themeOverride = nil
        state.countdownStyleOverride = nil
        state.visualEffectOverride = nil
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
        if let song = state.currentSong {
            state.tempo = song.bpm
        }
        clearItemOverrides()
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

    // MARK: - Pattern audition

    // Swaps the drum pattern on the current part to the next / previous one
    // in the pattern library (sorted alphabetically). Change is live — the
    // next bar plays the new pattern — and marked pending until Cmd+S.
    private func cyclePatternForCurrentPart(direction: Int) {
        guard let song = state.currentSong,
              let partName = state.currentPartName,
              let part = state.currentPart else { return }

        let allPatterns = Array(Generators.allPatternNames()).sorted()
        guard !allPatterns.isEmpty else { return }

        let currentIdx = allPatterns.firstIndex(of: part.pattern) ?? 0
        let nextIdx = ((currentIdx + direction) % allPatterns.count + allPatterns.count) % allPatterns.count
        let newPattern = allPatterns[nextIdx]
        guard newPattern != part.pattern else { return }

        applyPatternChange(songName: song.name, partName: partName, pattern: newPattern)
        state.pendingPatternSaves["\(song.name)/\(partName)"] = newPattern
    }

    // Rebuild the Song / Part structs in state.songs with the overridden
    // pattern value. Struct-heavy because Song / Part are immutable structs;
    // a reconstruction is clearer than adding class semantics.
    private func applyPatternChange(songName: String, partName: String, pattern: String) {
        guard let songIdx = state.songs.firstIndex(where: { $0.name == songName }),
              let existing = state.songs[songIdx].parts[partName] else { return }

        let updatedPart = Part(
            name: existing.name,
            pattern: pattern,
            chords: existing.chords,
            repeats: existing.repeats,
            padLevel: existing.padLevel,
            bassLevel: existing.bassLevel,
            lyrics: existing.lyrics,
            visuals: existing.visuals,
            visualMode: existing.visualMode,
            visualizer: existing.visualizer,
            visualEffect: existing.visualEffect
        )
        var newParts = state.songs[songIdx].parts
        newParts[partName] = updatedPart

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
            countIn: old.countIn
        )
    }

    // Save every song that currently has pending pattern edits, then clear
    // the pending set. File-watcher fires after the write but is a no-op
    // since state.songs already matches what we wrote.
    private func savePendingPatternEdits() {
        guard !state.pendingPatternSaves.isEmpty else { return }
        var saved = Set<String>()
        for key in state.pendingPatternSaves.keys {
            let parts = key.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let songName = String(parts[0])
            guard !saved.contains(songName),
                  let song = state.songs.first(where: { $0.name == songName }) else { continue }
            do {
                try SongLoader.save(song)
                saved.insert(songName)
            } catch {
                NSLog("BackTrack: failed to save '\(song.sourceURL.lastPathComponent)': \(error)")
            }
        }
        state.pendingPatternSaves.removeAll()
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

    private func reloadEverything() {
        audio.loadAllSamples()
        Generators.loadPatterns()
        let songResult = SongLoader.loadAll()
        state.songs = songResult.songs
        state.songIssues = songResult.issues
        let countdownResult = CountdownLoader.loadAll()
        state.countdowns = countdownResult.countdowns
        state.countdownIssues = countdownResult.issues
        let setlistResult = SetlistLoader.loadAll()
        state.setlists = setlistResult.setlists
        state.setlistIssues = setlistResult.issues
        if state.currentSetlistIndex >= state.setlists.count {
            state.currentSetlistIndex = max(0, state.setlists.count - 1)
        }
        state.rebuildLineup()
        state.outputDevice = AudioDevices.defaultOutputName()
    }
}
