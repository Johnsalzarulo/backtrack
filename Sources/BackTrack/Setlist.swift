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
    let kind: String  // "song" | "countdown"
    let ref: String   // matches Song.name or Countdown.name
}

// Compiled, validated setlist ready to drive lineup construction.
struct Setlist {
    let sourceURL: URL
    let name: String
    let items: [SetlistItemRef]
}

// Reference within a setlist — kind-discriminated, name-keyed.
// The actual Song/Countdown is looked up at lineup-build time.
enum SetlistItemRef {
    case song(name: String)
    case countdown(name: String)

    var name: String {
        switch self {
        case .song(let n), .countdown(let n): return n
        }
    }
}

// What the navigable lineup actually contains. Either a fully-
// resolved song or a fully-resolved countdown — by the time something
// becomes a LineupItem, the ref has been matched to an inventory
// entry and we have the real model object.
//
// This is the shape arrows + Space act on: the unified item type that
// replaces the old "two parallel decks toggled by D" model.
enum LineupItem {
    case song(Song)
    case countdown(Countdown)

    var name: String {
        switch self {
        case .song(let s): return s.name
        case .countdown(let c): return c.name
        }
    }
}
