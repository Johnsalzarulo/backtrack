import AVFoundation
import Foundation

struct NoteEvent {
    enum Voice {
        case kick
        case snare
        case hihat
        case pad(semitonesFromRoot: Int)
    }
    let voice: Voice
    let velocity: Float
}

final class AudioEngineController: ObservableObject {
    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    private let kickMixer = AVAudioMixerNode()
    private let snareMixer = AVAudioMixerNode()
    private let hhMixer = AVAudioMixerNode()
    private let padMixer = AVAudioMixerNode()

    private let kickPlayer = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let hhPlayer = AVAudioPlayerNode()

    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var hhBuffer: AVAudioPCMBuffer?

    private struct PadVoice {
        let player: AVAudioPlayerNode
        let pitch: AVAudioUnitVarispeed
    }
    private var padVoices: [PadVoice] = []
    private var padVoiceIndex = 0
    private var padBuffer: AVAudioPCMBuffer?
    private var padSamplePitchClass: Int?
    private var padFadeGen: [Int] = []  // per-voice generation for fade-out arbitration

    weak var state: AppState?

    init() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)

        for sub in [kickMixer, snareMixer, hhMixer, padMixer] {
            engine.attach(sub)
            engine.connect(sub, to: masterMixer, format: nil)
        }

        engine.attach(kickPlayer)
        engine.connect(kickPlayer, to: kickMixer, format: nil)
        engine.attach(snarePlayer)
        engine.connect(snarePlayer, to: snareMixer, format: nil)
        engine.attach(hhPlayer)
        engine.connect(hhPlayer, to: hhMixer, format: nil)

        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: nil)
            engine.connect(pitch, to: padMixer, format: nil)
            padVoices.append(PadVoice(player: player, pitch: pitch))
        }
        padFadeGen = Array(repeating: 0, count: padVoices.count)

        do {
            try engine.start()
        } catch {
            NSLog("BackTrack: audio engine failed to start: \(error)")
        }
    }

    private static let supportedExtensions = ["wav", "aif", "aiff", "mp3"]
    private static let extensionGlob = "{wav,aif,aiff,mp3}"

    func loadSamples() {
        var missing: [String] = []

        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Samples")
        let drums = base.appendingPathComponent("drums")
        let pads = base.appendingPathComponent("pads")

        kickBuffer = loadDrum(name: "kick", in: drums, missing: &missing)
        snareBuffer = loadDrum(name: "snare", in: drums, missing: &missing)
        hhBuffer = loadDrum(name: "hh", in: drums, missing: &missing)

        if let padURL = findPadFile(in: pads) {
            padBuffer = loadBuffer(at: padURL, label: "pads/\(padURL.lastPathComponent)", missing: &missing)
            padSamplePitchClass = parsePitchClassFromFilename(padURL.lastPathComponent)
            if padSamplePitchClass == nil {
                missing.append("pads/\(padURL.lastPathComponent) (unparseable pitch)")
                padBuffer = nil
            }
        } else {
            missing.append("pads/pad_*.\(Self.extensionGlob)")
            padBuffer = nil
            padSamplePitchClass = nil
        }

        rewireForBufferFormats()

        DispatchQueue.main.async { [weak self] in
            self?.state?.missingSamples = missing
        }
    }

    // Reconnect each player chain using the loaded buffer's native format.
    // Prevents AVAudioEngine from silently resampling a 44.1k buffer through a 48k
    // graph (or vice versa), which shifts pitch by ~1.5 semitones.
    private func rewireForBufferFormats() {
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        if let buf = kickBuffer { reconnectDrum(kickPlayer, mixer: kickMixer, format: buf.format) }
        if let buf = snareBuffer { reconnectDrum(snarePlayer, mixer: snareMixer, format: buf.format) }
        if let buf = hhBuffer { reconnectDrum(hhPlayer, mixer: hhMixer, format: buf.format) }
        if let buf = padBuffer { reconnectPadVoices(format: buf.format) }
        if wasRunning {
            do { try engine.start() } catch {
                NSLog("BackTrack: audio engine failed to restart after rewire: \(error)")
            }
        }
    }

    private func reconnectDrum(_ player: AVAudioPlayerNode, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        player.stop()
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: mixer, format: format)
    }

    private func reconnectPadVoices(format: AVAudioFormat) {
        for voice in padVoices {
            voice.player.stop()
            engine.disconnectNodeOutput(voice.player)
            engine.disconnectNodeOutput(voice.pitch)
            engine.connect(voice.player, to: voice.pitch, format: format)
            engine.connect(voice.pitch, to: padMixer, format: format)
        }
    }

    private func loadDrum(name: String, in dir: URL, missing: inout [String]) -> AVAudioPCMBuffer? {
        if let url = findDrumFile(base: name, in: dir) {
            return loadBuffer(at: url, label: "drums/\(url.lastPathComponent)", missing: &missing)
        }
        missing.append("drums/\(name).\(Self.extensionGlob)")
        return nil
    }

    private func findDrumFile(base: String, in dir: URL) -> URL? {
        for ext in Self.supportedExtensions {
            let url = dir.appendingPathComponent("\(base).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func findPadFile(in dir: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        return entries.first { url in
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix("pad_") else { return false }
            let ext = (name as NSString).pathExtension
            return Self.supportedExtensions.contains(ext)
        }
    }

    private func loadBuffer(at url: URL, label: String, missing: inout [String]) -> AVAudioPCMBuffer? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            missing.append(label)
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                missing.append(label)
                return nil
            }
            try file.read(into: buffer)
            return buffer
        } catch {
            missing.append(label)
            return nil
        }
    }

    // Extracts the pitch class (0–11) from filenames like `pad_C.aif`, `pad_F#.wav`,
    // `pad_Bb.mp3`, `pad_C3.aif`. Octave digits (if any) are ignored.
    private func parsePitchClassFromFilename(_ name: String) -> Int? {
        guard let underscore = name.firstIndex(of: "_") else { return nil }
        let afterUnderscore = name.index(after: underscore)
        let dot = name.lastIndex(of: ".") ?? name.endIndex
        guard afterUnderscore < dot else { return nil }
        let noteStr = String(name[afterUnderscore..<dot]).uppercased()
        guard let first = noteStr.first else { return nil }
        var pc: Int
        switch first {
        case "C": pc = 0
        case "D": pc = 2
        case "E": pc = 4
        case "F": pc = 5
        case "G": pc = 7
        case "A": pc = 9
        case "B": pc = 11
        default: return nil
        }
        let idx = noteStr.index(after: noteStr.startIndex)
        if idx < noteStr.endIndex {
            switch noteStr[idx] {
            case "#": pc += 1
            case "B": pc -= 1  // 'b' flat (note we already uppercased); handles Bb, Cb, etc.
            default: break
            }
        }
        return ((pc % 12) + 12) % 12
    }

    // MARK: - Volume

    func applyVolumes(from state: AppState) {
        kickMixer.outputVolume = AppState.levelGain(state.kickLevel)
        snareMixer.outputVolume = AppState.levelGain(state.snareLevel)
        hhMixer.outputVolume = AppState.levelGain(state.hhLevel)
        padMixer.outputVolume = AppState.levelGain(state.padLevel)
    }

    func setKickVolume(level: Int) { kickMixer.outputVolume = AppState.levelGain(level) }
    func setSnareVolume(level: Int) { snareMixer.outputVolume = AppState.levelGain(level) }
    func setHhVolume(level: Int) { hhMixer.outputVolume = AppState.levelGain(level) }
    func setPadVolume(level: Int) { padMixer.outputVolume = AppState.levelGain(level) }

    // MARK: - Playback

    func trigger(_ event: NoteEvent) {
        let now = Date()
        switch event.voice {
        case .kick:
            state?.kickLastTrigger = now
            play(buffer: kickBuffer, on: kickPlayer, volume: event.velocity)
        case .snare:
            state?.snareLastTrigger = now
            play(buffer: snareBuffer, on: snarePlayer, volume: event.velocity)
        case .hihat:
            state?.hhLastTrigger = now
            play(buffer: hhBuffer, on: hhPlayer, volume: event.velocity)
        case .pad(let offset):
            state?.padLastTrigger = now
            playPad(semitonesFromRoot: offset, volume: event.velocity)
        }
    }

    private func play(buffer: AVAudioPCMBuffer?, on player: AVAudioPlayerNode, volume: Float) {
        guard let buffer = buffer else { return }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func playPad(semitonesFromRoot offset: Int, volume: Float) {
        guard let buffer = padBuffer,
              let samplePc = padSamplePitchClass,
              let state = self.state else { return }

        // Map user root to nearest interval from sample's pitch class (range [-6, +5]).
        // This keeps chords in the sample's native register instead of jumping up or down an octave.
        var rootShift = state.rootNote - samplePc
        if rootShift > 6 { rootShift -= 12 }
        if rootShift < -5 { rootShift += 12 }

        let totalSemitones = Double(rootShift + offset)
        let rate = pow(2.0, totalSemitones / 12.0)

        let idx = padVoiceIndex
        padVoiceIndex = (padVoiceIndex + 1) % padVoices.count
        padFadeGen[idx] += 1  // invalidate any in-flight fade on this voice
        let gen = padFadeGen[idx]
        let voice = padVoices[idx]
        voice.pitch.rate = Float(rate)
        // Start silent, then ramp up over ~150 ms for a gentle swell-in.
        // Masks detection latency musically and gives the pad more body.
        // Generation check aborts the ramp if the voice is re-triggered
        // before the fade-in finishes.
        voice.player.volume = 0
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.player.isPlaying { voice.player.play() }
        let steps = 15
        let stepInterval: TimeInterval = 0.010  // 150 ms total
        let target = volume
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * stepInterval) { [weak self] in
                guard let self = self, self.padFadeGen[idx] == gen else { return }
                voice.player.volume = target * Float(step) / Float(steps)
            }
        }
    }

    // Fade pad voices to zero over ~150 ms via DispatchQueue-stepped ramps
    // on AVAudioPlayerNode.volume, then stop the players. Matches the
    // fade-in duration for a symmetric swell-out; also eliminates clicks
    // from hard stop() mid-sustain. Per-voice generation counters ensure
    // a new trigger that reuses a voice mid-fade doesn't get stomped.
    func stopAllPads() {
        let steps = 15
        let stepInterval: TimeInterval = 0.010  // 150 ms total
        let voices = padVoices
        let startVolumes = voices.map { $0.player.volume }
        for i in 0..<voices.count {
            padFadeGen[i] += 1
        }
        let gens = padFadeGen

        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * stepInterval) { [weak self] in
                guard let self = self else { return }
                let factor = Float(steps - step) / Float(steps)
                for (i, voice) in voices.enumerated() {
                    if self.padFadeGen[i] == gens[i] {
                        voice.player.volume = startVolumes[i] * factor
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps + 1) * stepInterval) { [weak self] in
            guard let self = self else { return }
            for (i, voice) in voices.enumerated() {
                if self.padFadeGen[i] == gens[i] {
                    voice.player.stop()
                    voice.player.volume = startVolumes[i]
                }
            }
        }
    }
}
