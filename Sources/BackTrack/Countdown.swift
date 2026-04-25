import Foundation

// A "countdown" is a sibling of Song — same idea (a thing the
// performer can navigate to and start with Space) but it just runs a
// timer instead of playing audio. Lives under ~/BackTrack/Countdowns/
// as a JSON file. In the future songs and countdowns will mix into one
// setlist; for now they're two parallel decks toggled by the D key.
struct CountdownJSON: Codable {
    let name: String
    let duration: Double             // seconds; required
    let label: String?               // e.g. "Show begins in"; default below
    let messageInterval: Double?     // seconds per rotating message; default 6
    let messages: [String]?          // rotating one-liners; may be empty
}

// Compiled, validated countdown ready to display.
struct Countdown {
    let sourceURL: URL
    let name: String
    let duration: TimeInterval
    let label: String
    let messageInterval: TimeInterval
    let messages: [String]

    static let defaultLabel = "Show begins in"
    static let defaultMessageInterval: TimeInterval = 6
}

// Transport state for a countdown. The performer's mental model is
// Space = start / pause / resume; navigating away resets to .stopped.
// Time math: `elapsed` at any instant is computed from these values
// and the wall clock, so the view can poll once per frame without us
// running our own timer.
enum CountdownTransport {
    case stopped
    case running(startedAt: Date, accumulated: TimeInterval)
    case paused(elapsed: TimeInterval)

    // How much time has elapsed on the visible timer right now.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        switch self {
        case .stopped:
            return 0
        case .running(let startedAt, let accumulated):
            return accumulated + now.timeIntervalSince(startedAt)
        case .paused(let elapsed):
            return elapsed
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
