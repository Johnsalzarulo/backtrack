import Foundation

// User-editable pattern definition matching the JSON schema at
// ~/BackTrack/Samples/patterns.json. Each grid is a string of 16
// characters (one per 16th-note tick in the bar):
//   `X` — full hit (velocity 1.0)
//   `x` — ghost hit (velocity 0.35)
//   `.` — rest
// Spaces are ignored, so you can write `X... X... X... X...` for
// readability.
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

    private struct CompiledPattern {
        let name: String
        let kick: [Int: Float]
        let snare: [Int: Float]
        let hh: [Int: Float]
    }

    // Active compiled patterns. Starts as the built-in defaults; loadPatterns
    // overrides slots that the user defines in patterns.json.
    private static var patterns: [CompiledPattern] = defaultDefinitions.map(compile)

    // Default file location — same samples directory users already write to.
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
        // Always start from defaults so users can override a subset.
        var result = defaultDefinitions.map(compile)

        guard FileManager.default.fileExists(atPath: url.path) else {
            patterns = result
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let defs = try JSONDecoder().decode([PatternDefinition].self, from: data)
            for (i, def) in defs.enumerated() where i < result.count {
                result[i] = compile(def)
            }
        } catch {
            NSLog("BackTrack: failed to load patterns.json: \(error)")
        }
        patterns = result
    }

    static func drums(state: AppState, tick: Int) -> [NoteEvent] {
        let idx = max(0, min(patterns.count - 1, state.pattern - 1))
        let p = patterns[idx]
        var events: [NoteEvent] = []
        if let v = p.kick[tick] { events.append(.init(voice: .kick, velocity: v)) }
        if let v = p.snare[tick] { events.append(.init(voice: .snare, velocity: v)) }
        if let v = p.hh[tick] { events.append(.init(voice: .hihat, velocity: v)) }
        return events
    }

    static func patternName(forIndex i: Int) -> String {
        let idx = max(0, min(patterns.count - 1, i))
        return patterns[idx].name
    }

    // MARK: - Compilation

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
            default: break  // '.' and any other char treated as rest
            }
        }
        return map
    }

    // MARK: - Built-in defaults

    // Ten patterns grouped in threes by feel (straight / rock / boom-bap),
    // each group ramping simple → busy. Pattern 10 is a sparse outlier
    // that resets the cycle.
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
