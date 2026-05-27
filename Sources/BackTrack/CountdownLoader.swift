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

        // CountdownStyle(rawValue:) drives parsing — a new case in the
        // enum is automatically parseable, no parallel switch to drift.
        let style: CountdownStyle
        if let rawStyle = raw.style?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           !rawStyle.isEmpty {
            guard let parsed = CountdownStyle(rawValue: rawStyle) else {
                let known = CountdownStyle.allCases.map(\.rawValue).joined(separator: ", ")
                throw CountdownValidationError(
                    "style '\(raw.style ?? "")' — expected one of: \(known)"
                )
            }
            style = parsed
        } else {
            style = .digital
        }

        let visualEffect: PostEffect
        do {
            visualEffect = try PostEffectParser.parse(raw.visualEffect, context: "countdown") ?? .none
        } catch let err as PostEffectParseError {
            throw CountdownValidationError(err.description)
        }

        let motif = try compileMotif(raw)

        return Countdown(
            sourceURL: sourceURL,
            name: raw.name,
            duration: raw.duration,
            label: raw.label ?? Countdown.defaultLabel,
            messageInterval: interval,
            messages: raw.messages ?? [],
            style: style,
            visualEffect: visualEffect,
            motif: motif
        )
    }

    // Compiles the optional looping motif. Returns nil (silent timer)
    // unless the file declares `chords` or `pattern`. Validation mirrors
    // SongLoader: unknown pattern / unparseable chord / out-of-range
    // level / pad-or-bass-level-without-a-sound-name all raise a
    // CountdownValidationError that surfaces in the HUD's issues block.
    private static func compileMotif(_ raw: CountdownJSON) throws -> CountdownMotif? {
        let patternName = raw.pattern?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPattern = !(patternName?.isEmpty ?? true)
        let hasChords = !(raw.chords?.isEmpty ?? true)
        guard hasPattern || hasChords else { return nil }

        if hasPattern, let name = patternName,
           !Generators.allPatternNames().contains(name) {
            throw CountdownValidationError(
                "motif references pattern '\(name)' which isn't defined in patterns.json"
            )
        }
        // Drums need a kit. Mirror SongJSON, where `kit` is mandatory
        // whenever the pattern produces hits.
        if hasPattern, (raw.kit?.isEmpty ?? true) {
            throw CountdownValidationError("motif has a pattern but no \"kit\" sound name")
        }

        var chords: [Chord] = []
        for symbol in raw.chords ?? [] {
            do {
                chords.append(try ChordParser.parse(symbol))
            } catch let err as ChordParseError {
                throw CountdownValidationError("motif chord '\(symbol)' — \(err.description)")
            }
        }

        // Levels default to 1 (a gentle ambient drone / whole-note root)
        // when a sound is named but the level is left off — "name the
        // instrument, hear the instrument." An explicit level wins.
        let padLevel = raw.padLevel ?? (raw.pad?.isEmpty == false ? 1 : 0)
        let bassLevel = raw.bassLevel ?? (raw.bass?.isEmpty == false ? 1 : 0)
        guard (0...3).contains(padLevel) else {
            throw CountdownValidationError("motif padLevel \(padLevel) out of range (0-3)")
        }
        guard (0...3).contains(bassLevel) else {
            throw CountdownValidationError("motif bassLevel \(bassLevel) out of range (0-3)")
        }
        if padLevel > 0 && (raw.pad?.isEmpty ?? true) {
            throw CountdownValidationError("motif uses pad (padLevel > 0) but has no \"pad\" sound name")
        }
        if bassLevel > 0 && (raw.bass?.isEmpty ?? true) {
            throw CountdownValidationError("motif uses bass (bassLevel > 0) but has no \"bass\" sound name")
        }
        // Pad/bass voices need chords to know what to play.
        if (padLevel > 0 || bassLevel > 0) && chords.isEmpty {
            throw CountdownValidationError("motif uses pad/bass but has no \"chords\" progression")
        }

        let bpm = raw.bpm ?? Countdown.defaultMotifBPM
        guard bpm > 0 else {
            throw CountdownValidationError("motif bpm must be > 0 (got \(bpm))")
        }

        return CountdownMotif(
            bpm: bpm,
            kit: hasPattern ? raw.kit : nil,
            pattern: hasPattern ? patternName : nil,
            chords: chords,
            padSound: padLevel > 0 ? raw.pad : nil,
            padLevel: padLevel,
            bassSound: bassLevel > 0 ? raw.bass : nil,
            bassLevel: bassLevel
        )
    }
}

struct CountdownValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
