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
    private var resignObserver: NSObjectProtocol?

    // Pending auto-advance for an interstitial that has a `duration`
    // set. Cancelled whenever the lineup cursor moves (so navigating
    // away early doesn't trigger an unrelated nav after the timer
    // fires). Video interstitials don't use this — they auto-advance
    // via the AVPlayer's didPlayToEndTime callback instead.
    private var interstitialAutoAdvance: DispatchWorkItem?

    // Pending revert for an audience-triggered song effect (the "1"
    // key during a song). Cancelled + rescheduled on each press so a
    // rapid double-tap cycles forward without ever timing out, and
    // cancelled on lineup-cursor moves so a drifting timer doesn't
    // clear an override on the *next* item.
    private var songEffectAutoRevert: DispatchWorkItem?

    // How long an audience-triggered effect stays on screen before
    // reverting to whatever the part's JSON specifies. Short enough
    // that the effect feels like a "moment", long enough that a slow
    // press-press-press still cycles each step visibly.
    private static let songEffectHoldSeconds: TimeInterval = 10

    init(state: AppState, clock: Clock, audio: AudioEngineController) {
        self.state = state
        self.clock = clock
        self.audio = audio
        // Bridge the closure VisualsView calls when an interstitial's
        // timer or video runs out. Captures self weakly so this
        // doesn't keep KeyboardHandler alive past app teardown.
        state.advanceLineupCursor = { [weak self] in
            self?.nextLineupItem()
        }
    }

    func install() {
        guard monitor == nil else { return }
        // Listen for both keyDown AND keyUp so the green-button
        // ("2") momentary-hold telemetry can release on key release.
        // Every other shortcut is keyDown-only and ignores keyUp via
        // the early return in handleUp.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return event }
            switch event.type {
            case .keyDown:
                return self.handle(event) ? nil : event
            case .keyUp:
                return self.handleUp(event) ? nil : event
            default:
                return event
            }
        }
        // Safety net: if the app loses focus while a momentary key
        // (the green button "2") is held, we'll never see the
        // matching keyUp because local monitors only fire while the
        // app is frontmost. Force-release on resign so the telemetry
        // panel doesn't get stuck on screen.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Force-release any momentary state on focus loss.
            // Currently just the telemetry panel; if we add more
            // held-key features they should also reset here.
            guard let self = self else { return }
            if self.state.telemetryHeldDown {
                self.state.telemetryHeldDown = false
            }
        }
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        if let token = resignObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // Handles .keyUp events. Almost every shortcut is fire-on-keyDown
    // and ignores release; the one exception is the green-button
    // momentary-hold ("2"), which uses release to dismiss the
    // telemetry panel. Returns true when consumed.
    private func handleUp(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if chars == "2", state.telemetryHeldDown {
            state.telemetryHeldDown = false
            return true
        }
        return false
    }

    private func handle(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.modifierFlags.contains(.command) { return false }

        // OS key-repeat fires keyDown over and over while a key is
        // held. For momentary-hold features (telemetry panel) we want
        // exactly one transition into the held state — ignore repeats
        // for "2" specifically. Other shortcuts pass through to the
        // normal switch (a held arrow can validly walk the lineup).
        if event.isARepeat && chars == "2" {
            return state.telemetryHeldDown
        }

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
        case "1":
            // Audience-facing red button. Behavior depends on what's
            // currently on stage:
            //   - song:                cycle a temporary post-effect
            //                          (auto-reverts after ~10s so
            //                          audience-triggered effects feel
            //                          like a moment, not a takeover)
            //   - countdown:           cycle the render style
            //                          indefinitely until the lineup
            //                          cursor moves
            //   - audience-interactive: kind-specific. start_button
            //                          flags this as the wrong button
            //                          (system beep + "WRONG BUTTON"
            //                          flash for ~1.5s)
            //   - anything else:       no-op
            if state.currentSong != nil {
                // Suppress while a videoClip is taking over the visuals
                // window — the clip IS the song's intentional moment
                // (e.g. Core of the Onion's intro), so layering an
                // audience-triggered effect on top would step on the
                // joke. Same suppression while the audience is holding
                // the green button — that interaction owns the screen.
                if state.activeVideoClip != nil { return true }
                if state.telemetryHeldDown { return true }
                cycleSongEffect()
                return true
            }
            if state.currentCountdown != nil {
                cycleCountdownStyle()
                return true
            }
            if state.currentAudienceInteractive != nil {
                handleAudienceInteractiveRed()
                return true
            }
            return false
        case "2":
            // Audience-facing green button. Behavior depends on what's
            // currently on stage:
            //   - song:                hold-to-show telemetry panel
            //                          (momentary). Suppressed during
            //                          videoClips.
            //   - countdown:           tap to advance the rotating
            //                          message.
            //   - audience-interactive: kind-specific. start_button
            //                          advances the lineup to the
            //                          next item ("show is starting").
            //   - anything else:       no-op.
            if state.currentSong != nil {
                if state.activeVideoClip != nil { return true }
                state.telemetryHeldDown = true
                return true
            }
            if state.currentCountdown != nil {
                advanceCountdownMessage()
                return true
            }
            if state.currentAudienceInteractive != nil {
                handleAudienceInteractiveGreen()
                return true
            }
            return false
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
            visualsFiles: state.visualsLibrary,
            // Sorted so cycling order is stable + alphabetical
            // regardless of patterns.json's internal ordering.
            patternNames: Array(Generators.allPatternNames()).sorted(),
            videoClipsFiles: state.videoClipsLibrary
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
        case .interstitial?:
            // Interstitials show their content the moment the cursor
            // lands on them — there's nothing for Space to start.
            // (Video pause/resume could go here later if useful.)
            break
        case .audienceInteractive(let a)?:
            // Space mirrors whichever button is the "advance" action
            // for this kind, so the operator can also drive the show
            // forward from the keyboard. For start_button, that's
            // green (advance). New kinds may differ — extend here as
            // they're added.
            switch a.kind {
            case .startButton:
                nextLineupItem()
            }
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
    // position fields. Wraps modulo at both ends. Also (re)schedules
    // any auto-advance the new item needs.
    private func selectLineupItem(at index: Int) {
        guard !state.lineup.isEmpty else { return }
        if state.isPlaying { clock.stop() }
        stopCountdown()
        cancelInterstitialAutoAdvance()

        let n = state.lineup.count
        state.currentLineupIndex = ((index % n) + n) % n
        state.currentPartIndex = 0
        state.currentBar = 0
        state.pendingPartIndex = nil
        // Audience-button overrides ("1" / "2") are scoped to the
        // active item — moving the cursor wipes them so the next
        // item starts at its JSON-defined defaults.
        state.countdownStyleOverride = nil
        state.countdownMessageOffset = 0
        state.telemetryHeldDown = false
        state.wrongButtonAt = .distantPast
        clearSongEffectOverride()

        scheduleInterstitialAutoAdvanceIfNeeded()
    }

    // Text/image interstitials with a `duration` field auto-advance
    // to the next lineup item after that many seconds. Video kind
    // doesn't use this path — its auto-advance fires off the
    // AVPlayer's didPlayToEndTime in VisualsView.
    private func scheduleInterstitialAutoAdvanceIfNeeded() {
        guard let inter = state.currentInterstitial,
              let duration = inter.duration else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.nextLineupItem()
        }
        interstitialAutoAdvance = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelInterstitialAutoAdvance() {
        interstitialAutoAdvance?.cancel()
        interstitialAutoAdvance = nil
    }

    // D — cycle to the next setlist alphabetically. Rebuilds the
    // lineup against the new setlist's refs and resets the cursor to
    // item 0. No-op with 0 or 1 setlist files.
    private func cycleSetlist() {
        guard state.setlists.count > 1 else { return }
        if state.isPlaying { clock.stop() }
        stopCountdown()
        cancelInterstitialAutoAdvance()

        let n = state.setlists.count
        state.currentSetlistIndex = (state.currentSetlistIndex + 1) % n
        state.rebuildLineup()

        state.currentLineupIndex = 0
        state.currentPartIndex = 0
        state.currentBar = 0
        state.pendingPartIndex = nil

        scheduleInterstitialAutoAdvanceIfNeeded()
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

    // "1" key — cycle the active countdown's style through
    // CountdownStyle.allCases. Sets an in-memory override on AppState
    // (the JSON `style` is left alone); the override gets cleared the
    // moment the lineup cursor moves so each countdown starts fresh.
    private func cycleCountdownStyle() {
        let current = state.effectiveCountdownStyle
        let cases = CountdownStyle.allCases
        guard let idx = cases.firstIndex(of: current) else {
            state.countdownStyleOverride = cases.first
            return
        }
        state.countdownStyleOverride = cases[(idx + 1) % cases.count]
    }

    // "2" key — bump the message-rotation offset by 1, which makes
    // CountdownView immediately render the next entry in the
    // countdown's `messages` array. No-op when there are no messages
    // (the offset would have nowhere to point).
    private func advanceCountdownMessage() {
        guard let countdown = state.currentCountdown,
              !countdown.messages.isEmpty else { return }
        state.countdownMessageOffset += 1
    }

    // "1" key during a song — cycle to the next post-effect from the
    // currently-effective one and arm a 10s revert. Skips .none so
    // every press shows something visibly different from the part's
    // resting state; .none would just return to "no effect" which the
    // auto-revert already handles for free. Each press cancels the
    // previous revert and arms a fresh one, so rapid presses cycle
    // through forever without ever timing out mid-cycle.
    private func cycleSongEffect() {
        let cycle: [PostEffect] = [.glitch, .tracking, .chroma]
        let current = state.effectiveVisualEffect
        let next: PostEffect
        if let idx = cycle.firstIndex(of: current) {
            next = cycle[(idx + 1) % cycle.count]
        } else {
            // Current is .none (or something not in the audience cycle)
            // — start from the first option.
            next = cycle.first ?? .glitch
        }
        state.songEffectOverride = next
        // Stamp the flash timestamp so VisualsView's overlay reads
        // "press confirmed" — this is the only visual feedback for an
        // audience press that happens to land on the same effect as
        // the part's JSON default (which would otherwise look like a
        // no-op even though the override is now active).
        state.audienceFlashTriggeredAt = Date()
        // Stamp the wall-clock deadline so the telemetry panel can
        // show a live "Xs remaining" countdown alongside the override.
        state.songEffectExpiresAt = Date().addingTimeInterval(Self.songEffectHoldSeconds)

        // Cancel-and-rearm the auto-revert. A pending work item from
        // the previous press would otherwise fire mid-cycle and snap
        // us back to JSON default before the audience saw the new
        // effect they just triggered.
        songEffectAutoRevert?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.state.songEffectOverride = nil
            self?.state.songEffectExpiresAt = .distantPast
            self?.songEffectAutoRevert = nil
        }
        songEffectAutoRevert = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.songEffectHoldSeconds,
            execute: work
        )
    }

    // Tear down any in-flight song-effect override. Used when the
    // lineup cursor moves; an unrelated work item firing on a new
    // song would briefly clear *its* JSON-default visualEffect, which
    // would look like a glitch on stage.
    private func clearSongEffectOverride() {
        songEffectAutoRevert?.cancel()
        songEffectAutoRevert = nil
        state.songEffectOverride = nil
        state.songEffectExpiresAt = .distantPast
    }

    // MARK: - Audience interactive routing

    // Green button on an audience-interactive item. Behavior depends
    // on the kind — for start_button green = "advance the show".
    private func handleAudienceInteractiveGreen() {
        guard let a = state.currentAudienceInteractive else { return }
        switch a.kind {
        case .startButton:
            // The show is starting — green advances the lineup to
            // whatever comes next. Same code path as the right-arrow
            // key, so the behavior is identical operator-side.
            nextLineupItem()
        }
    }

    // Red button on an audience-interactive item. start_button treats
    // red as the wrong choice — 8-bit error beep through the audio
    // engine plus a 1.5 s "WRONG BUTTON" overlay (driven by
    // state.wrongButtonAt that the view reads via TimelineView).
    private func handleAudienceInteractiveRed() {
        guard let a = state.currentAudienceInteractive else { return }
        switch a.kind {
        case .startButton:
            // Routed through AudioEngineController so the beep comes
            // out the same output device the music goes to (FOH at a
            // live rig, not the laptop speakers — NSSound.beep would
            // do the wrong thing here).
            audio.playWrongButtonBeep()
            state.wrongButtonAt = Date()
        }
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
