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
    // Output engine: drums + the live-input effect chain which is fed
    // by buffers captured on the input engine's tap.
    private let outputEngine = AVAudioEngine()
    private let outputMaster = AVAudioMixerNode()

    // Drum graph
    private let kickMixer = AVAudioMixerNode()
    private let snareMixer = AVAudioMixerNode()
    private let hhMixer = AVAudioMixerNode()
    private let kickPlayer = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let hhPlayer = AVAudioPlayerNode()
    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var hhBuffer: AVAudioPCMBuffer?

    // Live-input effect path. Fixed topology; PadMode just varies gains +
    // EQ settings + reverb preset.
    //   liveInputPlayer → [ dry (EQ) | +12 (pitchUp) | -12 (pitchDown) ]
    //                   → preReverbMixer → inputReverb → padMixer → master
    private let liveInputPlayer = AVAudioPlayerNode()
    private let inputEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let pitchUpNode = AVAudioUnitTimePitch()
    private let pitchDownNode = AVAudioUnitTimePitch()
    private let dryGain = AVAudioMixerNode()
    private let pitchUpGain = AVAudioMixerNode()
    private let pitchDownGain = AVAudioMixerNode()
    private let preReverbMixer = AVAudioMixerNode()
    private let inputReverb = AVAudioUnitReverb()
    private let padMixer = AVAudioMixerNode()

    // Input engine: mic capture only, no output routing.
    private let inputEngine = AVAudioEngine()
    private let inputMixer = AVAudioMixerNode()
    private var tapFormat: AVAudioFormat?

    // Signal-present threshold for the MIC/OUT activity dots.
    private let signalThreshold: Float = 0.01

    weak var state: AppState?
    weak var pitchDetector: PitchDetector?

    init() {
        setupOutputEngine()
        setupInputEngine()
        wireLiveInputPath()
        installOutputSignalTap()
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

        // Pitch shifters run at fixed intervals; gain mixers decide whether
        // their contribution reaches the pre-reverb sum.
        pitchUpNode.pitch = 1200       // +12 semitones
        pitchDownNode.pitch = -1200    // −12 semitones

        outputEngine.attach(liveInputPlayer)
        outputEngine.attach(inputEQ)
        outputEngine.attach(pitchUpNode)
        outputEngine.attach(pitchDownNode)
        outputEngine.attach(dryGain)
        outputEngine.attach(pitchUpGain)
        outputEngine.attach(pitchDownGain)
        outputEngine.attach(preReverbMixer)
        outputEngine.attach(inputReverb)
    }

    // MARK: - Input engine (capture + tap)

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
            self.liveInputPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            self.markSignalIfAudible(buffer, keyPath: \.micLastSignal)
        }
    }

    // MARK: - Live-input path wiring

    private func wireLiveInputPath() {
        guard let format = tapFormat else { return }

        // Fan liveInputPlayer out to three parallel paths.
        let points: [AVAudioConnectionPoint] = [
            AVAudioConnectionPoint(node: inputEQ, bus: 0),
            AVAudioConnectionPoint(node: pitchUpNode, bus: 0),
            AVAudioConnectionPoint(node: pitchDownNode, bus: 0)
        ]
        outputEngine.connect(liveInputPlayer, to: points, fromBus: 0, format: format)

        // Each path → its gain stage → preReverbMixer (one input bus each).
        outputEngine.connect(inputEQ, to: dryGain, format: format)
        outputEngine.connect(dryGain, to: preReverbMixer, format: format)

        outputEngine.connect(pitchUpNode, to: pitchUpGain, format: format)
        outputEngine.connect(pitchUpGain, to: preReverbMixer, format: format)

        outputEngine.connect(pitchDownNode, to: pitchDownGain, format: format)
        outputEngine.connect(pitchDownGain, to: preReverbMixer, format: format)

        outputEngine.connect(preReverbMixer, to: inputReverb, format: format)
        outputEngine.connect(inputReverb, to: padMixer, format: format)
    }

    // MARK: - Output signal tap (for OUT activity dot)

    private func installOutputSignalTap() {
        outputMaster.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.markSignalIfAudible(buffer, keyPath: \.outLastSignal)
        }
    }

    private func markSignalIfAudible(
        _ buffer: AVAudioPCMBuffer,
        keyPath: ReferenceWritableKeyPath<AppState, Date>
    ) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channel = data[0]
        var sum: Float = 0
        for i in 0..<frames {
            let s = channel[i]
            sum += s * s
        }
        let rms = (sum / Float(frames)).squareRoot()
        if rms > signalThreshold {
            DispatchQueue.main.async { [weak self] in
                self?.state?[keyPath: keyPath] = Date()
            }
        }
    }

    private func startEngines() {
        outputEngine.prepare()
        do { try outputEngine.start() } catch {
            NSLog("BackTrack: output engine failed to start: \(error)")
        }
        if tapFormat != nil { liveInputPlayer.play() }
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

    // MARK: - Volume + pad mode

    func applyMixVolumes(from state: AppState) {
        kickMixer.outputVolume = AppState.levelGain(state.kickLevel)
        snareMixer.outputVolume = AppState.levelGain(state.snareLevel)
        hhMixer.outputVolume = AppState.levelGain(state.hhLevel)
    }

    func setKickVolume(level: Int) { kickMixer.outputVolume = AppState.levelGain(level) }
    func setSnareVolume(level: Int) { snareMixer.outputVolume = AppState.levelGain(level) }
    func setHhVolume(level: Int) { hhMixer.outputVolume = AppState.levelGain(level) }

    // Each PadMode is a preset: gains on the three parallel paths, the EQ's
    // single band, and the reverb preset + wet mix. OFF simply mutes padMixer.
    func apply(mode: PadMode) {
        let band = inputEQ.bands[0]
        band.bypass = false
        band.bandwidth = 1.0
        band.gain = 0

        switch mode {
        case .off:
            padMixer.outputVolume = 0.0

        case .simple:
            padMixer.outputVolume = 1.0
            band.filterType = .highPass
            band.frequency = 100
            dryGain.outputVolume = 1.0
            pitchUpGain.outputVolume = 0
            pitchDownGain.outputVolume = 0
            inputReverb.loadFactoryPreset(.largeHall2)
            inputReverb.wetDryMix = 85

        case .shimmer:
            padMixer.outputVolume = 1.0
            band.filterType = .highPass
            band.frequency = 150
            dryGain.outputVolume = 1.0
            pitchUpGain.outputVolume = 0.7
            pitchDownGain.outputVolume = 0
            inputReverb.loadFactoryPreset(.cathedral)
            inputReverb.wetDryMix = 95

        case .synth:
            padMixer.outputVolume = 1.0
            band.filterType = .lowPass
            band.frequency = 2000
            dryGain.outputVolume = 0.6
            pitchUpGain.outputVolume = 0
            pitchDownGain.outputVolume = 0.7
            inputReverb.loadFactoryPreset(.cathedral)
            inputReverb.wetDryMix = 92

        case .strings:
            padMixer.outputVolume = 1.0
            band.filterType = .parametric
            band.frequency = 800
            band.bandwidth = 1.0
            band.gain = 4
            dryGain.outputVolume = 1.0
            pitchUpGain.outputVolume = 0.35
            pitchDownGain.outputVolume = 0
            inputReverb.loadFactoryPreset(.largeHall)
            inputReverb.wetDryMix = 80
        }
    }

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
