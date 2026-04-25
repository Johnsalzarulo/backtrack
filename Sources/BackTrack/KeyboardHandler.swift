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
            clock.toggleTransport()
            return true
        case 123: // Left — previous song (stops playback)
            clock.previousSong()
            return true
        case 124: // Right — next song
            clock.nextSong()
            return true
        case 125: // Down — previous part (wraps; immediate when stopped, queued when playing)
            clock.previousPart()
            return true
        case 126: // Up — next part (wraps; immediate when stopped, queued when playing)
            clock.nextPart()
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
            // Cycle through visualizer motifs plus a "song default"
            // stop at the end. Landing on default clears the override,
            // which restores the part's GIF/image/video if it had one
            // (or the song's JSON visualizer otherwise). Without this
            // stop, previewing other styles on a part with a GIF would
            // hide the GIF with no way to get it back short of a
            // restart.
            let styles = VisualizerStyle.allCases
            let cycleSize = styles.count + 1  // +1 for default slot
            let currentIdx: Int
            if let current = state.visualizerOverride,
               let idx = styles.firstIndex(of: current) {
                currentIdx = idx
            } else {
                currentIdx = styles.count  // sitting on default slot
            }
            let nextIdx = (currentIdx + 1) % cycleSize
            state.visualizerOverride = nextIdx < styles.count ? styles[nextIdx] : nil
            return true
        default:
            return false
        }
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
            visualizer: existing.visualizer
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
