import Foundation

// Song playback scheduler. Drives the 16th-note tick grid via a
// DispatchSourceTimer on the main queue, firing trigger events into
// the AudioEngineController on each tick and advancing bar / part
// position on bar boundaries.
//
// Grid: 16 ticks per bar (1, 1e, 1+, 1a, 2, 2e, ...). Tempo in BPM
// translates to tick interval = 60 / (BPM × 4) seconds. A tempo change
// (via T key tap-tempo) applies at the next tick boundary so we don't
// stretch the currently-pending tick.
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
    private var tapTimes: [Date] = []
    private var scheduledTempo: Double = 0
    private var lastChordKey: String = ""  // tracks chord-change for pad drone

    // Count-in pre-roll. While `countInRemaining` > 0 the timer fires
    // metronome clicks instead of song events. Counted in 16th-note
    // ticks so it shares the song's tick grid — N bars of count-in =
    // N × ticksPerBar ticks.
    private var countInRemaining: Int = 0

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

        // Apply song-level setup: kit, pad sound, bass sound, tempo.
        audio.selectDrumKit(named: song.kit)
        if let pad = song.padSound { audio.selectPadSound(named: pad) }
        if let bass = song.bassSound { audio.selectBassSound(named: bass) }
        state.tempo = song.bpm

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
        } else {
            countInRemaining = 0
            state.countInTotal = 0
            state.countInBeat = nil
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
        audio.stopAllPadAndBass()
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

    // MARK: - Song navigation (immediate, stops playback)

    func nextSong() {
        guard !state.songs.isEmpty else { return }
        if state.isPlaying { stop() }
        state.currentSongIndex = (state.currentSongIndex + 1) % state.songs.count
        resetSongPosition()
    }

    func previousSong() {
        guard !state.songs.isEmpty else { return }
        if state.isPlaying { stop() }
        let n = state.songs.count
        state.currentSongIndex = ((state.currentSongIndex - 1) % n + n) % n
        resetSongPosition()
    }

    private func resetSongPosition() {
        state.currentPartIndex = 0
        state.currentBar = 0
        state.pendingPartIndex = nil
        lastChordKey = ""
        tick = 0
        if let song = state.currentSong {
            state.tempo = song.bpm
        }
    }

    // MARK: - Timer

    private func scheduleTimer(immediate: Bool) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        let seconds = 60.0 / (state.tempo * 4.0)
        let interval = DispatchTimeInterval.nanoseconds(Int(seconds * 1_000_000_000))
        let first: DispatchTime = immediate ? .now() : .now() + interval
        t.schedule(deadline: first, repeating: interval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.onTick() }
        timer = t
        scheduledTempo = state.tempo
        t.resume()
    }

    private func onTick() {
        guard let song = state.currentSong else { stop(); return }
        guard state.currentPartIndex < song.structure.count,
              let part = state.currentPart else { stop(); return }

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
                state.currentPartIndex = pending
                state.currentBar = 0
                state.pendingPartIndex = nil
                audio.stopAllPadAndBass()
                lastChordKey = ""
                // Re-fetch part for this tick with the new index.
                guard let newPart = state.currentPart else { stop(); return }
                fireTick0(part: newPart)
                scheduleTickAdvance()
                return
            }
            if state.currentBar >= part.bars {
                // Loop mode: restart the same part instead of advancing.
                // Useful for auditioning drum patterns without the song
                // marching through the structure.
                if state.loopCurrentPart {
                    state.currentBar = 0
                    audio.stopAllPadAndBass()
                    lastChordKey = ""
                    guard let loopedPart = state.currentPart else { stop(); return }
                    fireTick0(part: loopedPart)
                    scheduleTickAdvance()
                    return
                }
                // Part finished — advance.
                let next = state.currentPartIndex + 1
                if next >= song.structure.count {
                    stop()
                    return
                }
                state.currentPartIndex = next
                state.currentBar = 0
                audio.stopAllPadAndBass()
                lastChordKey = ""
                guard let newPart = state.currentPart else { stop(); return }
                fireTick0(part: newPart)
                scheduleTickAdvance()
                return
            }
            fireTick0(part: part)
        } else {
            fireTickN(part: part, tick: tick)
        }

        scheduleTickAdvance()
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
            state.countInBeat = beatIndex + 1 // 1-based for display
            state.currentBeat = beatInBar
            state.lastBeatTime = Date()
        }

        countInRemaining -= 1
        if countInRemaining == 0 {
            state.countInBeat = nil
            state.countInTotal = 0
            state.currentBeat = 0
            // Next tick starts the song at bar 0, tick 0.
            tick = 0
        }

        if state.tempo != scheduledTempo {
            scheduleTimer(immediate: false)
        }
    }

    private func scheduleTickAdvance() {
        // Update beat indicator + advance tick counter.
        let newBeat = tick / 4
        if newBeat != state.currentBeat {
            state.lastBeatTime = Date()
        }
        state.currentBeat = newBeat
        tick += 1
        if tick >= Generators.ticksPerBar {
            tick = 0
            state.currentBar += 1
        }
        if state.tempo != scheduledTempo {
            scheduleTimer(immediate: false)
        }
    }

    // Tick 0 of a bar: evaluate chord change + fire all voices that hit on
    // the downbeat (drums tick 0 events + pad level 1 if chord changed +
    // pad level 2/3 initial hits + bass level 1/2/3 downbeat).
    //
    // On chord change, fade out the previous chord's pad + bass voices so
    // long sustained samples don't bleed into the new chord. The
    // fade-out runs on older voice-pool slots; new triggers below use
    // the next pool slots and fade in cleanly on top.
    private func fireTick0(part: Part) {
        guard let chord = part.chord(atBar: state.currentBar) else { return }
        let chordKey = "\(chord.rootPitchClass)-\(chord.quality)"
        let previousKey = lastChordKey
        let changed = (chordKey != previousKey)
        lastChordKey = chordKey

        if changed && !previousKey.isEmpty {
            audio.stopAllPadAndBass()
        }

        for e in Generators.drums(pattern: part.pattern, tick: 0) { audio.trigger(e) }
        for e in Generators.pad(level: part.padLevel, chord: chord, tick: 0, chordChanged: changed) {
            audio.trigger(e)
        }
        for e in Generators.bass(level: part.bassLevel, chord: chord, tick: 0) { audio.trigger(e) }
    }

    private func fireTickN(part: Part, tick: Int) {
        guard let chord = part.chord(atBar: state.currentBar) else { return }
        for e in Generators.drums(pattern: part.pattern, tick: tick) { audio.trigger(e) }
        for e in Generators.pad(level: part.padLevel, chord: chord, tick: tick, chordChanged: false) {
            audio.trigger(e)
        }
        for e in Generators.bass(level: part.bassLevel, chord: chord, tick: tick) { audio.trigger(e) }
    }

    // MARK: - Tap tempo

    func tapTempo() {
        let now = Date()
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2.0 {
            tapTimes.removeAll()
        }
        tapTimes.append(now)
        if tapTimes.count > 4 {
            tapTimes.removeFirst(tapTimes.count - 4)
        }
        if tapTimes.count >= 2 {
            var intervals: [TimeInterval] = []
            for i in 1..<tapTimes.count {
                intervals.append(tapTimes[i].timeIntervalSince(tapTimes[i - 1]))
            }
            let avg = intervals.reduce(0, +) / Double(intervals.count)
            if avg > 0 {
                let bpm = 60.0 / avg
                state.tempo = max(40, min(240, bpm))
            }
            if state.isPlaying {
                tick = 0
                state.currentBeat = 0
                scheduleTimer(immediate: true)
            }
        }
        state.bpmFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.state.bpmFlash = false
        }
    }
}
