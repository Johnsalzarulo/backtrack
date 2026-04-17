import Foundation
import SwiftUI

struct PendingChanges {
    var rootNote: Int?
    var isMajor: Bool?
    var complexity: Int?

    var isEmpty: Bool {
        rootNote == nil && isMajor == nil && complexity == nil
    }
}

final class AppState: ObservableObject {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    @Published var tempo: Double = 90
    @Published var isPlaying: Bool = false
    @Published var rootNote: Int = 0
    @Published var isMajor: Bool = false
    @Published var complexity: Int = 1
    @Published var currentBeat: Int = 0
    @Published var pending: PendingChanges = PendingChanges()
    @Published var bpmFlash: Bool = false
    @Published var missingSamples: [String] = []

    // Volume levels 0–4: 0=mute, 1=25%, 2=50%, 3=75%, 4=100%
    @Published var kickLevel: Int = 4
    @Published var snareLevel: Int = 4
    @Published var hhLevel: Int = 4
    @Published var padLevel: Int = 4

    @Published var detectedNote: String? = nil
    @Published var detectedFrequency: Float? = nil

    // Follow mode: detected pitch drives pad chord within a diatonic key scope.
    // keyRoot/keyIsMajor are the scale; rootNote/isMajor remain the current chord.
    @Published var followDetection: Bool = false
    @Published var keyRoot: Int = 0
    @Published var keyIsMajor: Bool = false

    @Published var inputDevice: String? = nil
    @Published var outputDevice: String? = nil

    static let maxLevel = 4

    static func levelGain(_ level: Int) -> Float {
        Float(max(0, min(maxLevel, level))) / Float(maxLevel)
    }

    static func cycleDown(_ level: Int) -> Int {
        level == 0 ? maxLevel : level - 1
    }

    func applyPending() {
        if let r = pending.rootNote { rootNote = r }
        if let m = pending.isMajor { isMajor = m }
        if let c = pending.complexity { complexity = c }
        pending = PendingChanges()
    }

    // The user-declared key (changes only on manual keystroke, immediate).
    var keyString: String {
        "\(Self.noteNames[keyRoot]) \(keyIsMajor ? "maj" : "min")"
    }

    // The chord the pad is currently playing (queued to bar boundaries).
    // In manual mode this matches the key; in follow mode it diverges per
    // the detected pitch.
    var chordString: String {
        "\(Self.noteNames[rootNote]) \(isMajor ? "maj" : "min")"
    }

    var pendingChordString: String? {
        guard pending.rootNote != nil || pending.isMajor != nil else { return nil }
        let root = pending.rootNote ?? rootNote
        let major = pending.isMajor ?? isMajor
        return "\(Self.noteNames[root]) \(major ? "maj" : "min")"
    }
}
