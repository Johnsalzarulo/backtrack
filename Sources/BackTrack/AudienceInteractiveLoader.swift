import Foundation

// Discovers and validates audience interactives under
// ~/BackTrack/AudienceInteractives/. Mirrors the shape of the other
// loaders so the Coordinator can drive every inventory through the
// same plumbing — directory scan, JSON decode, structural validate,
// emit issues for the HUD's issues block.
enum AudienceInteractiveLoader {
    struct Result {
        let interactives: [AudienceInteractive]
        let issues: [String]
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("AudienceInteractives")
    }

    static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    static func loadAll(from dir: URL) -> Result {
        var interactives: [AudienceInteractive] = []
        var issues: [String] = []

        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return Result(interactives: [], issues: [])
        }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "json" }
             .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            issues.append("failed to read AudienceInteractives directory: \(error.localizedDescription)")
            return Result(interactives: [], issues: issues)
        }

        for url in entries {
            do {
                let data = try Data(contentsOf: url)
                let raw = try JSONDecoder().decode(AudienceInteractiveJSON.self, from: data)
                let inter = try compile(raw, sourceURL: url)
                interactives.append(inter)
            } catch let err as AudienceInteractiveValidationError {
                issues.append("\(url.lastPathComponent): \(err.description)")
            } catch {
                issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return Result(interactives: interactives, issues: issues)
    }

    private static func compile(_ raw: AudienceInteractiveJSON, sourceURL: URL) throws -> AudienceInteractive {
        guard !raw.name.isEmpty else {
            throw AudienceInteractiveValidationError("name cannot be empty")
        }
        // Driven off AudienceInteractiveKind(rawValue:) so a new case
        // is automatically parseable. We pre-normalize hyphens and
        // spaces to underscores so the canonical snake_case rawValues
        // (e.g. "start_button") match user input written with any of
        // those separators. Anything that doesn't resolve to a known
        // case after normalization throws with the auto-built list.
        let normalized = raw.kind.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Backward-compat alias: "startbutton" (no separator) used to
        // be accepted alongside the canonical "start_button". Map it
        // through before the rawValue lookup to keep older files
        // loading without churn.
        let canonical: String
        switch normalized {
        case "startbutton": canonical = "start_button"
        default:            canonical = normalized
        }
        guard let kind = AudienceInteractiveKind(rawValue: canonical) else {
            let known = AudienceInteractiveKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw AudienceInteractiveValidationError(
                "kind '\(raw.kind)' — expected one of: \(known)"
            )
        }
        return AudienceInteractive(sourceURL: sourceURL, name: raw.name, kind: kind)
    }
}

struct AudienceInteractiveValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
