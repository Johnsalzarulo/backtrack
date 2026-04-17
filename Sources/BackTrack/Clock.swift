import Foundation

final class Clock: ObservableObject {
    let state: AppState
    let audio: AudioEngineController

    private var timer: DispatchSourceTimer?
    private var tick: Int = 0
    private var tapTimes: [Date] = []
    private var scheduledTempo: Double = 0

    init(state: AppState, audio: AudioEngineController) {
        self.state = state
        self.audio = audio
    }

    func toggleTransport() {
        if state.isPlaying { stop() } else { start() }
    }

    func start() {
        guard !state.isPlaying else { return }
        tick = 0
        state.isPlaying = true
        state.currentBeat = 0
        scheduleTimer(immediate: true)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        state.isPlaying = false
        state.currentBeat = 0
    }

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
        if tick == 0 {
            state.applyPending()
        }

        for e in Generators.drums(state: state, tick: tick) { audio.trigger(e) }

        state.currentBeat = tick / 4
        tick = (tick + 1) % Generators.ticksPerBar

        if state.tempo != scheduledTempo {
            scheduleTimer(immediate: false)
        }
    }

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
            audio.updateDelayTime()
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
