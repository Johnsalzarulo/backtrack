import Foundation
import SwiftUI

struct PendingChanges {
    var complexity: Int?

    var isEmpty: Bool {
        complexity == nil
    }
}

final class AppState: ObservableObject {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    @Published var tempo: Double = 90
    @Published var isPlaying: Bool = false
    @Published var complexity: Int = 1
    @Published var currentBeat: Int = 0
    @Published var pending: PendingChanges = PendingChanges()
    @Published var bpmFlash: Bool = false
    @Published var missingSamples: [String] = []

    // Volume levels 0–3: indexes into Self.levelGains (0%, 50%, 75%, 100%).
    @Published var kickLevel: Int = 3
    @Published var snareLevel: Int = 3
    @Published var hhLevel: Int = 3
    @Published var padLevel: Int = 3

    // Last-trigger timestamps drive the per-instrument activity indicators
    // in the HUD. Pad is continuous (live-processed) so has no trigger.
    @Published var kickLastTrigger: Date = .distantPast
    @Published var snareLastTrigger: Date = .distantPast
    @Published var hhLastTrigger: Date = .distantPast

    @Published var detectedNote: String? = nil
    @Published var detectedFrequency: Float? = nil

    @Published var inputDevice: String? = nil
    @Published var outputDevice: String? = nil

    static let levelGains: [Float] = [0.0, 0.5, 0.75, 1.0]
    static let maxLevel = levelGains.count - 1

    static func levelGain(_ level: Int) -> Float {
        levelGains[max(0, min(maxLevel, level))]
    }

    static func cycleDown(_ level: Int) -> Int {
        level == 0 ? maxLevel : level - 1
    }

    func applyPending() {
        if let c = pending.complexity { complexity = c }
        pending = PendingChanges()
    }
}
