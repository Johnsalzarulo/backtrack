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
    // Output engine — everything that hits the speakers lives here:
    // drum players, and the live-input effect chain which is fed by
    // buffers captured on the input engine's tap. Decoupling input
    // and output into separate engines avoids AVAudioEngine's
    // input/output-device matching requirement and works cleanly
    // with arbitrary mic/interface/monitor routing.
    private let outputEngine = AVAudioEngine()
    private let outputMaster = AVAudioMixerNode()

    // Drum graph (outputEngine)
    private let kickMixer = AVAudioMixerNode()
    private let snareMixer = AVAudioMixerNode()
    private let hhMixer = AVAudioMixerNode()
    private let kickPlayer = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let hhPlayer = AVAudioPlayerNode()
    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var hhBuffer: AVAudioPCMBuffer?

    // Live-input effect path (outputEngine): liveInputPlayer → EQ → reverb → padMixer → master
    private let liveInputPlayer = AVAudioPlayerNode()
    private let inputEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let inputReverb = AVAudioUnitReverb()
    private let padMixer = AVAudioMixerNode()

    // Input engine — captures mic input only, no output routing.
    // Buffers from its tap are forwarded to liveInputPlayer above.
    private let inputEngine = AVAudioEngine()
    private let inputMixer = AVAudioMixerNode()
    private var tapFormat: AVAudioFormat?

    weak var state: AppState?
    weak var pitchDetector: PitchDetector?

    init() {
        setupOutputEngine()
        setupInputEngine()
        wireLiveInputPath()
        startEngines()
    }

    // MARK: - Output engine setup

    private func setupOutputEngine() {
        outputEngine.attach(outputMaster)
        outputEngine.connect(outputMaster, to: outputEngine.mainMixerNode, format: nil)

        for sub in [kickMixer, snareMixer, hhMixer, padMixer] {
            outputEngine.attach(sub)
            outputEngine.connect(sub, to: outputMaster, format: nil)
        }

        outputEngine.attach(kickPlayer)
        outputEngine.connect(kickPlayer, to: kickMixer, format: nil)
        outputEngine.attach(snarePlayer)
        outputEngine.connect(snarePlayer, to: snareMixer, format: nil)
        outputEngine.attach(hhPlayer)
        outputEngine.connect(hhPlayer, to: hhMixer, format: nil)

        let band = inputEQ.bands[0]
        band.filterType = .highPass
        band.frequency = 100
        band.bypass = false

        inputReverb.loadFactoryPreset(.largeHall2)
        inputReverb.wetDryMix = 85

        outputEngine.attach(liveInputPlayer)
        outputEngine.attach(inputEQ)
        outputEngine.attach(inputReverb)
    }

    // MARK: - Input engine setup (capture + tap)

    private func setupInputEngine() {
        inputEngine.attach(inputMixer)

        let input = inputEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("BackTrack: no audio input — live pad processing disabled")
            return
        }
        inputEngine.connect(input, to: inputMixer, format: format)
        tapFormat = format

        inputMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.pitchDetector?.process(buffer)
            // Forward captured audio into the output engine's live player.
            self.liveInputPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    // MARK: - Live-input path wiring

    // Wire liveInputPlayer through EQ + reverb + padMixer using the tap's
    // format. Done after the tap format is known so every connection in
    // the chain uses a matching PCM format and AVAudioEngine doesn't
    // silently drop audio through an implicit conversion.
    private func wireLiveInputPath() {
        guard let format = tapFormat else { return }
        outputEngine.connect(liveInputPlayer, to: inputEQ, format: format)
        outputEngine.connect(inputEQ, to: inputReverb, format: format)
        outputEngine.connect(inputReverb, to: padMixer, format: format)
    }

    private func startEngines() {
        outputEngine.prepare()
        do {
            try outputEngine.start()
        } catch {
            NSLog("BackTrack: output engine failed to start: \(error)")
        }
        // liveInputPlayer must be playing for its scheduled buffers to produce audio.
        if tapFormat != nil {
            liveInputPlayer.play()
        }
        inputEngine.prepare()
        do {
            try inputEngine.start()
        } catch {
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
        let wasRunning = outputEngine.isRunning
        if wasRunning { outputEngine.pause() }
        if let buf = kickBuffer { reconnectDrum(kickPlayer, mixer: kickMixer, format: buf.format) }
        if let buf = snareBuffer { reconnectDrum(snarePlayer, mixer: snareMixer, format: buf.format) }
        if let buf = hhBuffer { reconnectDrum(hhPlayer, mixer: hhMixer, format: buf.format) }
        if wasRunning {
            do { try outputEngine.start() } catch {
                NSLog("BackTrack: output engine failed to restart after rewire: \(error)")
            }
            if tapFormat != nil, !liveInputPlayer.isPlaying {
                liveInputPlayer.play()
            }
        }
    }

    private func reconnectDrum(_ player: AVAudioPlayerNode, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        player.stop()
        outputEngine.disconnectNodeOutput(player)
        outputEngine.connect(player, to: mixer, format: format)
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
