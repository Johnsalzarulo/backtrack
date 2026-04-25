import Foundation

// Discovers and validates countdowns under ~/BackTrack/Countdowns/.
// Mirrors SongLoader's shape so the Coordinator can drive both with
// the same plumbing — file watcher, issues list, etc.
enum CountdownLoader {
    struct Result {
        let countdowns: [Countdown]
        let issues: [String]
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Countdowns")
    }

    static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    static func loadAll(from dir: URL) -> Result {
        var countdowns: [Countdown] = []
        var issues: [String] = []

        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            // Folder doesn't exist yet; not an error, just no countdowns.
            return Result(countdowns: [], issues: [])
        }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "json" }
             .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            issues.append("failed to read Countdowns directory: \(error.localizedDescription)")
            return Result(countdowns: [], issues: issues)
        }

        for url in entries {
            do {
                let data = try Data(contentsOf: url)
                let raw = try JSONDecoder().decode(CountdownJSON.self, from: data)
                let countdown = try compile(raw, sourceURL: url)
                countdowns.append(countdown)
            } catch let error as CountdownValidationError {
                issues.append("\(url.lastPathComponent): \(error.description)")
            } catch {
                issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return Result(countdowns: countdowns, issues: issues)
    }

    private static func compile(_ raw: CountdownJSON, sourceURL: URL) throws -> Countdown {
        guard raw.duration > 0 else {
            throw CountdownValidationError("duration must be > 0 (got \(raw.duration))")
        }
        let interval = raw.messageInterval ?? Countdown.defaultMessageInterval
        guard interval > 0 else {
            throw CountdownValidationError("messageInterval must be > 0 (got \(interval))")
        }

        let style: CountdownStyle
        switch raw.style?.lowercased() {
        case nil, "", "digital":
            style = .digital
        case "pie":
            style = .pie
        case "hourglass":
            style = .hourglass
        case let other?:
            throw CountdownValidationError(
                "style '\(other)' — expected one of: digital, pie, hourglass"
            )
        }

        return Countdown(
            sourceURL: sourceURL,
            name: raw.name,
            duration: raw.duration,
            label: raw.label ?? Countdown.defaultLabel,
            messageInterval: interval,
            messages: raw.messages ?? [],
            style: style
        )
    }
}

struct CountdownValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
