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
    let style: String?               // "digital" | "pie" | "hourglass"; default "digital"
}

// Compiled, validated countdown ready to display.
struct Countdown {
    let sourceURL: URL
    let name: String
    let duration: TimeInterval
    let label: String
    let messageInterval: TimeInterval
    let messages: [String]
    let style: CountdownStyle

    static let defaultLabel = "Show begins in"
    static let defaultMessageInterval: TimeInterval = 6
}

// How the countdown's remaining time is visualized. All three styles
// share the same chrome (label up top, rotating message below) — they
// only differ in how the timer itself renders.
//
//   digital   — giant M:SS:cc digits + thin progress bar (default)
//   pie       — clock-face pie shrinking clockwise from 12; small digits below
//   hourglass — sand draining from top to bottom triangle; small digits below
enum CountdownStyle: String {
    case digital
    case pie
    case hourglass
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

    // How much time has elapsed on the visible timer right now. Clamped
    // to >= 0 so we never feed a negative elapsed into formatters or
    // array indexers downstream — TimelineView's `context.date` can run
    // a hair behind the `Date()` we stamped on the keystroke, which on
    // the first frame after .running otherwise produces idx = -1 and
    // crashes the rotating-message lookup.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        switch self {
        case .stopped:
            return 0
        case .running(let startedAt, let accumulated):
            return max(0, accumulated + now.timeIntervalSince(startedAt))
        case .paused(let elapsed):
            return max(0, elapsed)
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
