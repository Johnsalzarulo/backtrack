import Foundation

// Drum pattern definition (from ~/BackTrack/Samples/patterns.json).
package struct PatternDefinition: Codable {
    package let name: String
    package let kick: String
    package let snare: String
    package let hh: String
}

// Tick positions in a 16-step bar:
//   0  = 1,    1 = 1e,   2 = 1+,   3 = 1a
//   4  = 2,    5 = 2e,   6 = 2+,   7 = 2a
//   8  = 3,    9 = 3e,  10 = 3+,  11 = 3a
//  12  = 4,   13 = 4e,  14 = 4+,  15 = 4a
package enum Generators {
    package static let ticksPerBar = 16

    // MARK: - Drum patterns (1-10 from patterns.json)

    private struct CompiledPattern {
        let name: String
        let kick: [Int: Float]
        let snare: [Int: Float]
        let hh: [Int: Float]
    }

    // Keyed by pattern name. Songs reference patterns by their name string;
    // unknown names fall through to silence (and are also caught at song
    // load time via allPatternNames()).
    private static var patterns: [String: CompiledPattern] = compileAll(defaultDefinitions)

    package static func defaultPatternsURL() -> URL {
        MacContentStore().patternsURL()
    }

    package static func loadPatterns() {
        loadPatterns(from: defaultPatternsURL())
    }

    package static func loadPatterns(from url: URL) {
        // Start with built-in defaults; patterns.json overrides by name and
        // also contributes any new names.
        var result = compileAll(defaultDefinitions)
        guard FileManager.default.fileExists(atPath: url.path) else {
            patterns = result
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let defs = try JSONDecoder().decode([PatternDefinition].self, from: data)
            for def in defs {
                result[def.name] = compile(def)
            }
        } catch {
            NSLog("BackTrack: failed to load patterns.json: \(error)")
        }
        patterns = result
    }

    package static func drums(pattern name: String, tick: Int) -> [NoteEvent] {
        guard let p = patterns[name] else { return [] }
        var events: [NoteEvent] = []
        if let v = p.kick[tick] { events.append(.init(voice: .kick, velocity: v)) }
        if let v = p.snare[tick] { events.append(.init(voice: .snare, velocity: v)) }
        if let v = p.hh[tick] { events.append(.init(voice: .hihat, velocity: v)) }
        return events
    }

    package static func allPatternNames() -> Set<String> {
        Set(patterns.keys)
    }

    // Tick positions (0..15) where the pattern has a kick or snare hit.
    // Sorted ascending. Used by the audience-drums visualizer to lay out
    // the falling-note chart for the part. Ghost hits count — if you
    // chart it, you can play it. Unknown patterns return empty arrays.
    package static func patternHitTicks(pattern name: String) -> (kick: [Int], snare: [Int]) {
        guard let p = patterns[name] else { return (kick: [], snare: []) }
        return (kick: p.kick.keys.sorted(), snare: p.snare.keys.sorted())
    }

    private static func compileAll(_ defs: [PatternDefinition]) -> [String: CompiledPattern] {
        var result: [String: CompiledPattern] = [:]
        for def in defs { result[def.name] = compile(def) }
        return result
    }

    private static func compile(_ def: PatternDefinition) -> CompiledPattern {
        CompiledPattern(
            name: def.name,
            kick: parseGrid(def.kick),
            snare: parseGrid(def.snare),
            hh: parseGrid(def.hh)
        )
    }

    private static func parseGrid(_ s: String) -> [Int: Float] {
        let compact = s.filter { !$0.isWhitespace }
        var map: [Int: Float] = [:]
        for (i, c) in compact.enumerated() {
            if i >= ticksPerBar { break }
            switch c {
            case "X", "O": map[i] = 1.0
            case "x", "o": map[i] = 0.35
            default: break
            }
        }
        return map
    }

    // MARK: - Pad generator (per-chord, levels 0-3)

    // Emits pad events for `tick` within a bar that has `chord` as its
    // active chord. `chordChanged` is true only on the first tick of a
    // bar where the chord differs from the previous bar (or the song
    // just started) — used to decide whether level-1 drone retriggers.
    //
    // All levels only use the chord's actual tones (via chord.intervals):
    // plain triads get root / 3rd / 5th, explicit 7th chords add the 7th.
    // We never synthesize a 7th or 9th for a plain triad — that was
    // landing out of key on diatonic progressions (e.g. implicit dom7
    // on a G chord in D major adds F natural).
    package static func pad(level: Int, chord: Chord, tick: Int, chordChanged: Bool) -> [NoteEvent] {
        guard level > 0 else { return [] }

        let root = chord.rootPitchClass
        let third = (root + (chord.quality == .minor ? 3 : 4)) % 12
        let fifth = (root + 7) % 12

        switch level {
        case 1:
            // Drone: root + 5, one trigger per chord change on the
            // downbeat of the bar where the chord appears.
            if tick == 0 && chordChanged {
                return [
                    .init(voice: .pad(pitchClass: root), velocity: 0.55),
                    .init(voice: .pad(pitchClass: fifth), velocity: 0.55)
                ]
            }
            return []

        case 2:
            // Stabs: full triad on quarter notes.
            if tick % 4 == 0 {
                return [
                    .init(voice: .pad(pitchClass: root), velocity: 0.45),
                    .init(voice: .pad(pitchClass: third), velocity: 0.45),
                    .init(voice: .pad(pitchClass: fifth), velocity: 0.45)
                ]
            }
            return []

        case 3:
            // Arpeggio: cycle the chord's own tones on 8th notes.
            // Triads give root-3-5-root-3-5-... ; 7th chords add the
            // 7th into the cycle. Tick 0 always lands on the root.
            if tick % 2 == 0 {
                let notes = chord.intervals.map { (root + $0) % 12 }
                let idx = (tick / 2) % notes.count
                return [.init(voice: .pad(pitchClass: notes[idx]), velocity: 0.5)]
            }
            return []

        default:
            return []
        }
    }

    // MARK: - Bass generator (per-chord root, levels 0-3)

    package static func bass(level: Int, chord: Chord, tick: Int) -> [NoteEvent] {
        guard level > 0 else { return [] }
        let root = chord.rootPitchClass

        switch level {
        case 1:
            // Whole: root on beat 1 of the bar.
            if tick == 0 {
                return [.init(voice: .bass(pitchClass: root), velocity: 1.0)]
            }
            return []

        case 2:
            // Half: root on beats 1 and 3.
            if tick == 0 || tick == 8 {
                return [.init(voice: .bass(pitchClass: root), velocity: 1.0)]
            }
            return []

        case 3:
            // Pump: root on every quarter.
            if tick % 4 == 0 {
                return [.init(voice: .bass(pitchClass: root), velocity: 1.0)]
            }
            return []

        default:
            return []
        }
    }

    // MARK: - Built-in pattern defaults (used if patterns.json absent)

    private static let defaultDefinitions: [PatternDefinition] = [
        PatternDefinition(
            name: "Minimal pulse",
            kick:  "X . . . . . . . . . . . . . . .",
            snare: ". . . . . . . . . . . . . . . .",
            hh:    "X . . . X . . . X . . . X . . ."
        ),
        PatternDefinition(
            name: "Basic 4/4",
            kick:  "X . . . . . . . X . . . . . . .",
            snare: ". . . . X . . . . . . . X . . .",
            hh:    "X . . . X . . . X . . . X . . ."
        ),
        PatternDefinition(
            name: "Basic + ghost",
            kick:  "X . . . . . . . X . . . . . . .",
            snare: ". . . . X . . . . . . . X x . .",
            hh:    "X . X . X . X . X . X . X . X ."
        ),
        PatternDefinition(
            name: "Rock minimal",
            kick:  "X . . . . . . . . . . . . . . .",
            snare: ". . . . . . . . X . . . . . . .",
            hh:    "X . X . X . X . X . X . X . X ."
        ),
        PatternDefinition(
            name: "Rock basic",
            kick:  "X . . . . . X . . . . . . . . .",
            snare: ". . . . . . . . X . . . . . . .",
            hh:    "X . X . X . X . X . X . X . X ."
        ),
        PatternDefinition(
            name: "Rock 16th",
            kick:  "X . . . . . X . . . . . . . X .",
            snare: ". . . . . . . . X . . . . . . .",
            hh:    "X X X X X X X X X X X X X X X X"
        ),
        PatternDefinition(
            name: "Boom-bap minimal",
            kick:  "X . . . . . . . . . . . . . . .",
            snare: ". . . . . . . . X . . . . . . .",
            hh:    ". . . . X . . . . . . . X . . ."
        ),
        PatternDefinition(
            name: "Boom-bap",
            kick:  "X X . . . . . . . . . . . . . .",
            snare: ". . . . . . . . X . . . . x . .",
            hh:    "X . X . X . X . X . X . X . X ."
        ),
        PatternDefinition(
            name: "Boom-bap busy",
            kick:  "X X . . . . . . . . X . . . . .",
            snare: ". . . . . . . . X . . . . x . .",
            hh:    "X X X X X X X X X X X X X X X X"
        ),
        PatternDefinition(
            name: "Sparse",
            kick:  "X . . . . . . . X . . . . . . .",
            snare: ". . . . . . . . . . . . . x . .",
            hh:    "X . . . . . . . X . . . . . . ."
        ),
        // No drums at all — the "off" stop on the per-part Pattern
        // cycle in tweak mode. Compiles to empty event lists, so the
        // Clock's drum trigger pass produces nothing on every tick.
        // Pad and bass voices are unaffected; the part still has its
        // chord progression, lyrics, and visuals.
        PatternDefinition(
            name: "Silent",
            kick:  ". . . . . . . . . . . . . . . .",
            snare: ". . . . . . . . . . . . . . . .",
            hh:    ". . . . . . . . . . . . . . . ."
        )
    ]
}
