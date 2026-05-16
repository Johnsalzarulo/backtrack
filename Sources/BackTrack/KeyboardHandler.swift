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

    // Pending auto-hide for the telemetry panel (the "2" key during a
    // song). Each tap toggles the panel; if turning ON we arm this
    // timer to hide it again after a few seconds in case the audience
    // forgets to tap a second time. Cancelled on a manual toggle-off
    // and on lineup moves.
    private var telemetryAutoHide: DispatchWorkItem?

    // How long the telemetry panel stays visible after a tap before
    // auto-hiding back to the song's normal visuals.
    private static let telemetryHoldSeconds: TimeInterval = 5

    // Pending transition for the active "transmission" audience-
    // interactive (e.g. The Breakup). The transmission walks through
    // a sequence of phases — incoming → replyEcho → preIncomingBlank
    // → next incoming, or → deletedFlash → lineup advance. Each
    // transition fires from the previous one's work item; this field
    // holds the currently-pending one so we can cancel cleanly when
    // the lineup cursor moves.
    private var transmissionTimer: DispatchWorkItem?

    // Minimum time "YOU SENT: <reply>" stays on screen after an
    // audience press. Short replies hit this floor; longer replies
    // grow the echo phase to match the estimated TTS speaking
    // duration so Tom's voice isn't cut mid-sentence — see
    // `estimatedReplyEchoDuration(for:)`.
    private static let transmissionEchoSeconds: TimeInterval = 1.5

    // Estimated seconds-per-character for the male reply voice at
    // its current rate (0.9 × default). Tuned empirically against
    // the shipped scripts — short replies finish comfortably, long
    // replies have room to land before the phase advances. Bump if
    // a slower system voice gets cut, drop if pacing drags.
    private static let transmissionTtsPerChar: TimeInterval = 0.085

    // Pre-delay built into speakReply (matches AudioEngine's value)
    // — the speech doesn't actually start until this fraction of a
    // second after the press, so we add it to the echo duration.
    private static let transmissionReplyPreDelay: TimeInterval = 0.2

    // Echo-phase duration for a given reply text. Returns the max of
    // the floor and the estimated speech duration plus trailing
    // padding, so the audience sees the YOU SENT card stay up while
    // Tom is reading it.
    private static func estimatedReplyEchoDuration(for text: String) -> TimeInterval {
        let speaking = TimeInterval(text.count) * transmissionTtsPerChar
        let estimated = transmissionReplyPreDelay + speaking + 0.4  // 0.4s trailing buffer
        return max(transmissionEchoSeconds, estimated)
    }
    // How long the screen sits blank between the reply echo and the
    // next incoming — sells the "they're typing on the other end"
    // pause without dragging.
    private static let transmissionPreIncomingSeconds: TimeInterval = 0.7
    // How long "DELETED" flashes before the lineup auto-advances on
    // an "abort" path (e.g. DELETE on the opening gate).
    private static let transmissionDeletedFlashSeconds: TimeInterval = 0.8

    // Used to dispatch button presses on a transmission item without
    // the call-site needing to know the "1=green, 2=red" mapping.
    private enum TransmissionButton {
        case green, red
    }

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
        // KeyDown-only — every shortcut fires on press. The telemetry
        // panel used to listen for keyUp too (hold-to-show), but the
        // hardware audience buttons in the rig only signal on press,
        // so the model is now tap-to-toggle with a timer-driven
        // auto-hide. No keyUp interest, no focus-loss observer.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let handled = self.handle(event)
            // Audience hardware buttons ("1" / "2") are always consumed
            // even if no handler had work to do in the current context
            // (interstitial, idle, tweak mode). Propagating them lets
            // AppKit play the system alert beep on every audience press
            // during a video — wrong for a stage rig where the laptop
            // speakers are wired to FOH. Per-key handlers are still in
            // charge of *what* happens; the wrapper just makes sure
            // *nothing else* does.
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if chars == "1" || chars == "2" {
                return nil
            }
            return handled ? nil : event
        }
        // Seed any per-item state for whatever lineup item the cursor
        // happens to be on at app launch (typically index 0). Covers
        // the rare case where the very first item is a transmission.
        seedTransmissionIfNeeded()
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.modifierFlags.contains(.command) { return false }

        // OS key-repeat fires keyDown over and over while a physical
        // key is held. The audience button cluster shouldn't generate
        // these (it pulses on press), but stage rigs sometimes share
        // keyboards with operators — ignore repeats on "2" so a stuck
        // key can't toggle the panel on/off rapidly.
        if event.isARepeat && chars == "2" {
            return true
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
                // joke. Same suppression while the telemetry panel is
                // up — that takeover owns the screen.
                if state.activeVideoClip != nil { return true }
                if state.telemetryVisible { return true }
                cycleSongEffect()
                return true
            }
            if state.currentCountdown != nil {
                cycleCountdownStyle()
                return true
            }
            if state.currentAudienceInteractive != nil {
                // The on-screen prompt asks the audience to press
                // green; the "1" key is wired to the green button on
                // this rig, so this is the "advance the show" path.
                // The naming of handleAudienceInteractive*Green/Red*
                // refers to the button color the audience sees, not
                // the underlying keycode.
                handleAudienceInteractiveGreen()
                return true
            }
            return false
        case "2":
            // Audience-facing green button. Behavior depends on what's
            // currently on stage:
            //   - song:                tap to toggle the telemetry
            //                          panel; if turning ON we arm a
            //                          5-second auto-hide so it
            //                          dismisses if no one taps again.
            //                          Suppressed during videoClips.
            //   - countdown:           tap to advance the rotating
            //                          message.
            //   - audience-interactive: kind-specific. start_button
            //                          advances the lineup to the
            //                          next item ("show is starting").
            //   - anything else:       no-op.
            if state.currentSong != nil {
                if state.activeVideoClip != nil { return true }
                toggleTelemetry()
                return true
            }
            if state.currentCountdown != nil {
                advanceCountdownMessage()
                return true
            }
            if state.currentAudienceInteractive != nil {
                // "2" is wired to the red button on this rig — error
                // path for start_button. See note on the "1" branch
                // above: the handler names track audience-button
                // *colors*, not keycodes.
                handleAudienceInteractiveRed()
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
            // Space mirrors the "advance the show" action for this
            // kind so the operator can also drive forward from the
            // keyboard. For start_button this is green (next item);
            // for transmission this is the operator escape — Space
            // bails out of the bit at any phase, which is what you
            // want if it stalls live.
            switch a.kind {
            case .startButton:
                nextLineupItem()
            case .transmission:
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
        clearTelemetry()
        state.wrongButtonAt = .distantPast
        clearSongEffectOverride()
        clearTransmission()

        scheduleInterstitialAutoAdvanceIfNeeded()
        seedTransmissionIfNeeded()
    }

    // If the new current item is a transmission audience-interactive,
    // initialize its phase to the first exchange so the audience sees
    // an INCOMING message the moment the cursor lands. No-op on every
    // other item kind (and on transmissions whose script is empty,
    // which the loader rejects anyway).
    private func seedTransmissionIfNeeded() {
        guard let interactive = state.currentAudienceInteractive,
              case .transmission = interactive.kind,
              let script = interactive.transmission,
              let firstId = script.firstExchangeId else { return }
        enterTransmissionIncoming(exchangeId: firstId)
    }

    // Single entry point for putting the phase into .incoming. Sets
    // the start time and — if the new exchange has an autoAdvance
    // block — schedules the timer that fires after typing + hold.
    // Used by initial seeding, the post-blank transition, and the
    // gate-skip path. Never call `state.transmissionPhase = .incoming`
    // directly outside this function.
    private func enterTransmissionIncoming(exchangeId: String) {
        let now = Date()
        state.transmissionPhase = .incoming(exchangeId: exchangeId, startedAt: now)
        // Look up the exchange so we can both play the arrival sound
        // and schedule any auto-advance.
        guard let interactive = state.currentAudienceInteractive,
              let script = interactive.transmission,
              let exchange = script.exchange(id: exchangeId) else { return }
        // Arrival SFX — "doot doot" for incoming messages, the
        // death arpeggio for GAME OVER beats, nothing for OUTGOING
        // or gates. See TransmissionExchange.effectiveArrivalSound
        // for the default rules + per-exchange override.
        switch exchange.effectiveArrivalSound {
        case .doot:
            audio.playMessageReceivedDoot()
        case .death:
            audio.playTransmissionEndSound()
        case .none:
            break
        }
        // TTS reads the message body in parallel with the typing
        // animation — female voice for INCOMING, male for OUTGOING.
        // Gate / GAME OVER / custom-header exchanges skip TTS (the
        // SFX carries them dramatically; the words would just feel
        // redundant).
        if !exchange.incoming.isEmpty {
            switch exchange.header.uppercased() {
            case "INCOMING":
                audio.speakIncoming(exchange.incoming)
            case "OUTGOING":
                audio.speakOutgoing(exchange.incoming)
            default:
                break
            }
        }
        guard let auto = exchange.autoAdvance else { return }
        // Timer = typing duration + hold seconds. The audience never
        // sees the message snap to a still state before the hold —
        // typing finishes, the message holds, then we transition.
        let typingDuration = TimeInterval(exchange.incoming.count) * TransmissionPacing.charDuration
        let totalDelay = typingDuration + auto.holdSeconds
        transmissionTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performTransmissionAutoAdvance(to: auto.next)
        }
        transmissionTimer = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + totalDelay,
            execute: work
        )
    }

    // Auto-advance is structurally similar to a normal press
    // transition but skips the reply echo (there's no reply to
    // echo) and uses a silent abort path (no DELETED flash —
    // auto-advancing to abort means the bit ended naturally, not
    // that anyone deleted anything).
    private func performTransmissionAutoAdvance(to next: TransmissionNext) {
        transmissionTimer?.cancel()
        transmissionTimer = nil
        // Silence any in-flight speech before the next phase begins,
        // so the previous message's voice doesn't trail into the
        // next exchange or out into the next setlist item.
        audio.stopSpeaking()
        switch next {
        case .abort:
            state.transmissionPhase = .idle
            nextLineupItem()
        case .exchange(let nextId):
            advanceToNextIncoming(nextId: nextId)
        }
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

    // Tap-toggle for the telemetry panel during a song. First tap
    // shows the panel + arms an auto-hide work item; second tap
    // (within the auto-hide window) cancels and hides immediately.
    // Replaces the previous keyDown/keyUp hold-to-show model so the
    // press-only audience hardware can drive it.
    private func toggleTelemetry() {
        if state.telemetryVisible {
            // Already showing — tap again means dismiss now.
            clearTelemetry()
            return
        }
        state.telemetryVisible = true
        // Arm the auto-hide so the panel can't get stuck on screen
        // if no one taps a second time. The work item also nils
        // itself out so toggling again later starts from a clean
        // slate.
        telemetryAutoHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.state.telemetryVisible = false
            self?.telemetryAutoHide = nil
        }
        telemetryAutoHide = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.telemetryHoldSeconds,
            execute: work
        )
    }

    // Hide the telemetry panel and cancel any pending auto-hide.
    // Used by manual tap-to-dismiss and by lineup-cursor moves so a
    // pending timer doesn't fire on a different item.
    private func clearTelemetry() {
        telemetryAutoHide?.cancel()
        telemetryAutoHide = nil
        state.telemetryVisible = false
    }

    // MARK: - Audience interactive routing

    // Green button on an audience-interactive item. Behavior depends
    // on the kind — for start_button green = "advance the show". For
    // transmission, green is the left choice in the current exchange.
    private func handleAudienceInteractiveGreen() {
        guard let a = state.currentAudienceInteractive else { return }
        switch a.kind {
        case .startButton:
            // The show is starting — green advances the lineup to
            // whatever comes next. Same code path as the right-arrow
            // key, so the behavior is identical operator-side.
            nextLineupItem()
        case .transmission:
            handleTransmissionPress(button: .green)
        }
    }

    // Red button on an audience-interactive item. start_button treats
    // red as the wrong choice (error beep + overlay); transmission
    // treats red as the right choice in the current exchange.
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
        case .transmission:
            handleTransmissionPress(button: .red)
        }
    }

    // MARK: - Transmission state machine

    // Audience press during a transmission. Only the .incoming phase
    // is interactive — every other phase is mid-transition, playing
    // out on a timer, and presses during it are no-ops. Terminal
    // exchanges (no choices) also no-op so a tap on the final
    // "mommy issues" message doesn't accidentally do anything. And
    // presses during the typing reveal are also dropped — the
    // audience shouldn't be able to skip past a message they haven't
    // had a chance to read.
    private func handleTransmissionPress(button: TransmissionButton) {
        guard case .incoming(let exchangeId, let startedAt) = state.transmissionPhase,
              let interactive = state.currentAudienceInteractive,
              let script = interactive.transmission,
              let exchange = script.exchange(id: exchangeId) else { return }
        if exchange.isTerminal { return }
        // Lockout while the message is still typing in. Empty-body
        // exchanges (the opening gate) clear this immediately because
        // there's nothing to type.
        let elapsed = Date().timeIntervalSince(startedAt)
        let charsRevealed = Int(elapsed / TransmissionPacing.charDuration)
        if charsRevealed < exchange.incoming.count { return }
        let choice: TransmissionChoice?
        switch button {
        case .green: choice = exchange.green
        case .red:   choice = exchange.red
        }
        if let choice = choice {
            // Normal press path — play the doot, transition phases.
            audio.playMessageReceivedDoot()
            applyTransmissionChoice(choice, fromExchange: exchange)
        } else if exchange.bottomPrompt != nil {
            // "Begging" press — exchange has a bottom prompt but no
            // reply choices (e.g. "Mash 🔴 and 🟢 to beg" during the
            // pre-GAME-OVER beat). Play the doot for feedback so the
            // audience hears something happening, but don't advance.
            // The exchange's own autoAdvance timer ends the moment.
            audio.playMessageReceivedDoot()
        }
        // Other case: no choices and no bottomPrompt — silently drop
        // (true terminal sit-forever exchanges).
    }

    // Drives the multi-step transition that follows an audience press:
    //   - On "abort": brief DELETED flash → lineup advance.
    //   - On a real exchange target: "YOU SENT: <text>" echo (1.0 s)
    //     → blank (0.7 s) → next .incoming. Each step's work item is
    //     cancelled if the lineup cursor moves before it fires.
    //
    // The echo is suppressed when the press happens on an exchange
    // with no incoming body (the opening "NEW MESSAGE RECEIVED" gate)
    // — there's nothing semantically to "reply" to, so showing
    // "YOU SENT: READ" reads as a bug. Skip straight to the blank
    // beat → next incoming.
    private func applyTransmissionChoice(_ choice: TransmissionChoice, fromExchange: TransmissionExchange) {
        transmissionTimer?.cancel()
        // Audience interrupted the voice — silence the TTS so it
        // doesn't continue talking past the moment they've moved on.
        audio.stopSpeaking()
        switch choice.next {
        case .abort:
            // No reply echo for the DELETE path — semantically it's a
            // dismissal, not a sent message.
            state.transmissionPhase = .deletedFlash
            let advance = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.state.transmissionPhase = .idle
                self.transmissionTimer = nil
                self.nextLineupItem()
            }
            transmissionTimer = advance
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.transmissionDeletedFlashSeconds,
                execute: advance
            )
        case .exchange(let nextId):
            if fromExchange.incoming.isEmpty || choice.isSilent {
                // Two cases skip the reply echo:
                //   - Gate-style exchange (no body to reply to, e.g.
                //     the opening "NEW MESSAGE RECEIVED" + READ/DELETE).
                //   - Silent stage-direction choice ("(say nothing)")
                //     — the audience didn't actually send anything.
                advanceToNextIncoming(nextId: nextId)
            } else {
                // Normal exchange: echo → blank → next incoming.
                state.transmissionPhase = .replyEcho(text: choice.label, nextExchangeId: nextId)
                // Speak the reply in the male voice (the player's
                // voice). speakReply has a small preUtteranceDelay
                // so it doesn't get smeared by the press-time doot.
                audio.speakReply(choice.label)
                let toBlank = DispatchWorkItem { [weak self] in
                    self?.advanceToNextIncoming(nextId: nextId)
                }
                transmissionTimer = toBlank
                // Echo duration scales with reply length so Tom's
                // voice has time to finish reading even on the
                // long replies ("we have so much life ahead",
                // "i'm sorry you feel that way", etc.) without
                // dragging on the short ones.
                let echoDuration = Self.estimatedReplyEchoDuration(for: choice.label)
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + echoDuration,
                    execute: toBlank
                )
            }
        }
    }

    // Pushes the phase from wherever-it-is into the
    // .preIncomingBlank → .incoming(nextId) sequence. Shared between
    // the normal echo path, the gate-skip path, the silent-choice
    // path, and post-autoAdvance transitions.
    private func advanceToNextIncoming(nextId: String) {
        state.transmissionPhase = .preIncomingBlank(nextExchangeId: nextId)
        let toIncoming = DispatchWorkItem { [weak self] in
            self?.enterTransmissionIncoming(exchangeId: nextId)
        }
        transmissionTimer = toIncoming
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.transmissionPreIncomingSeconds,
            execute: toIncoming
        )
    }

    // Cancels any pending transmission transition and resets the
    // phase to idle. Called from selectLineupItem so a transmission
    // that was mid-bit gets fully torn down before the next item
    // starts. Also stops any in-flight TTS so the voice doesn't
    // keep reading after the cursor has moved on. Idempotent.
    private func clearTransmission() {
        transmissionTimer?.cancel()
        transmissionTimer = nil
        state.transmissionPhase = .idle
        audio.stopSpeaking()
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
