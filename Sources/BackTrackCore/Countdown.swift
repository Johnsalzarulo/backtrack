import Foundation

// A "countdown" is a sibling of Song — same idea (a thing the
// performer can navigate to and start with Space) but it just runs a
// timer instead of playing audio. Lives under ~/BackTrack/Countdowns/
// as a JSON file. In the future songs and countdowns will mix into one
// setlist; for now they're two parallel decks toggled by the D key.
package struct CountdownJSON: Codable {
    package let name: String
    package let duration: Double             // seconds; required
    package let label: String?               // e.g. "Show begins in"; default below
    package let messageInterval: Double?     // seconds per rotating message; default 6
    package let messages: [String]?          // rotating one-liners; may be empty
    package let style: String?               // "digital" | "pie" | "hourglass"; default "digital"
    package let visualEffect: String?        // post-processing effect; default "none"

    // Optional looping musical motif. Field names mirror the song
    // schema so the two decks share authoring muscle memory (see the
    // deck-symmetry note in the README). A countdown has a motif when
    // `chords`, `pattern`, or `sections` is present; otherwise it's a
    // silent timer exactly as before.
    package let bpm: Double?                 // tempo for the loop; default 90 when motif present
    package let kit: String?                 // drum kit folder name (= song `kit`)
    package let pattern: String?             // drum pattern name (= part `pattern`)
    package let chords: [String]?            // the progression, looped (= part `chords`)
    package let pad: String?                 // pad sound folder name (= song-level `pad`)
    package let padLevel: Int?               // 0-3 pad intensity; default 1 when `pad` set
    package let bass: String?                // bass sound folder name (= song-level `bass`)
    package let bassLevel: Int?              // 0-3 bass intensity; default 1 when `bass` set
    // Optional arrangement: an ordered list of sections that play in
    // sequence and then loop, each able to override padLevel / bassLevel
    // / chords / repeats. Lets one motif move between, say, sustained
    // chords and an arpeggio. When omitted, the top-level chords/levels
    // above act as a single implicit section (the original flat form).
    package let sections: [CountdownSectionJSON]?
}

// One section of a sectioned motif. Every field is optional: a section
// inherits the motif-level `chords` / `padLevel` / `bassLevel` for
// anything it doesn't override, so a typical section is just a level +
// a repeat count.
package struct CountdownSectionJSON: Codable {
    package let chords: [String]?
    package let padLevel: Int?
    package let bassLevel: Int?
    package let repeats: Int?        // times the section's progression plays; default 1
}

// Compiled, validated countdown ready to display.
package struct Countdown {
    package let sourceURL: URL
    package let name: String
    package let duration: TimeInterval
    package let label: String
    package let messageInterval: TimeInterval
    package let messages: [String]
    package let style: CountdownStyle
    package let visualEffect: PostEffect
    // nil = silent timer (the original behavior). Non-nil = a looping
    // musical bed that plays while the countdown transport is running.
    package let motif: CountdownMotif?

    package static let defaultLabel = "Show begins in"
    package static let defaultMessageInterval: TimeInterval = 6
    package static let defaultMotifBPM: Double = 90
}

// A countdown's looping musical bed. Plays on the same 16th-note grid
// songs use, reusing the same Generators + AudioEngine voices. Tempo,
// drums, and the pad/bass sound choices are fixed for the whole motif;
// the chord progression and pad/bass intensity are carried by an
// ordered list of `sections` that play in sequence and then loop. A
// flat (single-section) motif is just `sections.count == 1`; a
// drums-only motif has no sections.
package struct CountdownMotif {
    package let bpm: Double
    package let kit: String?               // drum kit name; nil = no drums
    package let pattern: String?           // drum pattern name; nil = no drums
    package let padSound: String?          // nil unless some section uses pad
    package let bassSound: String?         // nil unless some section uses bass
    package let sections: [CountdownSection]  // arrangement, in play order; empty = drums-only

    // Flattened per-bar arrangement: one entry per bar across every
    // section × its repeats, in play order. The Clock loops it with
    // `% count`, so the section structure collapses into a simple
    // per-bar lookup. Empty for a drums-only motif.
    package var barSlots: [MotifBar] {
        var slots: [MotifBar] = []
        for section in sections {
            guard !section.chords.isEmpty else { continue }
            for _ in 0..<section.repeats {
                for chord in section.chords {
                    slots.append(MotifBar(
                        chord: chord,
                        padLevel: section.padLevel,
                        bassLevel: section.bassLevel
                    ))
                }
            }
        }
        return slots
    }
}

// One section of the arrangement: a progression voiced at a given
// pad/bass intensity, repeated `repeats` times before the next section.
package struct CountdownSection {
    package let chords: [Chord]
    package let padLevel: Int     // 0-3
    package let bassLevel: Int    // 0-3
    package let repeats: Int      // >= 1
}

// A single bar of the flattened arrangement — which chord sounds and
// at what pad/bass intensity. Drives one bar of the Clock's motif loop.
package struct MotifBar {
    package let chord: Chord
    package let padLevel: Int
    package let bassLevel: Int
}

// How the countdown's remaining time is visualized. All three styles
// share the same chrome (label up top, rotating message below) — they
// only differ in how the timer itself renders.
//
//   digital   — giant M:SS:cc digits + thin progress bar (default)
//   pie       — clock-face pie shrinking clockwise from 12; small digits below
//   hourglass — sand draining from top to bottom triangle; small digits below
package enum CountdownStyle: String {
    case digital
    case pie
    case hourglass

    // Cycle order for the `M` key in countdown mode. Mirrors how
    // VisualizerStyle.allCases drives the song-deck cycle so the two
    // decks share keybinding muscle memory.
    package static let allCases: [CountdownStyle] = [.digital, .pie, .hourglass]
}

// Transport state for a countdown. The performer's mental model is
// Space = start / pause / resume; navigating away resets to .stopped.
// Time math: `elapsed` at any instant is computed from these values
// and the wall clock, so the view can poll once per frame without us
// running our own timer.
package enum CountdownTransport {
    case stopped
    case running(startedAt: Date, accumulated: TimeInterval)
    case paused(elapsed: TimeInterval)

    // How much time has elapsed on the visible timer right now. Clamped
    // to >= 0 so we never feed a negative elapsed into formatters or
    // array indexers downstream — TimelineView's `context.date` can run
    // a hair behind the `Date()` we stamped on the keystroke, which on
    // the first frame after .running otherwise produces idx = -1 and
    // crashes the rotating-message lookup.
    package func elapsed(at now: Date = Date()) -> TimeInterval {
        switch self {
        case .stopped:
            return 0
        case .running(let startedAt, let accumulated):
            return max(0, accumulated + now.timeIntervalSince(startedAt))
        case .paused(let elapsed):
            return max(0, elapsed)
        }
    }

    package var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
