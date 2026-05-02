import Foundation

// One row in tweak mode's field list. Six song-level fields and six
// per-part fields; per-part cases carry the part name so the cursor
// knows which part it's editing.
//
// The list is rebuilt on every render from the current song's parts,
// in `structure` order, so cursor index N stably points to the same
// field as long as parts aren't added/removed (and tweak mode doesn't
// allow that — structure is JSON-only).
enum TweakField: Hashable {
    case kit
    case padSound
    case bassSound
    case theme
    case songVisualizer
    case countIn
    case partPadLevel(part: String)
    case partBassLevel(part: String)
    case partVisuals(part: String)
    case partVisualMode(part: String)
    case partVisualizer(part: String)
    case partVisualEffect(part: String)

    // Display label for the field's row in the HUD.
    var label: String {
        switch self {
        case .kit:                  return "Kit"
        case .padSound:             return "Pad Sound"
        case .bassSound:            return "Bass Sound"
        case .theme:                return "Theme"
        case .songVisualizer:       return "Visualizer"
        case .countIn:              return "Count-In"
        case .partPadLevel:         return "Pad Level"
        case .partBassLevel:        return "Bass Level"
        case .partVisuals:          return "Visuals"
        case .partVisualMode:       return "Visual Mode"
        case .partVisualizer:       return "Visualizer"
        case .partVisualEffect:     return "Visual Effect"
        }
    }
}

// All tweakable fields for a song, in render order: song-level fields
// first, then a block per unique part as it appears in `structure`.
// `[Self]` lets ContentView render rows AND KeyboardHandler index by
// cursor position with a single source of truth.
extension TweakField {
    static func fields(for song: Song) -> [TweakField] {
        var out: [TweakField] = [
            .kit, .padSound, .bassSound,
            .theme, .songVisualizer, .countIn
        ]
        var seen = Set<String>()
        for partName in song.structure where !seen.contains(partName) {
            guard song.parts[partName] != nil else { continue }
            seen.insert(partName)
            out.append(.partPadLevel(part: partName))
            out.append(.partBassLevel(part: partName))
            out.append(.partVisuals(part: partName))
            out.append(.partVisualMode(part: partName))
            out.append(.partVisualizer(part: partName))
            out.append(.partVisualEffect(part: partName))
        }
        return out
    }

    // Part name this field belongs to (nil for song-level fields).
    // Used to insert section breaks in the HUD's field list rendering.
    var partName: String? {
        switch self {
        case .kit, .padSound, .bassSound, .theme, .songVisualizer, .countIn:
            return nil
        case .partPadLevel(let p), .partBassLevel(let p),
             .partVisuals(let p), .partVisualMode(let p),
             .partVisualizer(let p), .partVisualEffect(let p):
            return p
        }
    }
}

// Runtime universe of valid values for fields whose cycle pulls from
// loaded resources (sample folder names, visuals filenames). Hardcoded
// enum cycles (theme, visualizer, etc.) don't need anything injected.
struct TweakUniverse {
    let kits: [String]
    let padSounds: [String]
    let bassSounds: [String]
    let visualsFiles: [String]
}

// Read the field's current value as a display string for the HUD.
// `(use song default)` and `(none)` surface optional-typed fields
// distinctly from named values so cycling reads naturally.
extension TweakField {
    func displayValue(in song: Song) -> String {
        switch self {
        case .kit:
            return song.kit
        case .padSound:
            return song.padSound ?? "(none)"
        case .bassSound:
            return song.bassSound ?? "(none)"
        case .theme:
            return song.theme.rawValue
        case .songVisualizer:
            return song.visualizer.rawValue
        case .countIn:
            return "\(song.countIn)"
        case .partPadLevel(let p):
            return "\(song.parts[p]?.padLevel ?? 0)"
        case .partBassLevel(let p):
            return "\(song.parts[p]?.bassLevel ?? 0)"
        case .partVisuals(let p):
            let v = song.parts[p]?.visuals ?? []
            return v.isEmpty ? "(none)" : v.joined(separator: ", ")
        case .partVisualMode(let p):
            return song.parts[p]?.visualMode.rawValue ?? VisualCycleMode.bar.rawValue
        case .partVisualizer(let p):
            return song.parts[p]?.visualizer?.rawValue ?? "(use song default)"
        case .partVisualEffect(let p):
            return song.parts[p]?.visualEffect.rawValue ?? PostEffect.none.rawValue
        }
    }
}

// Cycle the field's value forwards (next) or backwards (prev) and
// return a new Song with the change applied. Returns nil when the
// cycle is empty (no kits loaded, etc.) so the caller can no-op
// instead of producing a misleading "saved" toast.
extension TweakField {
    func cycled(forwards: Bool, in song: Song, universe: TweakUniverse) -> Song? {
        switch self {
        case .kit:
            guard let next = nextString(song.kit, in: universe.kits, forwards: forwards) else { return nil }
            return song.with(kit: next)

        case .padSound:
            guard let next = nextOptionalString(song.padSound, in: universe.padSounds, forwards: forwards) else { return nil }
            return song.with(padSound: next.value)

        case .bassSound:
            guard let next = nextOptionalString(song.bassSound, in: universe.bassSounds, forwards: forwards) else { return nil }
            return song.with(bassSound: next.value)

        case .theme:
            let cycle = VisualTheme.allCases
            let next = step(cycle, current: song.theme, forwards: forwards)
            return song.with(theme: next)

        case .songVisualizer:
            let cycle = VisualizerStyle.allCases
            let next = step(cycle, current: song.visualizer, forwards: forwards)
            return song.with(visualizer: next)

        case .countIn:
            let cycle = [0, 1, 2, 3, 4]
            let next = step(cycle, current: song.countIn, forwards: forwards)
            return song.with(countIn: next)

        case .partPadLevel(let p):
            guard let part = song.parts[p] else { return nil }
            let next = step([0, 1, 2, 3], current: part.padLevel, forwards: forwards)
            return song.replacingPart(p, with: part.with(padLevel: next))

        case .partBassLevel(let p):
            guard let part = song.parts[p] else { return nil }
            let next = step([0, 1, 2, 3], current: part.bassLevel, forwards: forwards)
            return song.replacingPart(p, with: part.with(bassLevel: next))

        case .partVisuals(let p):
            guard let part = song.parts[p] else { return nil }
            // Single-filename cycling only (per scope). Cycle through
            // (none) → file1 → file2 → ... → fileN → (none). Stored
            // as [] for none, [filename] otherwise.
            let current = part.visuals.first
            guard let next = nextOptionalString(current, in: universe.visualsFiles, forwards: forwards) else { return nil }
            let newList: [String] = next.value.map { [$0] } ?? []
            return song.replacingPart(p, with: part.with(visuals: newList))

        case .partVisualMode(let p):
            guard let part = song.parts[p] else { return nil }
            let next = step(VisualCycleMode.allCases, current: part.visualMode, forwards: forwards)
            return song.replacingPart(p, with: part.with(visualMode: next))

        case .partVisualizer(let p):
            guard let part = song.parts[p] else { return nil }
            // Cycle: nil ("use song default") → first style → ... → last → nil.
            let cycle: [VisualizerStyle?] = [nil] + VisualizerStyle.allCases.map(Optional.some)
            let next = step(cycle, current: part.visualizer, forwards: forwards)
            return song.replacingPart(p, with: part.with(visualizer: next))

        case .partVisualEffect(let p):
            guard let part = song.parts[p] else { return nil }
            let next = step(PostEffect.allCases, current: part.visualEffect, forwards: forwards)
            return song.replacingPart(p, with: part.with(visualEffect: next))
        }
    }
}

// MARK: - Cycle helpers

// Step through a fixed-order list, wrapping around at the ends.
// `current` not in the list is treated as "before the first entry"
// so the first forwards step lands on list[0].
private func step<T: Equatable>(_ list: [T], current: T, forwards: Bool) -> T {
    guard !list.isEmpty else { return current }
    let idx = list.firstIndex(of: current) ?? -1
    let n = list.count
    let nextIdx = forwards
        ? (idx + 1) % n
        : (idx - 1 + n) % n
    return list[nextIdx]
}

// Step through a list of strings, wrapping. Returns nil only when
// the list is empty (a single-entry list still produces the same
// value — caller can no-op via the `==` check the caller is welcome
// to skip; we still write it to disk so saving is idempotent).
private func nextString(_ current: String, in list: [String], forwards: Bool) -> String? {
    guard !list.isEmpty else { return nil }
    return step(list, current: current, forwards: forwards)
}

// Step through (nil) + list, where the first slot represents "no
// value" (e.g. padSound: nil). Returns a wrapper so callers can
// distinguish "set to nil" from "no change possible".
struct OptionalCycleResult {
    let value: String?
}

private func nextOptionalString(_ current: String?, in list: [String], forwards: Bool) -> OptionalCycleResult? {
    let cycle: [String?] = [nil] + list.map(Optional.some)
    guard cycle.count > 1 else { return nil }
    let idx = cycle.firstIndex { $0 == current } ?? 0
    let n = cycle.count
    let nextIdx = forwards
        ? (idx + 1) % n
        : (idx - 1 + n) % n
    return OptionalCycleResult(value: cycle[nextIdx])
}

// MARK: - Visuals library scan

// Flat list of media filenames in ~/BackTrack/Visuals/ for the
// `partVisuals` field cycle. Scanned once at app launch; adding a
// new visual file requires a restart (consistent with sample folders).
enum VisualsLibrary {
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "heic", "bmp",
        "gif",
        "mp4", "mov", "m4v", "mpg", "mpeg", "m2v", "webm", "avi"
    ]

    static func scanAll() -> [String] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Visuals")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
            .sorted()
    }
}
