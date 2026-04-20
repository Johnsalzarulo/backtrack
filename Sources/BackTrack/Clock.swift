import Foundation

final class Clock: ObservableObject {
    let state: AppState
    let audio: AudioEngineController

    private var timer: DispatchSourceTimer?
    private var tick: Int = 0              // 0..15 within current bar
    private var tapTimes: [Date] = []
    private var scheduledTempo: Double = 0
    private var lastChordKey: String = ""  // tracks chord-change for pad drone

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
        scheduleTimer(immediate: true)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        state.isPlaying = false
        state.currentBeat = 0
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

    private func scheduleTickAdvance() {
        // Update beat indicator + advance tick counter.
        state.currentBeat = tick / 4
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
