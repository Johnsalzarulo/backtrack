import Foundation

// A setlist is the performer's ordered arrangement of songs and
// countdowns for a show. Lives under ~/BackTrack/Setlists/ as JSON.
// Multiple files can coexist (Saturday show, Tuesday acoustic, etc.);
// the `D` key cycles between them alphabetically.
//
// Each item references a song or countdown by name. Resolution against
// state.songs / state.countdowns happens at lineup-build time, so a
// setlist still loads even if some refs don't currently resolve —
// missing items surface in the HUD's issues block instead of
// preventing the show from starting.

// On-disk schema.
struct SetlistJSON: Codable {
    let name: String
    let items: [SetlistItemJSON]
}

struct SetlistItemJSON: Codable {
    let kind: String  // "song" | "countdown" | "interstitial" | "audience-interactive"
    let ref: String   // matches Song.name / Countdown.name / Interstitial.name / AudienceInteractive.name
}

// Compiled, validated setlist ready to drive lineup construction.
struct Setlist {
    let sourceURL: URL
    let name: String
    let items: [SetlistItemRef]
}

// Reference within a setlist — kind-discriminated, name-keyed.
// The actual Song/Countdown/Interstitial/AudienceInteractive is looked
// up at lineup-build time.
enum SetlistItemRef {
    case song(name: String)
    case countdown(name: String)
    case interstitial(name: String)
    case audienceInteractive(name: String)

    var name: String {
        switch self {
        case .song(let n), .countdown(let n), .interstitial(let n), .audienceInteractive(let n): return n
        }
    }
}

// What the navigable lineup actually contains. Fully-resolved Song,
// Countdown, Interstitial, or AudienceInteractive — by the time
// something becomes a LineupItem, the ref has been matched to an
// inventory entry.
//
// This is the shape arrows + Space act on: the unified item type
// every part of the app — Clock, KeyboardHandler, ContentView,
// VisualsView — switches on.
enum LineupItem {
    case song(Song)
    case countdown(Countdown)
    case interstitial(Interstitial)
    case audienceInteractive(AudienceInteractive)

    var name: String {
        switch self {
        case .song(let s): return s.name
        case .countdown(let c): return c.name
        case .interstitial(let i): return i.name
        case .audienceInteractive(let a): return a.name
        }
    }
}
