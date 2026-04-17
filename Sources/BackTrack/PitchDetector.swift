import AVFoundation
import Foundation

final class PitchDetector {
    // Dedicated input-only engine — isolated from the playback engine so
    // topology changes and input/output device mismatches can't crash playback.
    private let engine = AVAudioEngine()
    private weak var state: AppState?
    private weak var audio: AudioEngineController?

    private var installed = false
    private var lastPublishedNote: String?
    private var lastDetectionTime: Date?
    private let holdInterval: TimeInterval = 0.4

    // YIN parameters
    private let threshold: Float = 0.15
    private let silenceRms: Float = 0.01

    init(state: AppState, audio: AudioEngineController) {
        self.state = state
        self.audio = audio
    }

    func start() {
        guard !installed else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("BackTrack: no audio input available — pitch detection disabled")
            return
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            installed = true
        } catch {
            NSLog("BackTrack: pitch detector engine failed to start: \(error)")
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let sampleRate = buffer.format.sampleRate

        let channel = floatData[0]
        var rms: Float = 0
        for i in 0..<frameCount {
            let s = channel[i]
            rms += s * s
        }
        rms = sqrt(rms / Float(frameCount))

        if rms < silenceRms {
            decayIfStale()
            return
        }

        if let freq = yinPitch(channel, count: frameCount, sampleRate: sampleRate) {
            let note = noteName(for: freq)
            lastDetectionTime = Date()
            publish(note: note, freq: freq)
        } else {
            decayIfStale()
        }
    }

    private func decayIfStale() {
        guard let t = lastDetectionTime else {
            publish(note: nil, freq: nil)
            return
        }
        if Date().timeIntervalSince(t) > holdInterval {
            publish(note: nil, freq: nil)
        }
    }

    private func publish(note: String?, freq: Float?) {
        if note == lastPublishedNote && note != nil { return }
        lastPublishedNote = note
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let state = self.state else { return }
            state.detectedNote = note
            state.detectedFrequency = freq
            if state.followDetection, let freq = freq {
                self.applyFollowImmediately(state: state, frequency: freq)
            }
        }
    }

    // Map detected pitch → nearest diatonic chord in the user's key scope
    // and apply it immediately (not queued). Follow mode ungrids chord
    // changes from the bar/beat structure so the pad tracks the voice as
    // fast as detection fires (~every 46 ms).
    private func applyFollowImmediately(state: AppState, frequency: Float) {
        let midi = 69.0 + 12.0 * log2(frequency / 440.0)
        let detectedPc = ((Int(midi.rounded()) % 12) + 12) % 12

        // Major: maj, min, min, maj, maj, min, min (vii° → min)
        // Minor: min, min, maj, min, min, maj, maj (ii° → min)
        let scale: [Int]
        let qualities: [Bool]
        if state.keyIsMajor {
            scale = [0, 2, 4, 5, 7, 9, 11]
            qualities = [true, false, false, true, true, false, false]
        } else {
            scale = [0, 2, 3, 5, 7, 8, 10]
            qualities = [false, false, true, false, false, true, true]
        }

        let offset = ((detectedPc - state.keyRoot) % 12 + 12) % 12
        var bestDegree = 0
        var bestDist = Int.max
        for (i, s) in scale.enumerated() {
            let raw = abs(s - offset)
            let dist = min(raw, 12 - raw)
            if dist < bestDist {
                bestDist = dist
                bestDegree = i
            }
        }

        let chordRoot = (state.keyRoot + scale[bestDegree]) % 12
        let chordIsMajor = qualities[bestDegree]

        if chordRoot == state.rootNote && chordIsMajor == state.isMajor {
            return
        }

        // Apply directly to committed state (not pending). Clear any
        // stale pending for these fields so a manual press queued right
        // before doesn't overwrite detection on the next bar.
        audio?.stopAllPads()
        state.rootNote = chordRoot
        state.isMajor = chordIsMajor
        state.pending.rootNote = nil
        state.pending.isMajor = nil

        // LVL 2 and 3 fire pad events on every 8th via the generator, so
        // the new chord is audible on the next Clock tick. LVL 1 only fires
        // on tick 0 ("sustained full bar"), so we retrigger explicitly.
        if state.complexity == 1, let audio = audio {
            for e in Generators.pads(state: state, tick: 0) { audio.trigger(e) }
        }
    }

    private func noteName(for frequency: Float) -> String {
        let midi = 69.0 + 12.0 * log2(frequency / 440.0)
        let rounded = Int(midi.rounded())
        let idx = ((rounded % 12) + 12) % 12
        let octave = rounded / 12 - 1
        return "\(AppState.noteNames[idx])\(octave)"
    }

    // YIN: de Cheveigné & Kawahara, 2002. Monophonic pitch estimation
    // via cumulative mean normalized difference function.
    private func yinPitch(_ p: UnsafePointer<Float>, count n: Int, sampleRate: Double) -> Float? {
        let maxLag = n / 2
        let minLag = max(2, Int(sampleRate / 1000.0))
        guard maxLag > minLag else { return nil }

        var d = [Float](repeating: 0, count: maxLag + 1)
        for tau in 1...maxLag {
            var sum: Float = 0
            let limit = n - tau
            var i = 0
            while i < limit {
                let diff = p[i] - p[i + tau]
                sum += diff * diff
                i += 1
            }
            d[tau] = sum
        }

        var cmndf = [Float](repeating: 1.0, count: maxLag + 1)
        var runningSum: Float = 0
        for tau in 1...maxLag {
            runningSum += d[tau]
            if runningSum > 0 {
                cmndf[tau] = d[tau] * Float(tau) / runningSum
            }
        }

        var tau = minLag
        while tau < maxLag {
            if cmndf[tau] < threshold {
                var best = tau
                while best + 1 < maxLag && cmndf[best + 1] < cmndf[best] {
                    best += 1
                }
                let refined = parabolicInterpolate(cmndf, around: best)
                return Float(sampleRate) / refined
            }
            tau += 1
        }
        return nil
    }

    private func parabolicInterpolate(_ a: [Float], around i: Int) -> Float {
        guard i > 0 && i < a.count - 1 else { return Float(i) }
        let y0 = a[i - 1], y1 = a[i], y2 = a[i + 1]
        let denom = y0 - 2 * y1 + y2
        if abs(denom) < 1e-9 { return Float(i) }
        return Float(i) + 0.5 * (y0 - y2) / denom
    }
}
