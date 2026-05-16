import Foundation

// An "audience interactive" is the fourth lineup-item kind alongside
// Song / Countdown / Interstitial. It's a screen the audience drives
// directly, using the red and green hardware buttons in front of them
// (keys "1" and "2"). The structure is generic — a kind discriminator
// in the JSON picks which behavior the screen has — so future
// audience-driven pieces (votes, branching paths, reactions, etc.) can
// land as new kinds without a new top-level lineup type each time.
//
// Stored under ~/BackTrack/AudienceInteractives/ as JSON. Referenced
// from setlists with kind "audience-interactive". Same hot-reload
// behavior as the other inventories.
//
// Currently shipping kinds:
//   start_button — a "PRESS 🟢 TO START THE SHOW" gate. Green advances
//                  the lineup to the next item; red plays a system
//                  error beep and shows "WRONG BUTTON" for ~1.5 s.
//                  Used immediately after the pre-show countdown.
struct AudienceInteractiveJSON: Codable {
    let name: String
    let kind: String       // "start_button" | "transmission"
    // Transmission-specific. Required when kind == "transmission",
    // ignored otherwise. Codable handles missing field as nil.
    let exchanges: [TransmissionExchangeJSON]?
}

struct TransmissionExchangeJSON: Codable {
    let id: String
    let header: String?
    let incoming: String?
    let green: TransmissionChoiceJSON?
    let red: TransmissionChoiceJSON?
    // Self-driving exchanges (OUTGOING messages, terminal beats)
    // declare an `autoAdvance` block. Mutually exclusive with
    // green/red — an exchange is either audience-driven or
    // timer-driven, never both.
    let autoAdvance: TransmissionAutoAdvanceJSON?
    // Optional sound to play when this exchange begins. Defaults
    // to "doot" (the SMS-style notification) for normal INCOMING
    // messages and "none" for everything else (OUTGOING, gates).
    // The "death" value plays the longer pac-man-style descending
    // arpeggio — meant for GAME OVER / closure beats.
    let arrivalSound: String?
}

struct TransmissionChoiceJSON: Codable {
    let label: String
    let next: String       // exchange id, or "abort"
}

struct TransmissionAutoAdvanceJSON: Codable {
    let holdSeconds: Double
    let next: String       // exchange id, or "abort"
}

// Compiled, validated audience interactive ready for the lineup.
struct AudienceInteractive {
    let sourceURL: URL
    let name: String
    let kind: AudienceInteractiveKind
    // Populated only when kind == .transmission.
    let transmission: TransmissionScript?
}

enum AudienceInteractiveKind: String, CaseIterable {
    // The audience presses green to advance the lineup. Pressing red
    // triggers a system error beep and a momentary "WRONG BUTTON"
    // overlay before reverting to the start prompt.
    case startButton = "start_button"
    // A multi-step text-message exchange between an unnamed sender
    // and the audience. Each exchange shows an INCOMING message and
    // (typically) two reply options on green/red; the audience picks,
    // the chosen reply briefly echoes as "YOU SENT: …", then the next
    // incoming arrives. The bit ends on a "terminal" exchange (one
    // with no reply options) that sits on screen until the operator
    // advances. The first scripted transmission is "The Breakup" —
    // the kind is reusable for future narrative pieces.
    case transmission
}

// MARK: - Transmission script types

// Compiled, validated transmission ready for runtime. Looked up by id.
struct TransmissionScript: Equatable {
    let exchanges: [TransmissionExchange]

    func exchange(id: String) -> TransmissionExchange? {
        exchanges.first { $0.id == id }
    }

    var firstExchangeId: String? {
        exchanges.first?.id
    }
}

struct TransmissionExchange: Equatable {
    let id: String
    let header: String        // default "INCOMING"
    let incoming: String      // default "" (used for the opening gate)
    let green: TransmissionChoice?
    let red: TransmissionChoice?
    // When set, this exchange has no audience interaction — it
    // displays for `holdSeconds` after typing finishes, then
    // auto-advances to the specified next. Used for OUTGOING
    // messages ("you" texted them, no reply expected) and for
    // terminal beats that should end the bit on their own clock.
    let autoAdvance: TransmissionAutoAdvance?
    // Sound played at the moment this exchange's typing begins.
    // Explicit when set; otherwise we infer from the header +
    // incoming (see `effectiveArrivalSound`).
    let arrivalSound: TransmissionArrivalSound?

    // An exchange with no choices and no autoAdvance terminates
    // the bit — the screen holds its `incoming` text until the
    // operator advances. That's how breakup's final beat works.
    // Adding autoAdvance changes a "would-be terminal" into a
    // self-ending one.
    var isTerminal: Bool {
        green == nil && red == nil && autoAdvance == nil
    }

    // Sound to play when the audience first sees this exchange.
    // Authors can override with the JSON `arrivalSound` field; the
    // default is "doot for a real incoming message, silence for
    // everything else." OUTGOING messages (where "you" are texting)
    // and gate-style exchanges (no body) skip by default — there's
    // nothing to *receive*, so no notification chirp.
    var effectiveArrivalSound: TransmissionArrivalSound {
        if let explicit = arrivalSound { return explicit }
        if incoming.isEmpty { return .none }
        if header.uppercased() == "INCOMING" { return .doot }
        return .none
    }
}

// Which SFX (if any) plays when a transmission exchange begins.
//   .doot — two-tone SMS-style "doot doot" (default for INCOMING
//           messages with a body)
//   .death — pac-man-style descending arpeggio (for GAME OVER /
//            closure beats)
//   .none — silence (default for OUTGOING, gates, custom headers)
enum TransmissionArrivalSound: String, Equatable, CaseIterable {
    case doot
    case death
    case none
}

struct TransmissionChoice: Equatable {
    let label: String
    let next: TransmissionNext

    // Choices wrapped in parens read as stage directions — "(say
    // nothing)", "(do nothing)", etc. — and shouldn't trigger the
    // "YOU SENT: <label>" reply echo (semantically, nothing was
    // sent). Detected automatically rather than via a schema flag
    // so authors can just write the parens and it does the right
    // thing.
    var isSilent: Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
    }
}

struct TransmissionAutoAdvance: Equatable {
    let holdSeconds: TimeInterval
    let next: TransmissionNext
}

enum TransmissionNext: Equatable {
    case exchange(id: String)
    case abort                // ends the bit, lineup advances
}

// Runtime phase for the active transmission. .idle when none is
// playing. Transitions are driven by KeyboardHandler timers — the
// view just renders whatever phase is current.
enum TransmissionPhase: Equatable {
    case idle
    // Showing an exchange's INCOMING + reply prompts. The audience
    // press transitions out of this phase. `startedAt` is the wall-
    // clock moment this phase began — the view uses it to drive a
    // character-by-character typing reveal of the incoming body, and
    // KeyboardHandler uses it to ignore audience presses that arrive
    // before the typing finishes (so the audience can't skip ahead
    // before they've seen the message).
    case incoming(exchangeId: String, startedAt: Date)
    // Briefly showing "YOU SENT: <reply>" before the next incoming.
    case replyEcho(text: String, nextExchangeId: String)
    // Brief blank between echo and next incoming — sells the
    // "they're typing on the other end" pause.
    case preIncomingBlank(nextExchangeId: String)
    // Showing "DELETED" briefly before the lineup auto-advances on
    // an "abort" path (e.g. DELETE on the opening gate).
    case deletedFlash
}

// Shared pacing constants for the transmission visualisation. View
// and KeyboardHandler both need the typing speed — the view to
// decide how many characters to render, the handler to decide
// whether a press should be honored or ignored. Keeping it in one
// place keeps them in sync.
enum TransmissionPacing {
    // Per-character reveal duration during the typing animation.
    // 40 ms ≈ 25 chars/sec — brisk text-message tempo, faster than
    // human typing but slow enough that the eye reads each char.
    static let charDuration: TimeInterval = 0.04
}
