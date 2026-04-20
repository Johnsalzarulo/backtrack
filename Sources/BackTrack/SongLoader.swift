import Foundation

// Discovers songs under ~/BackTrack/Songs/*.json, decodes + validates each,
// and returns compiled Songs plus a flat list of human-readable issues.
// Issues are surfaced in the HUD's SONG ISSUES block so authoring mistakes
// are visible without opening the terminal.
enum SongLoader {
    struct Result {
        let songs: [Song]
        let issues: [String]
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Songs")
    }

    static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    static func loadAll(from dir: URL) -> Result {
        var songs: [Song] = []
        var issues: [String] = []

        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            // Folder doesn't exist yet; not an error, just no songs.
            return Result(songs: [], issues: [])
        }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "json" }
             .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            issues.append("failed to read Songs directory: \(error.localizedDescription)")
            return Result(songs: [], issues: issues)
        }

        for url in entries {
            do {
                let data = try Data(contentsOf: url)
                let raw = try JSONDecoder().decode(SongJSON.self, from: data)
                let song = try compile(raw, sourceFilename: url.lastPathComponent)
                songs.append(song)
            } catch let error as SongValidationError {
                issues.append("\(url.lastPathComponent): \(error.description)")
            } catch {
                issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return Result(songs: songs, issues: issues)
    }

    // MARK: - Compilation

    private static func compile(_ raw: SongJSON, sourceFilename: String) throws -> Song {
        var parts: [String: Part] = [:]
        var usesPad = false
        var usesBass = false

        for (name, pjson) in raw.parts {
            let part = try compile(part: pjson, name: name)
            if part.padLevel > 0 { usesPad = true }
            if part.bassLevel > 0 { usesBass = true }
            parts[name] = part
        }

        // Structure must reference only defined parts.
        for ref in raw.structure where parts[ref] == nil {
            throw SongValidationError("unknown part '\(ref)' referenced in structure")
        }
        if raw.structure.isEmpty {
            throw SongValidationError("structure is empty")
        }
        // Require pad/bass sound names when any part actually uses them.
        if usesPad, (raw.pad?.isEmpty ?? true) {
            throw SongValidationError("parts use pad but song has no \"pad\" sound name")
        }
        if usesBass, (raw.bass?.isEmpty ?? true) {
            throw SongValidationError("parts use bass but song has no \"bass\" sound name")
        }

        return Song(
            name: raw.name,
            key: raw.key ?? "",
            bpm: raw.bpm,
            kit: raw.kit,
            padSound: usesPad ? raw.pad : nil,
            bassSound: usesBass ? raw.bass : nil,
            parts: parts,
            structure: raw.structure
        )
    }

    private static func compile(part: PartJSON, name: String) throws -> Part {
        guard Generators.allPatternNames().contains(part.pattern) else {
            throw SongValidationError(
                "part '\(name)' references pattern '\(part.pattern)' which isn't defined in patterns.json"
            )
        }
        guard !part.chords.isEmpty else {
            throw SongValidationError("part '\(name)' chords cannot be empty")
        }
        let repeats = part.repeats ?? 1
        guard repeats >= 1 else {
            throw SongValidationError("part '\(name)' repeats must be >= 1")
        }
        let padLevel = part.pad ?? 0
        let bassLevel = part.bass ?? 0
        guard (0...3).contains(padLevel) else {
            throw SongValidationError("part '\(name)' pad level \(padLevel) out of range (0-3)")
        }
        guard (0...3).contains(bassLevel) else {
            throw SongValidationError("part '\(name)' bass level \(bassLevel) out of range (0-3)")
        }

        var parsed: [Chord] = []
        for symbol in part.chords {
            do {
                parsed.append(try ChordParser.parse(symbol))
            } catch let err as ChordParseError {
                throw SongValidationError("part '\(name)' chord '\(symbol)' — \(err.description)")
            }
        }

        return Part(
            name: name,
            pattern: part.pattern,
            chords: parsed,
            repeats: repeats,
            padLevel: padLevel,
            bassLevel: bassLevel,
            lyrics: part.lyrics ?? ""
        )
    }
}

struct SongValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
