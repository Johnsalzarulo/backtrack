import Foundation

// Post-processing visual effect applied on top of the entire visuals
// window — runs above the synth visualizer, GIFs, lyric typography,
// AND the countdown view, so a single setting styles "what the
// audience sees" regardless of which deck is active.
//
// Songs and countdowns both carry an optional `visualEffect` field;
// the `E` key cycles through the available effects with a JSON-default
// slot at the end (same +1-default pattern as `M` for visualizers).
//
// `.none` is the no-op — it's an explicit slot in the cycle so the
// performer can kill an effect mid-show even if the song's JSON has
// one set. The implementations live in PostEffectsView.swift.
enum PostEffect: String {
    case none
    case glitch
    case tracking
    case chroma

    // Cycle order for the `E` key. `.none` is included so the
    // performer can explicitly turn effects off via the cycle without
    // having to wait for the JSON-default slot.
    static let allCases: [PostEffect] = [.none, .glitch, .tracking, .chroma]
}

// Shared parser used by both SongLoader and CountdownLoader. Returns
// nil for a missing/empty value so the loader can decide what default
// to apply. Throws with the field name in the error message so the
// HUD's issues block points at the right place.
enum PostEffectParser {
    static func parse(_ raw: String?, context: String) throws -> PostEffect? {
        switch raw?.lowercased() {
        case nil, "":
            return nil
        case "none":
            return PostEffect.none
        case "glitch":
            return .glitch
        case "tracking":
            return .tracking
        case "chroma":
            return .chroma
        case let other?:
            throw PostEffectParseError(
                description: "\(context) visualEffect '\(other)' — expected one of: none, glitch, tracking, chroma"
            )
        }
    }
}

struct PostEffectParseError: Error, CustomStringConvertible {
    let description: String
}
