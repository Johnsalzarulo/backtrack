import Foundation

// Drum pattern definition (from ~/BackTrack/Samples/patterns.json).
struct PatternDefinition: Codable {
    let name: String
    let kick: String
    let snare: String
    let hh: String
}

// Tick positions in a 16-step bar:
//   0  = 1,    1 = 1e,   2 = 1+,   3 = 1a
//   4  = 2,    5 = 2e,   6 = 2+,   7 = 2a
//   8  = 3,    9 = 3e,  10 = 3+,  11 = 3a
//  12  = 4,   13 = 4e,  14 = 4+,  15 = 4a
enum Generators {
    static let ticksPerBar = 16

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

    static func defaultPatternsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Samples")
            .appendingPathComponent("patterns.json")
    }

    static func loadPatterns() {
        loadPatterns(from: defaultPatternsURL())
    }

    static func loadPatterns(from url: URL) {
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

    static func drums(pattern name: String, tick: Int) -> [NoteEvent] {
        guard let p = patterns[name] else { return [] }
        var events: [NoteEvent] = []
        if let v = p.kick[tick] { events.append(.init(voice: .kick, velocity: v)) }
        if let v = p.snare[tick] { events.append(.init(voice: .snare, velocity: v)) }
        if let v = p.hh[tick] { events.append(.init(voice: .hihat, velocity: v)) }
        return events
    }

    static func allPatternNames() -> Set<String> {
        Set(patterns.keys)
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
    static func pad(level: Int, chord: Chord, tick: Int, chordChanged: Bool) -> [NoteEvent] {
        guard level > 0 else { return [] }

        let root = chord.rootPitchClass
        let third = (root + (chord.quality == .minor ? 3 : 4)) % 12
        let fifth = (root + 7) % 12
        let seventh: Int = {
            switch chord.ext {
            case .none: return (root + 10) % 12   // default to dom7 color for LVL 3 extension
            case .dom7: return (root + 10) % 12
            case .maj7: return (root + 11) % 12
            }
        }()
        let ninth = (root + 14) % 12

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
            // Arpeggio: extended chord (+ 7th, 9th) cycling on 8th notes.
            if tick % 2 == 0 {
                let notes = [root, third, fifth, seventh, ninth]
                let idx = (tick / 2) % notes.count
                return [.init(voice: .pad(pitchClass: notes[idx]), velocity: 0.55)]
            }
            return []

        default:
            return []
        }
    }

    // MARK: - Bass generator (per-chord root, levels 0-3)

    static func bass(level: Int, chord: Chord, tick: Int) -> [NoteEvent] {
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
        )
    ]
}
