import AVFoundation
import Foundation

struct NoteEvent {
    enum Voice {
        case kick
        case snare
        case hihat
        case pad(pitchClass: Int)   // 0-11; engine pitches pad sample to this class
        case bass(pitchClass: Int)  // 0-11; engine pitches bass sample to this class
    }
    let voice: Voice
    let velocity: Float
}

// AVAudioEngine graph manager for the three voice families (drums,
// pad, bass) plus master mixing. Centralizes sample discovery, buffer
// loading, format normalization, and voice-pool management so the rest
// of the app can just call `trigger(_:)` without touching AVFoundation
// directly.
//
// Graph shape:
//
//   drum players → per-drum mixer ─┐
//   pad voices   → padMixer        ├→ masterMixer → mainMixer → output
//   bass voices  → bassMixer       ┘
//
// All audio data is converted at load time to a canonical 44.1 kHz
// stereo float32 format (see `canonicalFormat` below). This way a
// kit/sound cycle is a pure buffer-pointer swap — the engine never
// reconfigures node connections, which would require stopping
// playback. Conversion cost is paid once per sample at load.
//
// Pad and bass use voice pools (8 and 4 voices respectively) so
// overlapping notes from chord stacks / arpeggios / transitions don't
// clip each other. Each pooled voice is a short chain:
//   AVAudioPlayerNode → AVAudioUnitVarispeed (pitch shift)
// so the same recorded sample can be pitched to any of the 12 pitch
// classes on the fly.
final class AudioEngineController: ObservableObject {
    // Output-only engine: drums + pitched pad voices + pitched bass
    // voices. No live input.
    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    // Per-instrument mixers so K/S/H/P/B can tweak levels independently.
    private let kickMixer = AVAudioMixerNode()
    private let snareMixer = AVAudioMixerNode()
    private let hhMixer = AVAudioMixerNode()
    private let padMixer = AVAudioMixerNode()
    private let bassMixer = AVAudioMixerNode()

    // Drum players — one per drum, interrupts on re-trigger (the hard drum
    // attack masks the cut). Connected at canonical drum format so a kit
    // swap is a pure buffer-pointer swap.
    private let kickPlayer = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let hhPlayer = AVAudioPlayerNode()
    private var kickBuffer: AVAudioPCMBuffer?
    private var snareBuffer: AVAudioPCMBuffer?
    private var hhBuffer: AVAudioPCMBuffer?

    // Canonical format all buffers are normalized to, so no player
    // connection ever needs reconfiguration on kit/sound cycle.
    //
    // The initializer can return nil in principle, but only if the
    // parameters are invalid — and these are compile-time constants
    // for the most common PCM format in macOS (44.1 kHz stereo
    // float32). Wrapping in a closure with guard+fatalError so that
    // if the API is somehow broken on a user's machine, the crash
    // reads as "failed to create canonical audio format" rather than
    // a bare unwrap panic during startup.
    private static let canonicalFormat: AVAudioFormat = {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("""
                BackTrack: failed to create canonical audio format
                (44.1 kHz stereo float32). This is a system-level
                failure — something is wrong with the AVFoundation
                install. Try a reboot.
                """)
        }
        return fmt
    }()

    // Pad voice pool — 8 voices for chord stacks / arpeggios. Each voice:
    // player → varispeed (pitch shift) → padMixer.
    private struct PitchedVoice {
        let player: AVAudioPlayerNode
        let pitch: AVAudioUnitVarispeed
    }
    private var padVoices: [PitchedVoice] = []
    private var padVoiceIndex = 0
    private var padFadeGen: [Int] = []
    private var padBuffer: AVAudioPCMBuffer?
    private var padSourcePitchClass: Int?

    // Bass voice pool — 4 voices is enough for overlapping note transitions.
    private var bassVoices: [PitchedVoice] = []
    private var bassVoiceIndex = 0
    private var bassFadeGen: [Int] = []
    private var bassBuffer: AVAudioPCMBuffer?
    private var bassSourcePitchClass: Int?

    // Signal-present indicator for the OUT row.
    private let signalThreshold: Float = 0.01

    // Sound kits — each instrument scans its own directory for subfolders.
    private struct SoundKit {
        let name: String
        let directory: URL
    }
    private var drumKits: [SoundKit] = []
    private var padSounds: [SoundKit] = []
    private var bassSounds: [SoundKit] = []

    weak var state: AppState?

    init() {
        setupGraph()
        startEngine()
    }

    // MARK: - Graph setup

    private func setupGraph() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)

        for sub in [kickMixer, snareMixer, hhMixer, padMixer, bassMixer] {
            engine.attach(sub)
            engine.connect(sub, to: masterMixer, format: nil)
        }

        engine.attach(kickPlayer)
        engine.connect(kickPlayer, to: kickMixer, format: Self.canonicalFormat)
        engine.attach(snarePlayer)
        engine.connect(snarePlayer, to: snareMixer, format: Self.canonicalFormat)
        engine.attach(hhPlayer)
        engine.connect(hhPlayer, to: hhMixer, format: Self.canonicalFormat)

        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: Self.canonicalFormat)
            engine.connect(pitch, to: padMixer, format: Self.canonicalFormat)
            padVoices.append(PitchedVoice(player: player, pitch: pitch))
        }
        padFadeGen = Array(repeating: 0, count: padVoices.count)

        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: Self.canonicalFormat)
            engine.connect(pitch, to: bassMixer, format: Self.canonicalFormat)
            bassVoices.append(PitchedVoice(player: player, pitch: pitch))
        }
        bassFadeGen = Array(repeating: 0, count: bassVoices.count)

        // Tap master for the OUT activity dot.
        masterMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.markOutSignal(buffer)
        }
    }

    private func startEngine() {
        engine.prepare()
        do { try engine.start() } catch {
            NSLog("BackTrack: audio engine failed to start: \(error)")
        }
    }

    private func markOutSignal(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let ch = data[0]
        var sum: Float = 0
        for i in 0..<frames { sum += ch[i] * ch[i] }
        let rms = (sum / Float(frames)).squareRoot()
        if rms > signalThreshold {
            DispatchQueue.main.async { [weak self] in
                self?.state?.outLastSignal = Date()
            }
        }
    }

    // MARK: - Sample discovery

    private static let supportedExtensions = ["wav", "aif", "aiff", "mp3"]
    private static let extensionGlob = "{wav,aif,aiff,mp3}"

    func loadAllSamples() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Samples")

        drumKits = scanKits(in: base.appendingPathComponent("drums"))
        padSounds = scanKits(in: base.appendingPathComponent("pads"))
        bassSounds = scanKits(in: base.appendingPathComponent("bass"))

        // Load whichever sound is currently selected (or the first available).
        applyInitialSelections()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let state = self.state else { return }
            state.drumKitNames = self.drumKits.map { $0.name }
            state.padSoundNames = self.padSounds.map { $0.name }
            state.bassSoundNames = self.bassSounds.map { $0.name }
        }
    }

    private func scanKits(in dir: URL) -> [SoundKit] {
        var found: [SoundKit] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir)
                if exists && isDir.boolValue {
                    found.append(SoundKit(name: entry.lastPathComponent, directory: entry))
                }
            }
        }
        return found
    }

    private func applyInitialSelections() {
        var missing: [String] = []
        if let first = drumKits.first {
            loadDrumKit(first, missing: &missing)
        } else {
            missing.append("drums/<kit>/ (no drum kits found)")
        }
        if let first = padSounds.first {
            loadPadSound(first, missing: &missing)
        } else if !padSounds.isEmpty {
            missing.append("pads/<sound>/pad_<NOTE>.\(Self.extensionGlob)")
        }
        if let first = bassSounds.first {
            loadBassSound(first, missing: &missing)
        } else if !bassSounds.isEmpty {
            missing.append("bass/<sound>/bass_<NOTE>.\(Self.extensionGlob)")
        }

        DispatchQueue.main.async { [weak self] in
            self?.state?.missingSamples = missing
        }
    }

    // MARK: - Kit selection (by name, called from SongPlayer when song loads)

    func selectDrumKit(named name: String) {
        guard let kit = drumKits.first(where: { $0.name == name }) else {
            appendMissing("drum kit '\(name)' not found")
            return
        }
        var missing: [String] = []
        loadDrumKit(kit, missing: &missing)
        mergeMissing(missing)
    }

    func selectPadSound(named name: String) {
        guard let kit = padSounds.first(where: { $0.name == name }) else {
            appendMissing("pad sound '\(name)' not found")
            return
        }
        var missing: [String] = []
        loadPadSound(kit, missing: &missing)
        mergeMissing(missing)
    }

    func selectBassSound(named name: String) {
        guard let kit = bassSounds.first(where: { $0.name == name }) else {
            appendMissing("bass sound '\(name)' not found")
            return
        }
        var missing: [String] = []
        loadBassSound(kit, missing: &missing)
        mergeMissing(missing)
    }

    private func appendMissing(_ s: String) {
        DispatchQueue.main.async { [weak self] in
            self?.state?.missingSamples.append(s)
        }
    }

    private func mergeMissing(_ entries: [String]) {
        guard !entries.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.state?.missingSamples.append(contentsOf: entries)
        }
    }

    // MARK: - Loading

    private func loadDrumKit(_ kit: SoundKit, missing: inout [String]) {
        kickBuffer = loadDrum(name: "kick", in: kit, missing: &missing)
        snareBuffer = loadDrum(name: "snare", in: kit, missing: &missing)
        hhBuffer = loadDrum(name: "hh", in: kit, missing: &missing)
    }

    private func loadPadSound(_ kit: SoundKit, missing: inout [String]) {
        let (buf, pc) = loadPitchedSample(prefix: "pad_", in: kit, missing: &missing)
        padBuffer = buf
        padSourcePitchClass = pc
    }

    private func loadBassSound(_ kit: SoundKit, missing: inout [String]) {
        let (buf, pc) = loadPitchedSample(prefix: "bass_", in: kit, missing: &missing)
        bassBuffer = buf
        bassSourcePitchClass = pc
    }

    private func loadDrum(name: String, in kit: SoundKit, missing: inout [String]) -> AVAudioPCMBuffer? {
        if let url = findFile(base: name, in: kit.directory) {
            return loadBuffer(at: url, label: "\(kit.name)/\(url.lastPathComponent)", missing: &missing)
        }
        missing.append("\(kit.name)/\(name).\(Self.extensionGlob)")
        return nil
    }

    // Finds and loads a `<prefix><NOTE>.<ext>` file (e.g., pad_C.wav).
    // Returns the normalized buffer plus the parsed source pitch class.
    private func loadPitchedSample(
        prefix: String,
        in kit: SoundKit,
        missing: inout [String]
    ) -> (AVAudioPCMBuffer?, Int?) {
        guard let url = findPitchedFile(prefix: prefix, in: kit.directory) else {
            missing.append("\(kit.name)/\(prefix)<NOTE>.\(Self.extensionGlob)")
            return (nil, nil)
        }
        guard let pc = parsePitchClass(url.lastPathComponent, prefix: prefix) else {
            missing.append("\(kit.name)/\(url.lastPathComponent) (unparseable pitch)")
            return (nil, nil)
        }
        let buf = loadBuffer(at: url, label: "\(kit.name)/\(url.lastPathComponent)", missing: &missing)
        return (buf, pc)
    }

    private func findFile(base: String, in dir: URL) -> URL? {
        for ext in Self.supportedExtensions {
            let url = dir.appendingPathComponent("\(base).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func findPitchedFile(prefix: String, in dir: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return nil }
        let lowerPrefix = prefix.lowercased()
        return entries.first { url in
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix(lowerPrefix) else { return false }
            let ext = (name as NSString).pathExtension
            return Self.supportedExtensions.contains(ext)
        }
    }

    // Parse the pitch class from filenames like `pad_C.aif`, `pad_F#.wav`,
    // `pad_Bb.mp3`, `pad_C3.aif`. Octave digits are ignored.
    private func parsePitchClass(_ filename: String, prefix: String) -> Int? {
        let prefixLower = prefix.lowercased()
        let nameLower = filename.lowercased()
        guard nameLower.hasPrefix(prefixLower) else { return nil }
        let afterPrefix = nameLower.index(nameLower.startIndex, offsetBy: prefixLower.count)
        let dot = nameLower.lastIndex(of: ".") ?? nameLower.endIndex
        guard afterPrefix < dot else { return nil }
        let noteStr = String(nameLower[afterPrefix..<dot]).uppercased()
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
            case "B": pc -= 1
            default: break
            }
        }
        return ((pc % 12) + 12) % 12
    }

    // Read a file and normalize to canonicalFormat so players never need
    // reconfig. Returns nil on failure.
    private func loadBuffer(at url: URL, label: String, missing: inout [String]) -> AVAudioPCMBuffer? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            missing.append(label)
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let native = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                missing.append(label)
                return nil
            }
            try file.read(into: native)
            if native.format.isEqual(Self.canonicalFormat) { return native }
            if let converted = convertToCanonical(native) { return converted }
            missing.append("\(label) (format conversion failed)")
            return nil
        } catch {
            missing.append(label)
            return nil
        }
    }

    private func convertToCanonical(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: input.format, to: Self.canonicalFormat) else {
            return nil
        }
        let ratio = Self.canonicalFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.canonicalFormat, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error || err != nil { return nil }
        return out
    }

    // MARK: - Volume

    func applyMixVolumes(from state: AppState) {
        kickMixer.outputVolume = AppState.levelGain(state.kickLevel)
        snareMixer.outputVolume = AppState.levelGain(state.snareLevel)
        hhMixer.outputVolume = AppState.levelGain(state.hhLevel)
        padMixer.outputVolume = AppState.levelGain(state.padVolume)
        bassMixer.outputVolume = AppState.levelGain(state.bassVolume)
    }

    func setKickVolume(level: Int) { kickMixer.outputVolume = AppState.levelGain(level) }
    func setSnareVolume(level: Int) { snareMixer.outputVolume = AppState.levelGain(level) }
    func setHhVolume(level: Int) { hhMixer.outputVolume = AppState.levelGain(level) }
    func setPadVolume(level: Int) { padMixer.outputVolume = AppState.levelGain(level) }
    func setBassVolume(level: Int) { bassMixer.outputVolume = AppState.levelGain(level) }

    // MARK: - Playback

    // Schedules audio for the event AND records its trigger timestamp
    // for the HUD activity dots / synth visualizer pulses. Thread-safe:
    // AVAudioPlayerNode.scheduleBuffer is fine on any thread, and the
    // @Published timestamp write is auto-dispatched to main if we're
    // not already there. The Clock fires this from a background queue
    // so heavy main-thread visual work (post-effects redrawing) can't
    // delay audio scheduling.
    func trigger(_ event: NoteEvent) {
        // Audio first — independent of main-thread load.
        switch event.voice {
        case .kick:   play(buffer: kickBuffer, on: kickPlayer, volume: event.velocity)
        case .snare:  play(buffer: snareBuffer, on: snarePlayer, volume: event.velocity)
        case .hihat:  play(buffer: hhBuffer, on: hhPlayer, volume: event.velocity)
        case .pad(let pc):  playPad(pitchClass: pc, volume: event.velocity)
        case .bass(let pc): playBass(pitchClass: pc, volume: event.velocity)
        }

        // State timestamp — must be on main since AppState is @Published.
        let now = Date()
        let voice = event.voice
        let writeTimestamp: () -> Void = { [weak self] in
            guard let s = self?.state else { return }
            switch voice {
            case .kick:  s.kickLastTrigger = now
            case .snare: s.snareLastTrigger = now
            case .hihat: s.hhLastTrigger = now
            case .pad:   s.padLastTrigger = now
            case .bass:  s.bassLastTrigger = now
            }
        }
        if Thread.isMainThread {
            writeTimestamp()
        } else {
            DispatchQueue.main.async(execute: writeTimestamp)
        }
    }

    private func play(buffer: AVAudioPCMBuffer?, on player: AVAudioPlayerNode, volume: Float) {
        guard let buffer = buffer,
              buffer.format.isEqual(Self.canonicalFormat) else { return }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // Choose the shortest interval from source→target pitch class so the
    // sample stays in its recorded register instead of jumping octaves.
    private func rateFor(pitchClass target: Int, source: Int) -> Float {
        var shift = target - source
        if shift > 6 { shift -= 12 }
        if shift < -5 { shift += 12 }
        return Float(pow(2.0, Double(shift) / 12.0))
    }

    private func playPad(pitchClass: Int, volume: Float) {
        guard let buffer = padBuffer, let source = padSourcePitchClass else { return }
        let rate = rateFor(pitchClass: pitchClass, source: source)
        let idx = padVoiceIndex
        padVoiceIndex = (padVoiceIndex + 1) % padVoices.count
        padFadeGen[idx] += 1
        let gen = padFadeGen[idx]
        let voice = padVoices[idx]
        voice.pitch.rate = rate
        voice.player.volume = 0
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.player.isPlaying { voice.player.play() }

        let steps = 15
        let stepInterval: TimeInterval = 0.010   // ~150 ms swell-in
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * stepInterval) { [weak self] in
                guard let self = self, self.padFadeGen[idx] == gen else { return }
                voice.player.volume = volume * Float(step) / Float(steps)
            }
        }
    }

    private func playBass(pitchClass: Int, volume: Float) {
        guard let buffer = bassBuffer, let source = bassSourcePitchClass else { return }
        let rate = rateFor(pitchClass: pitchClass, source: source)
        let idx = bassVoiceIndex
        bassVoiceIndex = (bassVoiceIndex + 1) % bassVoices.count
        bassFadeGen[idx] += 1
        let gen = bassFadeGen[idx]
        let voice = bassVoices[idx]
        voice.pitch.rate = rate
        voice.player.volume = 0
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.player.isPlaying { voice.player.play() }

        // Bass wants a fast attack so the groove stays tight — ~12 ms.
        let steps = 4
        let stepInterval: TimeInterval = 0.003
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * stepInterval) { [weak self] in
                guard let self = self, self.bassFadeGen[idx] == gen else { return }
                voice.player.volume = volume * Float(step) / Float(steps)
            }
        }
    }

    // Stop all pad + bass voices with a short fade. Used on part-change so
    // sustained drone chords don't bleed into the new chord.
    func stopAllPadAndBass() {
        let steps = 8
        let stepInterval: TimeInterval = 0.006  // ~48 ms fade-out

        let padList = padVoices
        let padStart = padList.map { $0.player.volume }
        for i in 0..<padList.count { padFadeGen[i] += 1 }
        let padGens = padFadeGen

        let bassList = bassVoices
        let bassStart = bassList.map { $0.player.volume }
        for i in 0..<bassList.count { bassFadeGen[i] += 1 }
        let bassGens = bassFadeGen

        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * stepInterval) { [weak self] in
                guard let self = self else { return }
                let factor = Float(steps - step) / Float(steps)
                for (i, voice) in padList.enumerated() where self.padFadeGen[i] == padGens[i] {
                    voice.player.volume = padStart[i] * factor
                }
                for (i, voice) in bassList.enumerated() where self.bassFadeGen[i] == bassGens[i] {
                    voice.player.volume = bassStart[i] * factor
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps + 1) * stepInterval) { [weak self] in
            guard let self = self else { return }
            for (i, voice) in padList.enumerated() where self.padFadeGen[i] == padGens[i] {
                voice.player.stop()
                voice.player.volume = padStart[i]
            }
            for (i, voice) in bassList.enumerated() where self.bassFadeGen[i] == bassGens[i] {
                voice.player.stop()
                voice.player.volume = bassStart[i]
            }
        }
    }
}

