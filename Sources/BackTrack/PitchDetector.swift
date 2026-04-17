import AVFoundation
import Foundation

// Pitch detector for the DETECTED display. Consumes audio buffers from the
// main engine's input tap (installed in AudioEngineController) and publishes
// the detected note name to state.detectedNote. No longer owns its own engine,
// no longer drives chord changes — just a readout.
final class PitchDetector {
    private weak var state: AppState?

    private var lastPublishedNote: String?
    private var lastDetectionTime: Date?
    private let holdInterval: TimeInterval = 0.4

    // YIN parameters
    private let threshold: Float = 0.15
    private let silenceRms: Float = 0.01

    init(state: AppState) {
        self.state = state
    }

    func process(_ buffer: AVAudioPCMBuffer) {
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
        if note == lastPublishedNote { return }
        lastPublishedNote = note
        DispatchQueue.main.async { [weak self] in
            self?.state?.detectedNote = note
            self?.state?.detectedFrequency = freq
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
