import Foundation

// Raw JSON schema for a song file. Decoded by SongLoader then compiled
// into a playable Song. Part-level `pad`/`bass` are integers (0-3 complexity)
// while song-level `pad`/`bass` are strings (sound folder names) — the
// loader keeps them separate via the two distinct structs.
struct SongJSON: Codable {
    let name: String
    let key: String?
    let bpm: Double
    let kit: String
    let pad: String?
    let bass: String?
    let parts: [String: PartJSON]
    let structure: [String]
    // Visual palette for the synth layer. "dark" (default) = black bg +
    // white ink; "light" = white bg + black ink. Per-song so different
    // tunes can feel different without a global toggle.
    let theme: String?
    // Synth-layer visualization style. See VisualizerStyle for the list.
    // Defaults to "sun" when omitted.
    let visualizer: String?
    // Optional count-in. When > 0, pressing Space plays N bars of
    // metronome clicks (4 per bar at the song's BPM, beat 1 accented)
    // before the song actually starts. Default 0 = no count-in.
    let countIn: Int?
}

struct PartJSON: Codable {
    let pattern: String
    let chords: [String]
    let repeats: Int?
    let pad: Int?
    let bass: Int?
    let lyrics: String?
    // `visuals` accepts either a single filename string or an array of
    // filenames under ~/BackTrack/Visuals/. Single string is the common
    // case; array triggers cycling behavior controlled by `visualMode`.
    let visuals: VisualList?
    // "bar" (default) advances visuals once per bar; "beat" advances
    // once per quarter-note beat. Ignored when visuals has <= 1 entry.
    let visualMode: String?
    // Per-part visualizer override. When set, this part uses the named
    // style instead of the song-level `visualizer`. Same vocabulary as
    // the song-level field — see VisualizerStyle. Note: a part with a
    // `visuals` GIF always shows the GIF; the visualizer setting only
    // kicks in when there's no GIF.
    let visualizer: String?
    // Post-processing effect for this part (glitch, tracking, chroma).
    // Each part declares its own — different sections of a song can
    // have different effects. Default "none".
    let visualEffect: String?
}

// Polymorphic JSON container: decodes either `"visuals": "foo.gif"` or
// `"visuals": ["foo.gif","bar.gif"]`. Writes back as a plain string when
// there's a single entry so hand-authored files stay tidy.
struct VisualList: Codable {
    let items: [String]

    init(_ items: [String]) { self.items = items }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            self.items = [single]
        } else if let arr = try? container.decode([String].self) {
            self.items = arr
        } else {
            throw DecodingError.typeMismatch(
                VisualList.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "expected string or array of strings for 'visuals'"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if items.count == 1 {
            try container.encode(items[0])
        } else {
            try container.encode(items)
        }
    }
}

// Compiled, validated song ready for the playback engine.
struct Song {
    let sourceURL: URL        // path to the JSON file this was loaded from
    let name: String
    let key: String
    let bpm: Double
    let kit: String
    let padSound: String?
    let bassSound: String?
    let parts: [String: Part]
    let structure: [String]   // part names, in play order
    let theme: VisualTheme          // synth-layer palette
    let visualizer: VisualizerStyle // synth-layer visualization motif
    let countIn: Int                // 0 = none; N > 0 plays N bars of clicks before start

    // Total bar count across the whole structure, for progress indicators.
    var totalBars: Int {
        structure.reduce(0) { sum, name in
            sum + (parts[name]?.bars ?? 0)
        }
    }
}

// Synth-layer palette. `.dark` is the default (black background, white
// ink) — chosen to match the overwhelmingly black-and-white linocut /
// woodblock feel the project is going for. `.light` is a straight
// invert: white background, black ink.
enum VisualTheme: String {
    case dark
    case light
}

// Synth-layer visualization style. The geometric styles share a shape
// vocabulary (subtle low-frequency wobble + 5-wide smoothed carved
// noise); the lyric styles display the current part's `lyrics` field
// typographically.
//
//   constellation — fixed star-positions that light up per voice (default)
//   orbit         — planets on continuous orbits, bar-progress arc on outer ring
//   ink           — ferrofluid-style central mass that deforms per voice
//   squares       — chunky wobbly rectangles
//   dots          — everything becomes circles / dot-rings
//   lines         — horizontal bars at fixed Y positions
//   ripple        — nested concentric rings, one per voice
//   lyrics-block  — all lyrics as one justified paragraph, filling screen
//   lyrics-line   — current lyric line, one at a time
enum VisualizerStyle: String {
    case constellation
    case orbit
    case ink
    case squares
    case dots
    case lines
    case ripple
    case lyricsBlock = "lyrics-block"
    case lyricsLine = "lyrics-line"

    // Cycle order for the `M` key. Most distinctive motifs first so
    // cycling hits the signature styles before the simpler ones.
    static let allCases: [VisualizerStyle] = [
        .constellation, .orbit, .ink,
        .squares, .dots, .lines, .ripple,
        .lyricsBlock, .lyricsLine
    ]
}

// How a part's visuals array advances during playback. Only meaningful
// when visuals.count > 1.
enum VisualCycleMode: String {
    case bar    // one image per bar
    case beat   // one image per quarter-note beat
}

struct Part {
    let name: String
    let pattern: String        // name in patterns.json
    let chords: [Chord]        // the progression; looped `repeats` times
    let repeats: Int           // how many times the progression cycles (>= 1)
    let padLevel: Int          // 0..3
    let bassLevel: Int         // 0..3
    let lyrics: String         // empty string if not provided
    let visuals: [String]           // filenames under Visuals/; empty = none
    let visualMode: VisualCycleMode // cycling behavior when visuals.count > 1
    let visualizer: VisualizerStyle? // per-part override; nil = inherit from song
    let visualEffect: PostEffect    // post-processing effect for this part; .none = no effect

    // Derived: total bar count for this part.
    var bars: Int { chords.count * repeats }

    // Chord active on the given bar index (0-based), wrapping around the
    // progression. Callers should check `bar < bars` before.
    func chord(atBar bar: Int) -> Chord? {
        guard !chords.isEmpty else { return nil }
        return chords[bar % chords.count]
    }

    // Resolve the visual filename for the current playback position,
    // cycling through `visuals` based on `visualMode`. Returns nil if
    // this part has no visuals.
    func visualFilename(bar: Int, beat: Int) -> String? {
        guard !visuals.isEmpty else { return nil }
        let idx: Int
        switch visualMode {
        case .bar:
            idx = bar % visuals.count
        case .beat:
            let slot = bar * 4 + beat
            idx = slot % visuals.count
        }
        return visuals[idx]
    }
}
