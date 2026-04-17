import Foundation
import SwiftUI

struct PendingChanges {
    var pattern: Int?

    var isEmpty: Bool {
        pattern == nil
    }
}

enum PadMode: Int, CaseIterable {
    case off
    case simple
    case shimmer
    case synth
    case strings

    var displayName: String {
        switch self {
        case .off:     return "OFF"
        case .simple:  return "SIMPLE"
        case .shimmer: return "SHIMMER"
        case .synth:   return "SYNTH"
        case .strings: return "STRINGS"
        }
    }

    var next: PadMode {
        let all = PadMode.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

final class AppState: ObservableObject {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    @Published var tempo: Double = 90
    @Published var isPlaying: Bool = false
    @Published var pattern: Int = 2  // 1–10; default is the classic kick1&3 / snare2&4 / hh quarters
    @Published var currentBeat: Int = 0
    @Published var pending: PendingChanges = PendingChanges()
    @Published var bpmFlash: Bool = false
    @Published var missingSamples: [String] = []

    // Volume levels 0–3: indexes into Self.levelGains (0%, 50%, 75%, 100%).
    @Published var kickLevel: Int = 3
    @Published var snareLevel: Int = 3
    @Published var hhLevel: Int = 3

    // Pad is no longer a volume-cycle instrument; P cycles through
    // pre-baked effect-chain presets defined by PadMode.
    @Published var padMode: PadMode = .simple

    // Last-trigger timestamps drive the per-instrument activity indicators
    // in the HUD. Pad is continuous (live-processed) so has no trigger.
    @Published var kickLastTrigger: Date = .distantPast
    @Published var snareLastTrigger: Date = .distantPast
    @Published var hhLastTrigger: Date = .distantPast

    @Published var detectedNote: String? = nil
    @Published var detectedFrequency: Float? = nil

    @Published var inputDevice: String? = nil
    @Published var outputDevice: String? = nil

    // Signal-present indicators for MIC and OUT rows: updated whenever
    // the respective tap sees RMS above a small threshold.
    @Published var micLastSignal: Date = .distantPast
    @Published var outLastSignal: Date = .distantPast

    // Discovered drum kits. Each kit is a subdirectory under drums/.
    @Published var kitNames: [String] = []
    @Published var currentKitIndex: Int = 0

    var currentKitName: String {
        guard !kitNames.isEmpty,
              currentKitIndex >= 0,
              currentKitIndex < kitNames.count else { return "—" }
        return kitNames[currentKitIndex]
    }

    static let levelGains: [Float] = [0.0, 0.5, 0.75, 1.0]
    static let maxLevel = levelGains.count - 1

    static func levelGain(_ level: Int) -> Float {
        levelGains[max(0, min(maxLevel, level))]
    }

    static func cycleDown(_ level: Int) -> Int {
        level == 0 ? maxLevel : level - 1
    }

    func applyPending() {
        if let p = pending.pattern { pattern = p }
        pending = PendingChanges()
    }
}
