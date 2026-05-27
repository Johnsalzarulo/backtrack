import Foundation

// Song playback scheduler. Drives the 16th-note tick grid via a
// DispatchSourceTimer on the main queue, firing trigger events into
// the AudioEngineController on each tick and advancing bar / part
// position on bar boundaries.
//
// Grid: 16 ticks per bar (1, 1e, 1+, 1a, 2, 2e, ...). Tempo in BPM
// translates to tick interval = 60 / (BPM × 4) seconds. Tempo is the
// active song's `bpm` field — no live retiming.
//
// Part navigation while playing is queued to the next bar (so arrow
// presses don't chop mid-bar); while stopped, selection applies
// immediately and Space starts from the chosen part.
//
// Ownership: Coordinator creates one Clock, shared with
// AudioEngineController and KeyboardHandler. The Clock reads AppState
// for song / part / bar context and writes back transport state,
// position, and — via audio.trigger() → audio updating state — the
// per-voice trigger timestamps that the visuals read.
final class Clock: ObservableObject {
    let state: AppState
    let audio: AudioEngineController

    private var timer: DispatchSourceTimer?
    private var tick: Int = 0              // 0..15 within current bar
    private var lastChordKey: String = ""  // tracks chord-change for pad drone

    // Countdown motif loop. Separate from the song transport above:
    // a countdown is never a song, so the two never run at once, but
    // keeping a distinct timer + tick state means stopping one can't
    // disturb the other and the motif path stays free of the song's
    // part/structure/count-in machinery. Started/stopped from the
    // countdown transport in KeyboardHandler.
    private var motifTimer: DispatchSourceTimer?
    private var motifTick: Int = 0
    private var motifBar: Int = 0
    private var motifChordKey: String = ""
    private var activeMotif: CountdownMotif?
    // Flattened per-bar arrangement for activeMotif, precomputed at
    // startMotif so the per-tick path is a cheap index instead of
    // rebuilding the section list 16 times a bar. Empty = drums-only.
    private var motifSlots: [MotifBar] = []

    // Count-in pre-roll. While `countInRemaining` > 0 the timer fires
    // metronome clicks instead of song events. Counted in 16th-note
    // ticks so it shares the song's tick grid — N bars of count-in =
    // N × ticksPerBar ticks.
    private var countInRemaining: Int = 0

    // Dedicated high-priority queue for the playback timer. Keeping
    // the timer off `.main` means heavy visual work (post-effects
    // redrawing every frame) can't delay tick firing — audio events
    // schedule on this queue and AVAudioPlayerNode handles them on
    // its own audio thread, while @Published state mutations bounce
    // back to main via the helpers below.
    private let clockQueue = DispatchQueue(label: "com.backtrack.clock", qos: .userInteractive)

    init(state: AppState, audio: AudioEngineController) {
        self.state = state
        self.audio = audio
    }

    // MARK: - Transport

    func toggleTransport() {
        if state.isPlaying { stop() } else { start() }
    }

    func start() {
        guard !state.isPlaying else { return }
        guard let song = state.currentSong, !song.structure.isEmpty else { return }

        // Apply song-level setup: kit, pad sound, bass sound.
        audio.selectDrumKit(named: song.kit)
        if let pad = song.padSound { audio.selectPadSound(named: pad) }
        if let bass = song.bassSound { audio.selectBassSound(named: bass) }

        // Respect whatever part the user arrowed to while stopped —
        // don't forcibly rewind to the intro on each Space press.
        if state.currentPartIndex < 0 || state.currentPartIndex >= song.structure.count {
            state.currentPartIndex = 0
        }
        tick = 0
        state.currentBar = 0
        state.pendingPartIndex = nil
        lastChordKey = ""
        state.isPlaying = true
        state.currentBeat = 0

        // Set up count-in if configured. countInRemaining is in 16th-note
        // ticks; the timer below fires every tick, and onTick() emits a
        // click whenever countInRemaining lands on a quarter-note.
        if song.countIn > 0 {
            countInRemaining = song.countIn * Generators.ticksPerBar
            state.countInTotal = song.countIn * 4
            state.countInBeat = nil // first click sets it on tick 0
            // Defer videoClip activation until count-in finishes —
            // count-in's giant 1/2/3/4 display takes the visuals window
            // on its own.
        } else {
            countInRemaining = 0
            state.countInTotal = 0
            state.countInBeat = nil
            applyVideoClip(for: state.currentPart)
        }
        scheduleTimer(immediate: true)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        state.isPlaying = false
        state.currentBeat = 0
        countInRemaining = 0
        state.countInBeat = nil
        state.countInTotal = 0
        // Tear down any in-progress video clip; the visuals window
        // will fall back to the synth / static idle view.
        state.activeVideoClip = nil
        audio.stopAllPadAndBass()
        audio.stopAllDrums()
    }

    // MARK: - Countdown motif loop

    // Start the looping musical bed for a countdown. Idempotent-ish:
    // a fresh call cancels any running loop and restarts from the top
    // of the progression (resume-from-pause restarts the loop, which
    // is musically fine for an endlessly looping motif). Selects the
    // motif's kit / pad / bass sounds the same way Clock.start() does
    // for songs.
    func startMotif(_ motif: CountdownMotif) {
        stopMotif()
        activeMotif = motif
        motifSlots = motif.barSlots
        if let kit = motif.kit { audio.selectDrumKit(named: kit) }
        if let pad = motif.padSound { audio.selectPadSound(named: pad) }
        if let bass = motif.bassSound { audio.selectBassSound(named: bass) }
        motifTick = 0
        motifBar = 0
        motifChordKey = ""
        scheduleMotifTimer(immediate: true)
    }

    func stopMotif() {
        motifTimer?.cancel()
        motifTimer = nil
        guard activeMotif != nil else { return }
        activeMotif = nil
        motifSlots = []
        audio.stopAllPadAndBass()
        audio.stopAllDrums()
        writeState { s in s.currentBeat = 0 }
    }

    private func scheduleMotifTimer(immediate: Bool) {
        motifTimer?.cancel()
        let bpm = activeMotif?.bpm ?? Countdown.defaultMotifBPM
        let t = DispatchSource.makeTimerSource(queue: clockQueue)
        let seconds = 60.0 / (bpm * 4.0)
        let interval = DispatchTimeInterval.nanoseconds(Int(seconds * 1_000_000_000))
        let first: DispatchTime = immediate ? .now() : .now() + interval
        t.schedule(deadline: first, repeating: interval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.onMotifTick() }
        motifTimer = t
        t.resume()
    }

    // One 16th-note tick of the countdown motif. The flattened
    // `motifSlots` collapse the section arrangement into a per-bar
    // lookup, so this loops the whole arrangement just by wrapping
    // motifBar with `% count` — no structure to advance through, which
    // keeps it much simpler than the song path's onTick().
    private func onMotifTick() {
        guard let motif = activeMotif else { return }
        let slot = motifSlots.isEmpty ? nil : motifSlots[motifBar % motifSlots.count]
        let chord = slot?.chord
        let padLevel = slot?.padLevel ?? 0
        let bassLevel = slot?.bassLevel ?? 0

        // Chord-change detection drives the level-1 pad drone retrigger
        // and clears ringing voices at section / chord boundaries,
        // mirroring fireTick0's logic for songs.
        var chordChanged = false
        if motifTick == 0, let chord = chord {
            let key = "\(chord.rootPitchClass)-\(chord.quality)"
            chordChanged = (key != motifChordKey)
            if chordChanged && !motifChordKey.isEmpty {
                audio.stopAllPadAndBass()
            }
            motifChordKey = key
        }

        if let pattern = motif.pattern {
            for e in Generators.drums(pattern: pattern, tick: motifTick) {
                audio.trigger(e)
            }
        }
        if let chord = chord {
            for e in Generators.pad(level: padLevel, chord: chord, tick: motifTick, chordChanged: chordChanged) {
                audio.trigger(e)
            }
            for e in Generators.bass(level: bassLevel, chord: chord, tick: motifTick) {
                audio.trigger(e)
            }
        }

        // Beat indicator so countdown post-effects (glitch / tracking /
        // chroma) can beat-sync to the motif, same as during songs.
        let newBeat = motifTick / 4
        if newBeat != state.currentBeat {
            let now = Date()
            writeState { s in
                s.currentBeat = newBeat
                s.lastBeatTime = now
            }
        }

        motifTick += 1
        if motifTick >= Generators.ticksPerBar {
            motifTick = 0
            motifBar += 1
        }
    }

    // Resolve a part's videoClip (if any) into state so the visuals
    // window can render it. Volume is mirrored from the part's
    // videoClipVolume (0–100) into a 0.0–1.0 float for AVPlayer.
    // Called whenever the transport enters a new part.
    private func applyVideoClip(for part: Part?) {
        let url: URL?
        let volume: Float
        if let part = part,
           let filename = part.videoClip,
           let resolved = VideoClipsLibrary.url(for: filename) {
            url = resolved
            volume = Float(max(0, min(100, part.videoClipVolume))) / 100.0
        } else {
            url = nil
            volume = 1.0
        }
        writeState { s in
            s.activeVideoClip = url
            s.activeVideoClipVolume = volume
        }
    }

    // MARK: - Part navigation

    // Arrow keys. While playing, part changes queue to the next bar and
    // accumulate if pressed repeatedly (pressing up 3× queues three
    // parts ahead). While stopped, the selection changes immediately so
    // Space starts from wherever the user has arrowed to. Both wrap
    // around so up from the last part jumps to the first, and vice versa.
    func nextPart() { stepPart(by: 1) }
    func previousPart() { stepPart(by: -1) }

    private func stepPart(by direction: Int) {
        guard let song = state.currentSong, !song.structure.isEmpty else { return }
        let count = song.structure.count
        if state.isPlaying {
            let base = state.pendingPartIndex ?? state.currentPartIndex
            state.pendingPartIndex = ((base + direction) % count + count) % count
        } else {
            state.currentPartIndex = ((state.currentPartIndex + direction) % count + count) % count
            state.currentBar = 0
            state.pendingPartIndex = nil
            lastChordKey = ""
        }
    }

    // Lineup navigation (next/previous lineup item) lives in
    // KeyboardHandler now — it owns the cursor + override resets.
    // Clock just provides `stop()` and the in-song part navigation
    // helpers (nextPart / previousPart) above.

    // MARK: - Timer

    private func scheduleTimer(immediate: Bool) {
        timer?.cancel()
        let bpm = state.currentSong?.bpm ?? 100
        let t = DispatchSource.makeTimerSource(queue: clockQueue)
        let seconds = 60.0 / (bpm * 4.0)
        let interval = DispatchTimeInterval.nanoseconds(Int(seconds * 1_000_000_000))
        let first: DispatchTime = immediate ? .now() : .now() + interval
        t.schedule(deadline: first, repeating: interval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.onTick() }
        timer = t
        t.resume()
    }

    // Helper: bounce a state mutation to main from any thread. Used
    // throughout onTick/tickCountIn since they run on `clockQueue`
    // and @Published updates must happen on main.
    private func writeState(_ block: @escaping (AppState) -> Void) {
        if Thread.isMainThread {
            block(state)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                block(self.state)
            }
        }
    }

    private func onTick() {
        // Running on `clockQueue` — reads from @Published state may
        // be slightly stale relative to main, but for transport
        // timing that's harmless (worst case we use last tick's
        // values for one beat). State writes go through writeState.
        guard let song = state.currentSong else {
            stopAsync()
            return
        }
        guard state.currentPartIndex < song.structure.count,
              let part = state.currentPart else {
            stopAsync()
            return
        }

        // Count-in pre-roll. Fires a hi-hat click on each quarter note,
        // accented on every bar's downbeat. The song proper hasn't
        // started yet — currentBar / tick stay at 0 the whole time.
        if countInRemaining > 0 {
            tickCountIn(totalBeats: song.countIn * 4)
            return
        }

        // Bar boundary: apply pending part jump, or auto-advance if the
        // current part has finished its bars.
        if tick == 0 {
            if let pending = state.pendingPartIndex {
                writeState { s in
                    s.currentPartIndex = pending
                    s.currentBar = 0
                    s.pendingPartIndex = nil
                }
                audio.stopAllPadAndBass()
                lastChordKey = ""
                // Re-fetch the resolved part directly off the song so
                // we don't depend on the @Published state having flushed.
                let newPart = song.parts[song.structure[pending]] ?? part
                applyVideoClip(for: newPart)
                fireTick0(part: newPart, atBar: 0)
                scheduleTickAdvance()
                return
            }
            if state.currentBar >= part.bars {
                // Loop mode: restart the same part instead of advancing.
                // Don't re-trigger videoClip — looping a part with a
                // clip would otherwise replay the clip every loop, and
                // loops are mostly used for pattern auditioning.
                if state.loopCurrentPart {
                    writeState { s in s.currentBar = 0 }
                    audio.stopAllPadAndBass()
                    lastChordKey = ""
                    fireTick0(part: part, atBar: 0)
                    scheduleTickAdvance()
                    return
                }
                // Part finished — advance.
                let next = state.currentPartIndex + 1
                if next >= song.structure.count {
                    stopAsync()
                    return
                }
                writeState { s in
                    s.currentPartIndex = next
                    s.currentBar = 0
                }
                audio.stopAllPadAndBass()
                lastChordKey = ""
                let newPart = song.parts[song.structure[next]] ?? part
                applyVideoClip(for: newPart)
                fireTick0(part: newPart, atBar: 0)
                scheduleTickAdvance()
                return
            }
            fireTick0(part: part, atBar: state.currentBar)
        } else {
            fireTickN(part: part, tick: tick)
        }

        scheduleTickAdvance()
    }

    // Async-safe stop, callable from clockQueue. The public `stop()`
    // is fine on main but unsafe to invoke directly from the timer
    // thread (timer.cancel from inside its own handler can deadlock
    // briefly), so we bounce through main.
    private func stopAsync() {
        DispatchQueue.main.async { [weak self] in self?.stop() }
    }

    // One tick of count-in pre-roll: emit a click on each quarter and
    // update the HUD's count-in indicator. Each tick decrements
    // `countInRemaining`; when it hits zero the next call to onTick()
    // begins the song proper at bar 0, tick 0.
    private func tickCountIn(totalBeats: Int) {
        // Position within the count-in span, expressed in 16th-note ticks
        // counted from 0 (first click) up to totalBeats * 4 - 1.
        let totalTicks = totalBeats * 4
        let ticksElapsed = totalTicks - countInRemaining
        let isQuarter = (ticksElapsed % 4 == 0)

        if isQuarter {
            let beatIndex = ticksElapsed / 4 // 0-based
            let beatInBar = beatIndex % 4
            // Beat 1 of every count-in bar is accented so the player
            // can lock to the bar grid by ear.
            let velocity: Float = beatInBar == 0 ? 1.0 : 0.55
            audio.trigger(NoteEvent(voice: .hihat, velocity: velocity))
            let beatNumber = beatIndex + 1
            let now = Date()
            writeState { s in
                s.countInBeat = beatNumber
                s.currentBeat = beatInBar
                s.lastBeatTime = now
            }
        }

        countInRemaining -= 1
        if countInRemaining == 0 {
            writeState { s in
                s.countInBeat = nil
                s.countInTotal = 0
                s.currentBeat = 0
            }
            // Now the song proper begins — surface the first part's
            // videoClip, if any, so it starts together with the music.
            applyVideoClip(for: state.currentPart)
            // Next tick starts the song at bar 0, tick 0.
            tick = 0
        }
    }

    private func scheduleTickAdvance() {
        // Update beat indicator + advance tick counter. `tick` lives
        // on this clock and increments here; the @Published mirror
        // (state.currentBeat) flushes via writeState a moment later.
        let newBeat = tick / 4
        let beatChanged = (newBeat != state.currentBeat)
        let now = Date()
        writeState { s in
            if beatChanged {
                s.currentBeat = newBeat
                s.lastBeatTime = now
            }
        }
        tick += 1
        if tick >= Generators.ticksPerBar {
            tick = 0
            writeState { s in s.currentBar += 1 }
        }
    }

    // Tick 0 of a bar: evaluate chord change + fire all voices that hit on
    // the downbeat. Takes the bar explicitly so callers don't depend on
    // the @Published state having flushed before they fire.
    private func fireTick0(part: Part, atBar bar: Int) {
        guard let chord = part.chord(atBar: bar) else { return }
        let chordKey = "\(chord.rootPitchClass)-\(chord.quality)"
        let previousKey = lastChordKey
        let changed = (chordKey != previousKey)
        lastChordKey = chordKey

        if changed && !previousKey.isEmpty {
            audio.stopAllPadAndBass()
        }

        fireDrums(part: part, tick: 0)
        for e in Generators.pad(level: part.padLevel, chord: chord, tick: 0, chordChanged: changed) {
            audio.trigger(e)
        }
        for e in Generators.bass(level: part.bassLevel, chord: chord, tick: 0) { audio.trigger(e) }
    }

    private func fireTickN(part: Part, tick: Int) {
        // Re-read the bar so a tick-0 advance that already wrote the
        // new bar is reflected here. The slight staleness window is
        // safe because tick 1+ within a bar can't span a boundary.
        guard let chord = part.chord(atBar: state.currentBar) else { return }
        fireDrums(part: part, tick: tick)
        for e in Generators.pad(level: part.padLevel, chord: chord, tick: tick, chordChanged: false) {
            audio.trigger(e)
        }
        for e in Generators.bass(level: part.bassLevel, chord: chord, tick: tick) { audio.trigger(e) }
    }

    // Fires the pattern's drum events for this tick, except when the part
    // is in audience-drums mode — then kick + snare are dropped (the
    // audience is the drummer; their button presses provide them).
    // Hi-hat keeps running so the player has a metronomic pulse to hold to.
    private func fireDrums(part: Part, tick: Int) {
        let audienceDrums = effectiveVisualizer(for: part) == .audienceDrums
        for e in Generators.drums(pattern: part.pattern, tick: tick) {
            if audienceDrums {
                if case .kick = e.voice { continue }
                if case .snare = e.voice { continue }
            }
            audio.trigger(e)
        }
    }

    // Resolves the visualizer for a part, falling back to the song-level
    // value when the part doesn't override. Mirrors AppState.effectiveVisualizer
    // but takes the part explicitly so transitions (where state hasn't
    // flushed yet) resolve correctly.
    private func effectiveVisualizer(for part: Part) -> VisualizerStyle {
        part.visualizer ?? state.currentSong?.visualizer ?? .constellation
    }
}
