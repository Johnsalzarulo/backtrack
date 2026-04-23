import Foundation
import SwiftUI

final class AppState: ObservableObject {
    // MARK: - Transport + tempo

    @Published var tempo: Double = 100
    @Published var isPlaying: Bool = false
    @Published var currentBeat: Int = 0
    @Published var bpmFlash: Bool = false

    // MARK: - Song state

    @Published var songs: [Song] = []
    @Published var currentSongIndex: Int = 0
    @Published var songIssues: [String] = []

    @Published var currentPartIndex: Int = 0    // index into current song's structure
    @Published var currentBar: Int = 0          // bar within current part (0-based)
    @Published var pendingPartIndex: Int? = nil // queued part jump on next bar
    @Published var loopCurrentPart: Bool = false // toggle: part repeats instead of advancing

    // Tracks whether the secondary visuals window should be visible. V
    // key toggles; ContentView observes this via onChange to call
    // openWindow / dismissWindow.
    @Published var visualsOpen: Bool = true

    // Pattern edits made via [ / ] that haven't been written back to JSON yet.
    // Key format: "<songName>/<partName>". Cleared on Cmd+S save.
    @Published var pendingPatternSaves: [String: String] = [:]

    // Live overrides for the synth-layer visualization, set via the `I`
    // (invert theme) and `M` (cycle motif) keys. Nil falls back to the
    // current song's JSON values. In-memory only — not persisted to the
    // song file, so JSON stays the source of truth for "what this song
    // looks like by default".
    @Published var themeOverride: VisualTheme? = nil
    @Published var visualizerOverride: VisualizerStyle? = nil

    // Effective values, merging override over the current song's JSON.
    var effectiveTheme: VisualTheme {
        themeOverride ?? currentSong?.theme ?? .dark
    }
    var effectiveVisualizer: VisualizerStyle {
        visualizerOverride ?? currentSong?.visualizer ?? .constellation
    }

    var currentSong: Song? {
        guard !songs.isEmpty, currentSongIndex >= 0, currentSongIndex < songs.count else {
            return nil
        }
        return songs[currentSongIndex]
    }

    var currentPartName: String? {
        guard let song = currentSong,
              currentPartIndex >= 0,
              currentPartIndex < song.structure.count else { return nil }
        return song.structure[currentPartIndex]
    }

    var currentPart: Part? {
        guard let name = currentPartName, let song = currentSong else { return nil }
        return song.parts[name]
    }

    var currentChord: Chord? {
        guard let part = currentPart else { return nil }
        return part.chord(atBar: currentBar)
    }

    // Resolves the current playback position (bar + beat within the
    // current part) to a full URL under ~/BackTrack/Visuals/, cycling
    // through the part's `visuals` array according to its `visualMode`.
    // Returns nil if the part has no visuals or the resolved file is
    // missing on disk.
    var currentPartVisualURL: URL? {
        guard let part = currentPart,
              let name = part.visualFilename(bar: currentBar, beat: currentBeat),
              !name.isEmpty else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Visuals")
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var nextChord: Chord? {
        guard let part = currentPart else { return nil }
        if currentBar + 1 < part.bars {
            return part.chord(atBar: currentBar + 1)
        }
        // Next bar belongs to the next part.
        guard let song = currentSong,
              currentPartIndex + 1 < song.structure.count,
              let nextPart = song.parts[song.structure[currentPartIndex + 1]] else { return nil }
        return nextPart.chord(atBar: 0)
    }

    // MARK: - Per-instrument mix (0-3: 0%, 50%, 75%, 100%)

    @Published var kickLevel: Int = 3
    @Published var snareLevel: Int = 3
    @Published var hhLevel: Int = 3
    @Published var padVolume: Int = 3
    @Published var bassVolume: Int = 3

    // MARK: - Activity timestamps (HUD dots)

    @Published var kickLastTrigger: Date = .distantPast
    @Published var snareLastTrigger: Date = .distantPast
    @Published var hhLastTrigger: Date = .distantPast
    @Published var padLastTrigger: Date = .distantPast
    @Published var bassLastTrigger: Date = .distantPast
    @Published var outLastSignal: Date = .distantPast

    // MARK: - Sample directories (discovered at load)

    @Published var drumKitNames: [String] = []
    @Published var padSoundNames: [String] = []
    @Published var bassSoundNames: [String] = []
    @Published var missingSamples: [String] = []

    // MARK: - Device display

    @Published var outputDevice: String? = nil

    // MARK: - Volume helpers

    static let levelGains: [Float] = [0.0, 0.5, 0.75, 1.0]
    static let maxLevel = levelGains.count - 1

    static func levelGain(_ level: Int) -> Float {
        levelGains[max(0, min(maxLevel, level))]
    }

    static func cycleDown(_ level: Int) -> Int {
        level == 0 ? maxLevel : level - 1
    }
}
