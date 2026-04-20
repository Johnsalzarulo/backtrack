import Foundation

// Raw JSON schema for a song file. Decoded by SongLoader then compiled
// into a playable Song. Part-level `pad`/`bass` are integers (0-3 complexity)
// while song-level `pad`/`bass` are strings (sound folder names) — the
// loader keeps them separate via the two distinct structs.
struct SongJSON: Decodable {
    let name: String
    let key: String?
    let bpm: Double
    let kit: String
    let pad: String?
    let bass: String?
    let parts: [String: PartJSON]
    let structure: [String]
}

struct PartJSON: Decodable {
    let pattern: Int
    let bars: Int
    let chords: [String]
    let pad: Int?
    let bass: Int?
    let lyrics: String?
}

// Compiled, validated song ready for the playback engine.
struct Song {
    let name: String
    let key: String
    let bpm: Double
    let kit: String
    let padSound: String?
    let bassSound: String?
    let parts: [String: Part]
    let structure: [String]   // part names, in play order

    // Total bar count across the whole structure, for progress indicators.
    var totalBars: Int {
        structure.reduce(0) { sum, name in
            sum + (parts[name]?.bars ?? 0)
        }
    }
}

struct Part {
    let name: String
    let pattern: Int           // 1..10, references patterns.json slot
    let bars: Int
    let chords: [Chord]        // length == bars
    let padLevel: Int          // 0..3
    let bassLevel: Int         // 0..3
    let lyrics: String         // empty string if not provided
}
