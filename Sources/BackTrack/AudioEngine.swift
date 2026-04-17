import AVFoundation
import Foundation

struct NoteEvent {
    enum Voice {
        case kick
        case snare
        case hihat
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

    // Live input processing chain: mic → EQ (high-pass) → reverb → padMixer.
    // The padMixer's outputVolume is still the P key in the HUD — turning it
    // down silences the wet effect entirely.
    private let inputEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let inputReverb = AVAudioUnitReverb()
    private var inputWired = false

    weak var state: AppState?
    weak var pitchDetector: PitchDetector?

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

        // Input processing chain setup
        let band = inputEQ.bands[0]
        band.filterType = .highPass
        band.frequency = 100
        band.bypass = false

        inputReverb.loadFactoryPreset(.largeHall2)
        inputReverb.wetDryMix = 85  // mostly wet — the dry through-sound is louder

        engine.attach(inputEQ)
        engine.attach(inputReverb)

        wireInputChain()

        do {
            try engine.start()
        } catch {
            NSLog("BackTrack: audio engine failed to start: \(error)")
        }
    }

    private func wireInputChain() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("BackTrack: no audio input — live pad processing disabled")
            return
        }
        engine.connect(input, to: inputEQ, format: format)
        engine.connect(inputEQ, to: inputReverb, format: format)
        engine.connect(inputReverb, to: padMixer, format: nil)

        // Tap for pitch detection (display only).
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.pitchDetector?.process(buffer)
        }

        inputWired = true
    }

    private static let supportedExtensions = ["wav", "aif", "aiff", "mp3"]
    private static let extensionGlob = "{wav,aif,aiff,mp3}"

    func loadSamples() {
        var missing: [String] = []

        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Samples")
        let drums = base.appendingPathComponent("drums")

        kickBuffer = loadDrum(name: "kick", in: drums, missing: &missing)
        snareBuffer = loadDrum(name: "snare", in: drums, missing: &missing)
        hhBuffer = loadDrum(name: "hh", in: drums, missing: &missing)

        rewireForBufferFormats()

        DispatchQueue.main.async { [weak self] in
            self?.state?.missingSamples = missing
        }
    }

    // Reconnect each drum chain using the loaded buffer's native format so
    // AVAudioEngine doesn't silently resample a 44.1k buffer through a 48k
    // graph (shifts pitch by ~1.5 semitones).
    private func rewireForBufferFormats() {
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        if let buf = kickBuffer { reconnectDrum(kickPlayer, mixer: kickMixer, format: buf.format) }
        if let buf = snareBuffer { reconnectDrum(snarePlayer, mixer: snareMixer, format: buf.format) }
        if let buf = hhBuffer { reconnectDrum(hhPlayer, mixer: hhMixer, format: buf.format) }
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
        }
    }

    private func play(buffer: AVAudioPCMBuffer?, on player: AVAudioPlayerNode, volume: Float) {
        guard let buffer = buffer else { return }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
