import Foundation

// Discovers and validates setlists under ~/BackTrack/Setlists/.
// Mirrors SongLoader / CountdownLoader's shape so the Coordinator can
// drive all three with the same plumbing — file watcher, issues list,
// alphabetical sort.
//
// Validation here is structural only (parseable JSON, known kind
// strings, non-empty refs). Whether each ref actually resolves to a
// song or countdown is checked at lineup-build time in AppState —
// a setlist file can outlive a particular song being renamed/deleted
// and the missing ref surfaces as a HUD issue instead of a load
// failure.
enum SetlistLoader {
    struct Result {
        let setlists: [Setlist]
        let issues: [String]
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Setlists")
    }

    static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    static func loadAll(from dir: URL) -> Result {
        var setlists: [Setlist] = []
        var issues: [String] = []

        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return Result(setlists: [], issues: [])
        }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "json" }
             .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            issues.append("failed to read Setlists directory: \(error.localizedDescription)")
            return Result(setlists: [], issues: issues)
        }

        for url in entries {
            do {
                let data = try Data(contentsOf: url)
                let raw = try JSONDecoder().decode(SetlistJSON.self, from: data)
                let setlist = try compile(raw, sourceURL: url)
                setlists.append(setlist)
            } catch let err as SetlistValidationError {
                issues.append("\(url.lastPathComponent): \(err.description)")
            } catch {
                issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return Result(setlists: setlists, issues: issues)
    }

    private static func compile(_ raw: SetlistJSON, sourceURL: URL) throws -> Setlist {
        guard !raw.name.isEmpty else {
            throw SetlistValidationError("name cannot be empty")
        }
        var items: [SetlistItemRef] = []
        for (idx, raw) in raw.items.enumerated() {
            guard !raw.ref.isEmpty else {
                throw SetlistValidationError("item \(idx + 1) has empty ref")
            }
            switch raw.kind.lowercased() {
            case "song":
                items.append(.song(name: raw.ref))
            case "countdown":
                items.append(.countdown(name: raw.ref))
            default:
                throw SetlistValidationError(
                    "item \(idx + 1) ('\(raw.ref)') kind '\(raw.kind)' — expected 'song' or 'countdown'"
                )
            }
        }
        return Setlist(sourceURL: sourceURL, name: raw.name, items: items)
    }
}

struct SetlistValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
