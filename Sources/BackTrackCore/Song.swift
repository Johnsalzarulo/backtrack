import Foundation

// Raw JSON schema for a song file. Decoded by SongLoader then compiled
// into a playable Song. Part-level `pad`/`bass` are integers (0-3 complexity)
// while song-level `pad`/`bass` are strings (sound folder names) — the
// loader keeps them separate via the two distinct structs.
package struct SongJSON: Codable {
    package let name: String
    package let key: String?
    package let bpm: Double
    package let kit: String
    package let pad: String?
    package let bass: String?
    package let parts: [String: PartJSON]
    package let structure: [String]
    // Visual palette for the synth layer. "dark" (default) = black bg +
    // white ink; "light" = white bg + black ink. Per-song so different
    // tunes can feel different without a global toggle.
    package let theme: String?
    // Synth-layer visualization style. See VisualizerStyle for the list.
    // Defaults to "constellation" when omitted.
    package let visualizer: String?
    // Optional count-in. When > 0, pressing Space plays N bars of
    // metronome clicks (4 per bar at the song's BPM, beat 1 accented)
    // before the song actually starts. Default 0 = no count-in.
    package let countIn: Int?
}

package struct PartJSON: Codable {
    package let pattern: String
    package let chords: [String]
    package let repeats: Int?
    package let pad: Int?
    package let bass: Int?
    package let lyrics: String?
    // `visuals` accepts either a single filename string or an array of
    // filenames under ~/BackTrack/Visuals/. Single string is the common
    // case; array triggers cycling behavior controlled by `visualMode`.
    package let visuals: VisualList?
    // "bar" (default) advances visuals once per bar; "beat" advances
    // once per quarter-note beat. Ignored when visuals has <= 1 entry.
    package let visualMode: String?
    // Per-part visualizer override. When set, this part uses the named
    // style instead of the song-level `visualizer`. Same vocabulary as
    // the song-level field — see VisualizerStyle. Note: a part with a
    // `visuals` GIF always shows the GIF; the visualizer setting only
    // kicks in when there's no GIF.
    package let visualizer: String?
    // Post-processing effect for this part (glitch, tracking, chroma).
    // Each part declares its own — different sections of a song can
    // have different effects. Default "none".
    package let visualEffect: String?
    // Optional video clip (filename in ~/BackTrack/VideoClips/) that
    // plays once with audio when the part starts. Overrides the
    // visuals layer for the duration of the clip; falls back to the
    // part's normal visuals (GIF / synth) when the clip ends. The
    // backing track keeps playing alongside the clip's own audio.
    package let videoClip: String?
    // Audio gain for the clip, 0–100. Default 100. Only meaningful
    // when `videoClip` is set; ignored otherwise.
    package let videoClipVolume: Int?
}

// Polymorphic JSON container: decodes either `"visuals": "foo.gif"` or
// `"visuals": ["foo.gif","bar.gif"]`. Writes back as a plain string when
// there's a single entry so hand-authored files stay tidy.
package struct VisualList: Codable {
    package let items: [String]

    package init(_ items: [String]) { self.items = items }

    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if items.count == 1 {
            try container.encode(items[0])
        } else {
            try container.encode(items)
        }
    }
}

// Compiled, validated song ready for the playback engine.
package struct Song {
    package let sourceURL: URL        // path to the JSON file this was loaded from
    package let name: String
    package let key: String
    package let bpm: Double
    package let kit: String
    package let padSound: String?
    package let bassSound: String?
    package let parts: [String: Part]
    package let structure: [String]   // part names, in play order
    package let theme: VisualTheme          // synth-layer palette
    package let visualizer: VisualizerStyle // synth-layer visualization motif
    package let countIn: Int                // 0 = none; N > 0 plays N bars of clicks before start

    // Total bar count across the whole structure, for progress indicators.
    package var totalBars: Int {
        structure.reduce(0) { sum, name in
            sum + (parts[name]?.bars ?? 0)
        }
    }
}

// Synth-layer palette. `.dark` is the default (black background, white
// ink) — chosen to match the overwhelmingly black-and-white linocut /
// woodblock feel the project is going for. `.light` is a straight
// invert: white background, black ink.
package enum VisualTheme: String, CaseIterable {
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
//   oscilloscope  — full-bleed CRT-style waveform: each voice contributes
//                   a sine at its own frequency, weighted by the current
//                   pulse envelope, summed into a single scrolling trace
//                   over a 4×6 grid. Reads as a real instrument scope
//                   wired to the song's drum + bass + pad voices.
//   lyrics-block  — all lyrics as one justified paragraph, filling screen
//   lyrics-line   — current lyric line, one at a time
//   audience-drums — Guitar-Hero-style two-lane scrolling chart driven by
//                    the part's drum pattern. Activates audience-drummer
//                    mode: clock-driven kick/snare are muted and keys
//                    1/2 fire kick/snare samples directly.
package enum VisualizerStyle: String {
    case constellation
    case orbit
    case ink
    case squares
    case dots
    case lines
    case ripple
    case oscilloscope
    case lyricsBlock = "lyrics-block"
    case lyricsLine = "lyrics-line"
    case audienceDrums = "audience-drums"

    // Cycle order for the `M` key. Most distinctive motifs first so
    // cycling hits the signature styles before the simpler ones.
    // `audienceDrums` lives at the end — it's a behavioral mode, not
    // just a renderer, so casual cycling shouldn't land on it.
    package static let allCases: [VisualizerStyle] = [
        .constellation, .orbit, .ink,
        .squares, .dots, .lines, .ripple, .oscilloscope,
        .lyricsBlock, .lyricsLine,
        .audienceDrums
    ]
}

// How a part's visuals array advances during playback. Only meaningful
// when visuals.count > 1.
package enum VisualCycleMode: String, CaseIterable {
    case bar    // one image per bar
    case beat   // one image per quarter-note beat
}

package struct Part {
    package let name: String
    package let pattern: String        // name in patterns.json
    package let chords: [Chord]        // the progression; looped `repeats` times
    package let repeats: Int           // how many times the progression cycles (>= 1)
    package let padLevel: Int          // 0..3
    package let bassLevel: Int         // 0..3
    package let lyrics: String         // empty string if not provided
    package let visuals: [String]           // filenames under Visuals/; empty = none
    package let visualMode: VisualCycleMode // cycling behavior when visuals.count > 1
    package let visualizer: VisualizerStyle? // per-part override; nil = inherit from song
    package let visualEffect: PostEffect    // post-processing effect for this part; .none = no effect
    package let videoClip: String?          // filename under VideoClips/; nil = no clip
    package let videoClipVolume: Int        // 0..100; ignored unless videoClip is set

    // Derived: total bar count for this part.
    package var bars: Int { chords.count * repeats }

    // Chord active on the given bar index (0-based), wrapping around the
    // progression. Callers should check `bar < bars` before.
    package func chord(atBar bar: Int) -> Chord? {
        guard !chords.isEmpty else { return nil }
        return chords[bar % chords.count]
    }

    // Resolve the visual filename for the current playback position,
    // cycling through `visuals` based on `visualMode`. Returns nil if
    // this part has no visuals.
    package func visualFilename(bar: Int, beat: Int) -> String? {
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

// Tweak-mode field-update helpers: produce a copy of the Song / Part
// with one field replaced. Used by the tweak-mode cycle handlers in
// Tweak.swift; immutable struct semantics are preserved.

package extension Song {
    // True if any part needs a pad voice (padLevel > 0). When true,
    // the song JSON must declare a pad sound name; SongLoader rejects
    // the file otherwise. Tweak mode reads this to omit the `(none)`
    // stop from the padSound cycle for songs whose parts use pad,
    // so cycling can never produce a JSON that fails to reload.
    package var anyPartUsesPad: Bool {
        parts.values.contains { $0.padLevel > 0 }
    }

    // Same as above for bass — gates the `(none)` stop on the
    // bassSound cycle in tweak mode.
    package var anyPartUsesBass: Bool {
        parts.values.contains { $0.bassLevel > 0 }
    }

    package func with(kit value: String) -> Song {
        Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
             kit: value, padSound: padSound, bassSound: bassSound,
             parts: parts, structure: structure,
             theme: theme, visualizer: visualizer, countIn: countIn)
    }

    package func with(padSound value: String?) -> Song {
        Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
             kit: kit, padSound: value, bassSound: bassSound,
             parts: parts, structure: structure,
             theme: theme, visualizer: visualizer, countIn: countIn)
    }

    package func with(bassSound value: String?) -> Song {
        Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
             kit: kit, padSound: padSound, bassSound: value,
             parts: parts, structure: structure,
             theme: theme, visualizer: visualizer, countIn: countIn)
    }

    package func with(theme value: VisualTheme) -> Song {
        Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
             kit: kit, padSound: padSound, bassSound: bassSound,
             parts: parts, structure: structure,
             theme: value, visualizer: visualizer, countIn: countIn)
    }

    package func with(visualizer value: VisualizerStyle) -> Song {
        Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
             kit: kit, padSound: padSound, bassSound: bassSound,
             parts: parts, structure: structure,
             theme: theme, visualizer: value, countIn: countIn)
    }

    package func with(countIn value: Int) -> Song {
        Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
             kit: kit, padSound: padSound, bassSound: bassSound,
             parts: parts, structure: structure,
             theme: theme, visualizer: visualizer, countIn: value)
    }

    package func replacingPart(_ partName: String, with replacement: Part) -> Song {
        var newParts = parts
        newParts[partName] = replacement
        return Song(sourceURL: sourceURL, name: name, key: key, bpm: bpm,
                    kit: kit, padSound: padSound, bassSound: bassSound,
                    parts: newParts, structure: structure,
                    theme: theme, visualizer: visualizer, countIn: countIn)
    }
}

package extension Part {
    package func with(pattern value: String) -> Part {
        Part(name: name, pattern: value, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(padLevel value: Int) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: value, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(bassLevel value: Int) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: value,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(visuals value: [String]) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: value, visualMode: visualMode,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(visualMode value: VisualCycleMode) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: value,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(visualizer value: VisualizerStyle?) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: value, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(visualEffect value: PostEffect) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: visualizer, visualEffect: value,
             videoClip: videoClip, videoClipVolume: videoClipVolume)
    }

    package func with(videoClip value: String?) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: value, videoClipVolume: videoClipVolume)
    }

    package func with(videoClipVolume value: Int) -> Part {
        Part(name: name, pattern: pattern, chords: chords, repeats: repeats,
             padLevel: padLevel, bassLevel: bassLevel,
             lyrics: lyrics, visuals: visuals, visualMode: visualMode,
             visualizer: visualizer, visualEffect: visualEffect,
             videoClip: videoClip, videoClipVolume: value)
    }
}
