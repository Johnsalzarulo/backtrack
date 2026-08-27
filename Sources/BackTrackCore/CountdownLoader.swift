import Foundation

// Discovers and validates countdowns under ~/BackTrack/Countdowns/.
// Mirrors SongLoader's shape so the Coordinator can drive both with
// the same plumbing — file watcher, issues list, etc.
package enum CountdownLoader {
    package struct Result {
        package let countdowns: [Countdown]
        package let issues: [String]
    }

    package static func defaultDirectory() -> URL {
        MacContentStore().rootURL.appendingPathComponent("Countdowns")
    }

    package static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    package static func loadAll(from dir: URL) -> Result {
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
    // unless the file declares `chords`, `pattern`, or `sections`.
    // Validation mirrors SongLoader: unknown pattern / unparseable chord
    // / out-of-range level / bad repeats / pad-or-bass-level-without-a-
    // sound-name all raise a CountdownValidationError that surfaces in
    // the HUD's issues block.
    private static func compileMotif(_ raw: CountdownJSON) throws -> CountdownMotif? {
        let patternName = raw.pattern?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPattern = !(patternName?.isEmpty ?? true)
        let hasChords = !(raw.chords?.isEmpty ?? true)
        let hasSections = !(raw.sections?.isEmpty ?? true)
        guard hasPattern || hasChords || hasSections else { return nil }

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

        // Motif-level chords + levels act as defaults the sections
        // inherit. Levels default to 1 (a gentle ambient drone /
        // whole-note root) when a sound is named but no level is given —
        // "name the instrument, hear the instrument." An explicit level
        // (here or per-section) wins.
        let motifChords = try parseChords(raw.chords, context: "motif")
        let defaultPadLevel = raw.padLevel ?? (raw.pad?.isEmpty == false ? 1 : 0)
        let defaultBassLevel = raw.bassLevel ?? (raw.bass?.isEmpty == false ? 1 : 0)

        let sections = try compileSections(
            raw,
            motifChords: motifChords,
            defaultPadLevel: defaultPadLevel,
            defaultBassLevel: defaultBassLevel
        )

        let usesPad = sections.contains { $0.padLevel > 0 }
        let usesBass = sections.contains { $0.bassLevel > 0 }
        if usesPad && (raw.pad?.isEmpty ?? true) {
            throw CountdownValidationError("motif uses pad (padLevel > 0) but has no \"pad\" sound name")
        }
        if usesBass && (raw.bass?.isEmpty ?? true) {
            throw CountdownValidationError("motif uses bass (bassLevel > 0) but has no \"bass\" sound name")
        }

        let bpm = raw.bpm ?? Countdown.defaultMotifBPM
        guard bpm > 0 else {
            throw CountdownValidationError("motif bpm must be > 0 (got \(bpm))")
        }

        return CountdownMotif(
            bpm: bpm,
            kit: hasPattern ? raw.kit : nil,
            pattern: hasPattern ? patternName : nil,
            padSound: usesPad ? raw.pad : nil,
            bassSound: usesBass ? raw.bass : nil,
            sections: sections
        )
    }

    // Builds the ordered section list. With an explicit `sections`
    // array, each section inherits the motif-level chords/levels for
    // anything it doesn't override. Without one, the motif-level chords
    // form a single implicit section (the flat form). A drums-only
    // motif (no chords anywhere) yields no sections.
    private static func compileSections(
        _ raw: CountdownJSON,
        motifChords: [Chord],
        defaultPadLevel: Int,
        defaultBassLevel: Int
    ) throws -> [CountdownSection] {
        guard let rawSections = raw.sections, !rawSections.isEmpty else {
            guard !motifChords.isEmpty else { return [] }
            try validateLevels(pad: defaultPadLevel, bass: defaultBassLevel, context: "motif")
            return [CountdownSection(
                chords: motifChords,
                padLevel: defaultPadLevel,
                bassLevel: defaultBassLevel,
                repeats: 1
            )]
        }

        var sections: [CountdownSection] = []
        for (i, sec) in rawSections.enumerated() {
            let label = "section \(i + 1)"
            let chords: [Chord]
            if let symbols = sec.chords, !symbols.isEmpty {
                chords = try parseChords(symbols, context: label)
            } else {
                chords = motifChords
            }
            let padLevel = sec.padLevel ?? defaultPadLevel
            let bassLevel = sec.bassLevel ?? defaultBassLevel
            try validateLevels(pad: padLevel, bass: bassLevel, context: label)
            let repeats = sec.repeats ?? 1
            guard repeats >= 1 else {
                throw CountdownValidationError("\(label) repeats must be >= 1 (got \(repeats))")
            }
            if (padLevel > 0 || bassLevel > 0) && chords.isEmpty {
                throw CountdownValidationError("\(label) uses pad/bass but has no \"chords\"")
            }
            sections.append(CountdownSection(
                chords: chords,
                padLevel: padLevel,
                bassLevel: bassLevel,
                repeats: repeats
            ))
        }
        return sections
    }

    private static func parseChords(_ symbols: [String]?, context: String) throws -> [Chord] {
        var chords: [Chord] = []
        for symbol in symbols ?? [] {
            do {
                chords.append(try ChordParser.parse(symbol))
            } catch let err as ChordParseError {
                throw CountdownValidationError("\(context) chord '\(symbol)' — \(err.description)")
            }
        }
        return chords
    }

    private static func validateLevels(pad: Int, bass: Int, context: String) throws {
        guard (0...3).contains(pad) else {
            throw CountdownValidationError("\(context) padLevel \(pad) out of range (0-3)")
        }
        guard (0...3).contains(bass) else {
            throw CountdownValidationError("\(context) bassLevel \(bass) out of range (0-3)")
        }
    }
}

package struct CountdownValidationError: Error, CustomStringConvertible {
    package let description: String
    package init(_ description: String) { self.description = description }
}
