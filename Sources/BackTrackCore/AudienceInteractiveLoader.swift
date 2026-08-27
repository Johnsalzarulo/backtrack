import Foundation

// Discovers and validates audience interactives under
// ~/BackTrack/AudienceInteractives/. Mirrors the shape of the other
// loaders so the Coordinator can drive every inventory through the
// same plumbing — directory scan, JSON decode, structural validate,
// emit issues for the HUD's issues block.
package enum AudienceInteractiveLoader {
    package struct Result {
        package let interactives: [AudienceInteractive]
        package let issues: [String]
    }

    package static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("AudienceInteractives")
    }

    package static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    package static func loadAll(from dir: URL) -> Result {
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

        // Per-kind compilation of the optional payload.
        var transmission: TransmissionScript? = nil
        var lottery: LotteryScript? = nil
        switch kind {
        case .startButton:
            break
        case .transmission:
            transmission = try compileTransmission(raw.exchanges)
        case .lottery:
            lottery = try compileLottery(raw.prizes)
        }

        return AudienceInteractive(
            sourceURL: sourceURL,
            name: raw.name,
            kind: kind,
            transmission: transmission,
            lottery: lottery
        )
    }

    // Validates the prizes array for a lottery audience-interactive.
    // Rules:
    //   - At least 2 prizes (a one-slice wheel isn't a wheel).
    //   - No empty/whitespace-only entries.
    //   - Trimmed to keep the display tight (leading/trailing whitespace
    //     on a slice label would just pad the centered text).
    // Duplicates are allowed — an author may want the same prize on
    // multiple slices to weight it heavier.
    private static func compileLottery(_ raw: [String]?) throws -> LotteryScript {
        guard let raw = raw, !raw.isEmpty else {
            throw AudienceInteractiveValidationError(
                "lottery must declare a 'prizes' array"
            )
        }
        guard raw.count >= 2 else {
            throw AudienceInteractiveValidationError(
                "lottery needs at least 2 prizes (got \(raw.count))"
            )
        }
        var prizes: [String] = []
        for (i, p) in raw.enumerated() {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AudienceInteractiveValidationError(
                    "lottery prize \(i + 1) is empty"
                )
            }
            prizes.append(trimmed)
        }
        return LotteryScript(prizes: prizes)
    }

    // Validates the exchanges array for a transmission audience-
    // interactive. Rules:
    //   - At least one exchange.
    //   - Unique ids.
    //   - Choices are both-or-neither (no half-terminal exchanges).
    //   - Every choice's `next` resolves to either "abort" or an
    //     existing exchange id.
    private static func compileTransmission(_ raw: [TransmissionExchangeJSON]?) throws -> TransmissionScript {
        guard let raw = raw, !raw.isEmpty else {
            throw AudienceInteractiveValidationError(
                "transmission must declare at least one item in 'exchanges'"
            )
        }
        // First pass: validate id uniqueness (also gives us the set of
        // valid id targets for the second pass).
        var seenIds: Set<String> = []
        for ex in raw {
            let trimmed = ex.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AudienceInteractiveValidationError(
                    "transmission exchange has empty 'id'"
                )
            }
            guard !seenIds.contains(trimmed) else {
                throw AudienceInteractiveValidationError(
                    "transmission has duplicate exchange id '\(trimmed)'"
                )
            }
            seenIds.insert(trimmed)
        }
        // Second pass: compile each exchange and resolve `next`.
        var exchanges: [TransmissionExchange] = []
        for ex in raw {
            let green = try compileTransmissionChoice(ex.green, exchangeId: ex.id, button: "green", validIds: seenIds)
            let red   = try compileTransmissionChoice(ex.red,   exchangeId: ex.id, button: "red",   validIds: seenIds)
            let auto  = try compileTransmissionAutoAdvance(ex.autoAdvance, exchangeId: ex.id, validIds: seenIds)
            let arrival = try compileTransmissionArrivalSound(ex.arrivalSound, exchangeId: ex.id)
            // Both-or-neither rule: a partial-choice exchange is
            // ambiguous — would the missing button be a no-op or
            // abort? Force the author to be explicit.
            if (green == nil) != (red == nil) {
                throw AudienceInteractiveValidationError(
                    "transmission exchange '\(ex.id)' must have BOTH 'green' and 'red' choices, or NEITHER (terminal exchange)"
                )
            }
            // Mutual exclusivity: choices and autoAdvance can't both
            // run an exchange. Either the audience advances it
            // (green/red) or the timer does (autoAdvance). Allowing
            // both would create ambiguous timing semantics.
            if auto != nil && (green != nil || red != nil) {
                throw AudienceInteractiveValidationError(
                    "transmission exchange '\(ex.id)' has both autoAdvance and reply choices — pick one"
                )
            }
            exchanges.append(TransmissionExchange(
                id: ex.id,
                header: ex.header ?? "INCOMING",
                incoming: ex.incoming ?? "",
                green: green,
                red: red,
                autoAdvance: auto,
                arrivalSound: arrival,
                bottomPrompt: ex.bottomPrompt?.isEmpty == true ? nil : ex.bottomPrompt
            ))
        }
        return TransmissionScript(exchanges: exchanges)
    }

    // Optional `arrivalSound` parser. Drives off the enum's
    // rawValue so adding a new SFX case to TransmissionArrivalSound
    // auto-picks it up — no parallel switch to drift.
    private static func compileTransmissionArrivalSound(
        _ raw: String?,
        exchangeId: String
    ) throws -> TransmissionArrivalSound? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = TransmissionArrivalSound(rawValue: normalized) {
            return value
        }
        let known = TransmissionArrivalSound.allCases.map(\.rawValue).joined(separator: ", ")
        throw AudienceInteractiveValidationError(
            "transmission exchange '\(exchangeId)' arrivalSound '\(raw)' — expected one of: \(known)"
        )
    }

    private static func compileTransmissionAutoAdvance(
        _ raw: TransmissionAutoAdvanceJSON?,
        exchangeId: String,
        validIds: Set<String>
    ) throws -> TransmissionAutoAdvance? {
        guard let raw = raw else { return nil }
        guard raw.holdSeconds > 0 else {
            throw AudienceInteractiveValidationError(
                "transmission exchange '\(exchangeId)' autoAdvance.holdSeconds must be > 0 (got \(raw.holdSeconds))"
            )
        }
        let normalized = raw.next.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AudienceInteractiveValidationError(
                "transmission exchange '\(exchangeId)' autoAdvance.next is empty"
            )
        }
        let next: TransmissionNext
        if normalized == "abort" {
            next = .abort
        } else if validIds.contains(normalized) {
            next = .exchange(id: normalized)
        } else {
            throw AudienceInteractiveValidationError(
                "transmission exchange '\(exchangeId)' autoAdvance.next '\(raw.next)' doesn't reference any exchange id (or 'abort')"
            )
        }
        return TransmissionAutoAdvance(holdSeconds: raw.holdSeconds, next: next)
    }

    private static func compileTransmissionChoice(
        _ raw: TransmissionChoiceJSON?,
        exchangeId: String,
        button: String,
        validIds: Set<String>
    ) throws -> TransmissionChoice? {
        guard let raw = raw else { return nil }
        guard !raw.label.isEmpty else {
            throw AudienceInteractiveValidationError(
                "transmission exchange '\(exchangeId)' \(button) choice has empty 'label'"
            )
        }
        let normalized = raw.next
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AudienceInteractiveValidationError(
                "transmission exchange '\(exchangeId)' \(button) choice has empty 'next'"
            )
        }
        let next: TransmissionNext
        if normalized == "abort" {
            next = .abort
        } else if validIds.contains(normalized) {
            next = .exchange(id: normalized)
        } else {
            throw AudienceInteractiveValidationError(
                "transmission exchange '\(exchangeId)' \(button) choice 'next: \(raw.next)' doesn't reference any exchange id (or the literal 'abort')"
            )
        }
        return TransmissionChoice(label: raw.label, next: next)
    }
}

package struct AudienceInteractiveValidationError: Error, CustomStringConvertible {
    package let description: String
    package init(_ description: String) { self.description = description }
}
