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
        guard let part = currentPart, currentBar < part.chords.count else { return nil }
        return part.chords[currentBar]
    }

    var nextChord: Chord? {
        guard let part = currentPart else { return nil }
        if currentBar + 1 < part.chords.count {
            return part.chords[currentBar + 1]
        }
        // Next bar is in the next part.
        guard let song = currentSong,
              currentPartIndex + 1 < song.structure.count,
              let nextPart = song.parts[song.structure[currentPartIndex + 1]],
              !nextPart.chords.isEmpty else { return nil }
        return nextPart.chords[0]
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
