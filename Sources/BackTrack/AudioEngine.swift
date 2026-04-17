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
    // Drum engine — output only. Isolated from the input engine so
    // the mic and the output device can be on different hardware
    // without AVAudioEngine choking on the mismatch.
    private let drumEngine = AVAudioEngine()
    private let drumMaster = AVAudioMixerNode()
    private let kickMixer = AVAudioMixerNode()
    private let snareMixer = AVAudioMixerNode()
    private let hhMixer = AVAudioMixerNode()
    private let kickPlayer = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let hhPlayer = AVAudioPlayerNode()
    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var hhBuffer: AVAudioPCMBuffer?

    // Input processing engine — mic → EQ → reverb → padMixer → output.
    // Outputs to the system default output just like the drum engine;
    // macOS's HAL mixes both streams on the device.
    private let inputEngine = AVAudioEngine()
    private let padMixer = AVAudioMixerNode()
    private let inputMixer = AVAudioMixerNode()  // tap point, avoids tapping inputNode directly
    private let inputEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let inputReverb = AVAudioUnitReverb()
    private var inputWired = false

    weak var state: AppState?
    weak var pitchDetector: PitchDetector?

    init() {
        setupDrumEngine()
        setupInputEngine()
        startEngines()
    }

    // MARK: - Drum engine

    private func setupDrumEngine() {
        drumEngine.attach(drumMaster)
        drumEngine.connect(drumMaster, to: drumEngine.mainMixerNode, format: nil)

        for sub in [kickMixer, snareMixer, hhMixer] {
            drumEngine.attach(sub)
            drumEngine.connect(sub, to: drumMaster, format: nil)
        }

        drumEngine.attach(kickPlayer)
        drumEngine.connect(kickPlayer, to: kickMixer, format: nil)
        drumEngine.attach(snarePlayer)
        drumEngine.connect(snarePlayer, to: snareMixer, format: nil)
        drumEngine.attach(hhPlayer)
        drumEngine.connect(hhPlayer, to: hhMixer, format: nil)
    }

    // MARK: - Input processing engine

    private func setupInputEngine() {
        inputEngine.attach(padMixer)
        inputEngine.connect(padMixer, to: inputEngine.mainMixerNode, format: nil)

        let band = inputEQ.bands[0]
        band.filterType = .highPass
        band.frequency = 100
        band.bypass = false

        inputReverb.loadFactoryPreset(.largeHall2)
        inputReverb.wetDryMix = 85

        inputEngine.attach(inputMixer)
        inputEngine.attach(inputEQ)
        inputEngine.attach(inputReverb)

        let input = inputEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("BackTrack: no audio input — live pad processing disabled")
            return
        }
        inputEngine.connect(input, to: inputMixer, format: format)
        inputEngine.connect(inputMixer, to: inputEQ, format: format)
        inputEngine.connect(inputEQ, to: inputReverb, format: format)
        inputEngine.connect(inputReverb, to: padMixer, format: nil)

        // Tap the intermediate mixer, not the input node directly, so the
        // tap and the processing chain don't contend for the same node.
        inputMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.pitchDetector?.process(buffer)
        }

        inputWired = true
    }

    private func startEngines() {
        drumEngine.prepare()
        do { try drumEngine.start() } catch {
            NSLog("BackTrack: drum engine failed to start: \(error)")
        }
        inputEngine.prepare()
        do { try inputEngine.start() } catch {
            NSLog("BackTrack: input engine failed to start: \(error)")
        }
    }

    // MARK: - Sample loading

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

        rewireDrumsForBufferFormats()

        DispatchQueue.main.async { [weak self] in
            self?.state?.missingSamples = missing
        }
    }

    private func rewireDrumsForBufferFormats() {
        let wasRunning = drumEngine.isRunning
        if wasRunning { drumEngine.pause() }
        if let buf = kickBuffer { reconnectDrum(kickPlayer, mixer: kickMixer, format: buf.format) }
        if let buf = snareBuffer { reconnectDrum(snarePlayer, mixer: snareMixer, format: buf.format) }
        if let buf = hhBuffer { reconnectDrum(hhPlayer, mixer: hhMixer, format: buf.format) }
        if wasRunning {
            do { try drumEngine.start() } catch {
                NSLog("BackTrack: drum engine failed to restart after rewire: \(error)")
            }
        }
    }

    private func reconnectDrum(_ player: AVAudioPlayerNode, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        player.stop()
        drumEngine.disconnectNodeOutput(player)
        drumEngine.connect(player, to: mixer, format: format)
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
