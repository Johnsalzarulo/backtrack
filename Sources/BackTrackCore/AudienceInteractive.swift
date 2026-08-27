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
package struct AudienceInteractiveJSON: Codable {
    package let name: String
    package let kind: String       // "start_button" | "transmission" | "lottery"
    // Transmission-specific. Required when kind == "transmission",
    // ignored otherwise. Codable handles missing field as nil.
    package let exchanges: [TransmissionExchangeJSON]?
    // Lottery-specific. Required when kind == "lottery": the wheel's
    // slice labels (the prizes the audience can "win"). Ignored for
    // other kinds.
    package let prizes: [String]?
}

package struct TransmissionExchangeJSON: Codable {
    package let id: String
    package let header: String?
    package let incoming: String?
    package let green: TransmissionChoiceJSON?
    package let red: TransmissionChoiceJSON?
    // Self-driving exchanges (OUTGOING messages, terminal beats)
    // declare an `autoAdvance` block. Mutually exclusive with
    // green/red — an exchange is either audience-driven or
    // timer-driven, never both.
    package let autoAdvance: TransmissionAutoAdvanceJSON?
    // Optional sound to play when this exchange begins. Defaults
    // to "doot" (the SMS-style notification) for normal INCOMING
    // messages and "none" for everything else (OUTGOING, gates).
    // The "death" value plays the longer pac-man-style descending
    // arpeggio — meant for GAME OVER / closure beats.
    package let arrivalSound: String?
    // Optional small text at the bottom of the exchange, where
    // reply prompts normally render. Used for non-interactive
    // exchanges (autoAdvance + no choices) to display things like
    // "Mash 🔴 and 🟢 to beg" while the audience can't actually
    // do anything to escape. Presses on such an exchange fire the
    // doot for feedback but don't advance.
    //
    // 🔴 / 🟢 in the string render as colored ⬤ dots (matching
    // the rest of the transmission UI).
    package let bottomPrompt: String?
}

package struct TransmissionChoiceJSON: Codable {
    package let label: String
    package let next: String       // exchange id, or "abort"
}

package struct TransmissionAutoAdvanceJSON: Codable {
    package let holdSeconds: Double
    package let next: String       // exchange id, or "abort"
}

// Compiled, validated audience interactive ready for the lineup.
package struct AudienceInteractive {
    package let sourceURL: URL
    package let name: String
    package let kind: AudienceInteractiveKind
    // Populated only when kind == .transmission.
    package let transmission: TransmissionScript?
    // Populated only when kind == .lottery.
    package let lottery: LotteryScript?
}

package enum AudienceInteractiveKind: String, CaseIterable {
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
    // An 8-bit prize-wheel game. Audience presses green to spin a
    // wheel of N slices; the wheel ramps up, sustains a blur, then
    // decelerates with ratcheting ticks and lands on a random slice;
    // a triumphant fanfare plays and the "won" prize fills the
    // screen for a beat before the bit fades out and the lineup
    // advances. The comedy is the form/content collision —
    // celebratory game-show language wrapping a piece of modern
    // psychological baggage.
    case lottery
}

// MARK: - Transmission script types

// Compiled, validated transmission ready for runtime. Looked up by id.
package struct TransmissionScript: Equatable {
    package let exchanges: [TransmissionExchange]

    package func exchange(id: String) -> TransmissionExchange? {
        exchanges.first { $0.id == id }
    }

    package var firstExchangeId: String? {
        exchanges.first?.id
    }
}

package struct TransmissionExchange: Equatable {
    package let id: String
    package let header: String        // default "INCOMING"
    package let incoming: String      // default "" (used for the opening gate)
    package let green: TransmissionChoice?
    package let red: TransmissionChoice?
    // When set, this exchange has no audience interaction — it
    // displays for `holdSeconds` after typing finishes, then
    // auto-advances to the specified next. Used for OUTGOING
    // messages ("you" texted them, no reply expected) and for
    // terminal beats that should end the bit on their own clock.
    package let autoAdvance: TransmissionAutoAdvance?
    // Sound played at the moment this exchange's typing begins.
    // Explicit when set; otherwise we infer from the header +
    // incoming (see `effectiveArrivalSound`).
    package let arrivalSound: TransmissionArrivalSound?
    // Optional bottom-of-screen prompt for non-interactive
    // exchanges. Renders where reply choices would go. 🔴 / 🟢
    // emoji in the string substitute to colored ⬤ dots at render
    // time. When set, audience button presses on this exchange
    // produce the doot (interaction feedback) but don't advance
    // — perfect for "press to no avail" beats like "Mash 🔴 and
    // 🟢 to beg" during a doomed message hold.
    package let bottomPrompt: String?

    // An exchange with no choices and no autoAdvance terminates
    // the bit — the screen holds its `incoming` text until the
    // operator advances. That's how breakup's final beat works.
    // Adding autoAdvance changes a "would-be terminal" into a
    // self-ending one.
    package var isTerminal: Bool {
        green == nil && red == nil && autoAdvance == nil
    }

    // Sound to play when the audience first sees this exchange.
    // Authors can override with the JSON `arrivalSound` field;
    // otherwise:
    //
    //   - Gate (empty body) → doot. The gate has no body and no TTS,
    //     so the chirp IS the arrival signal — without it the
    //     opening screen lands silently.
    //   - Anything with a non-empty body → none. The TTS reading the
    //     body is the audio signal; an additional doot would step on
    //     the first few words.
    //
    // The press-time doot fires on every audience press during a
    // transmission (handled separately in KeyboardHandler) — that's
    // the "interaction acknowledgment" sound, distinct from this
    // arrival sound.
    package var effectiveArrivalSound: TransmissionArrivalSound {
        if let explicit = arrivalSound { return explicit }
        if incoming.isEmpty { return .doot }
        return .none
    }
}

// Which SFX (if any) plays when a transmission exchange begins.
//   .doot — two-tone SMS-style "doot doot" (default for INCOMING
//           messages with a body)
//   .death — pac-man-style descending arpeggio (for GAME OVER /
//            closure beats)
//   .none — silence (default for OUTGOING, gates, custom headers)
package enum TransmissionArrivalSound: String, Equatable, CaseIterable {
    case doot
    case death
    case none
}

package struct TransmissionChoice: Equatable {
    package let label: String
    package let next: TransmissionNext

    // Choices wrapped in parens read as stage directions — "(say
    // nothing)", "(do nothing)", etc. — and shouldn't trigger the
    // "YOU SENT: <label>" reply echo (semantically, nothing was
    // sent). Detected automatically rather than via a schema flag
    // so authors can just write the parens and it does the right
    // thing.
    package var isSilent: Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
    }
}

package struct TransmissionAutoAdvance: Equatable {
    package let holdSeconds: TimeInterval
    package let next: TransmissionNext
}

package enum TransmissionNext: Equatable {
    case exchange(id: String)
    case abort                // ends the bit, lineup advances
}

// Runtime phase for the active transmission. .idle when none is
// playing. Transitions are driven by KeyboardHandler timers — the
// view just renders whatever phase is current.
package enum TransmissionPhase: Equatable {
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
package enum TransmissionPacing {
    // Per-character reveal duration during the typing animation.
    // 40 ms ≈ 25 chars/sec — brisk text-message tempo, faster than
    // human typing but slow enough that the eye reads each char.
    package static let charDuration: TimeInterval = 0.04
}

// MARK: - Lottery script types

// Compiled, validated lottery ready for runtime. The prizes array is
// the wheel — each entry one slice, equal weight at the RNG. Slice
// count is captured at load time so the view, the spin-angle math, and
// the random selection all agree on the same count.
package struct LotteryScript: Equatable {
    package let prizes: [String]

    package var sliceCount: Int { prizes.count }
}

// Runtime phase for the active lottery. .idle when none is playing.
// Transitions are driven by KeyboardHandler timers (auto-advances) and
// audience green presses (manual advances on `.setup` and `.wheel`).
// All non-idle phases carry the wall-clock moment the phase began —
// the view reads it to drive animation (spin angle, fade opacity,
// pulse on the landed slice) and the handler reads it for ignore-
// early-presses logic.
package enum LotteryPhase: Equatable {
    case idle
    // Triumphant "CONGRATULATIONS! YOU HAVE A CHANCE TO SPIN THE
    // WHEEL" setup screen. Auto-advances to .wheel after
    // setupHoldSeconds, or earlier on a green press.
    case setup(startedAt: Date)
    // Wheel rendered static with "PRESS TO SPIN" prompt. Stays here
    // until the audience presses green.
    case wheel(startedAt: Date)
    // Wheel animating to its landing slice. No interruption.
    // `landing` is the slice index chosen at spin start; the view
    // computes the current rotation from (now - startedAt) using a
    // 1s accel / 2s sustain / 4s decel profile that ends exactly at
    // landing.
    case spinning(landing: Int, startedAt: Date)
    // Wheel at rest on the landed slice, slice pulsing/highlighted.
    // Brief beat before the text screens take over.
    case resultPending(landing: Int, startedAt: Date)
    // Text-only "CONGRATULATIONS! / YOU HAVE WON..." with no prize
    // yet visible. Builds tension on the diagnostic before it drops.
    case revealIntro(prize: String, startedAt: Date)
    // The prize fills the screen. Held for prizeDisplaySeconds —
    // long enough for the audience to read it, recognize it, sit
    // with it. Do not rush this phase.
    case prizeDisplay(prize: String, startedAt: Date)
    // Fade-to-black over the prize before the lineup advances. The
    // view reads `startedAt` to drive a 0→1 black-overlay opacity.
    case fading(prize: String, startedAt: Date)
}

// Shared pacing constants for the lottery. View and KeyboardHandler
// both reference these so phase transitions in code and animation
// timing in the view stay in agreement.
package enum LotteryPacing {
    // Phase durations.
    package static let setupHoldSeconds: TimeInterval = 5
    package static let resultPendingSeconds: TimeInterval = 0.5
    package static let revealIntroSeconds: TimeInterval = 1.5
    package static let prizeDisplaySeconds: TimeInterval = 6.0
    package static let fadingSeconds: TimeInterval = 1.5

    // Spin animation profile: accel-sustain-decel piecewise so the
    // wheel matches the spec's "starts slow, blurs out for ~2s, then
    // decelerates with audible slowing ticks" shape rather than a
    // single ease curve.
    package static let spinAccelDuration: TimeInterval = 1.0
    package static let spinSustainDuration: TimeInterval = 2.0
    package static let spinDecelDuration: TimeInterval = 4.0
    // Full revolutions the wheel makes before landing on the chosen
    // slice. Combined with the durations above, sets peak angular
    // velocity (and therefore peak tick rate at full blur).
    package static let spinFullRotations: Int = 6

    package static var spinDuration: TimeInterval {
        spinAccelDuration + spinSustainDuration + spinDecelDuration
    }

    // Rotation angle (radians, clockwise from rest) at `elapsed`
    // seconds into a spin that lands on `landing` out of `slices`.
    // Used by the view to draw the wheel and by the handler to
    // pre-schedule tick SFX at each slice-boundary crossing.
    //
    // Profile:
    //   accel  : ω(t) = ωmax · t / Ta             (linear ramp-up)
    //   sustain: ω(t) = ωmax                      (full-speed blur)
    //   decel  : ω(t) = ωmax · (1 - (t-Td0)/Td)²  (quadratic falloff)
    //
    // ωmax is solved so the integrated θ over [0, spinDuration]
    // equals exactly `spinFullRotations × 2π + landing × 2π/slices`,
    // i.e. the wheel comes to rest with the chosen slice centered
    // under the top indicator.
    package static func spinAngle(elapsed: TimeInterval, landing: Int, slices: Int) -> Double {
        let landingFraction = Double(landing) / Double(slices)
        let thetaFinal = (Double(spinFullRotations) + landingFraction) * 2 * .pi
        // Integrated angle factor over the full spin: Ta/2 + Ts + Td/3
        // (accel contributes 0.5·ωmax·Ta = ωmax·Ta/2 worth of rotation;
        // sustain contributes ωmax·Ts; decel's ∫(1-x)² over [0,1] = 1/3,
        // scaled by Td gives ωmax·Td/3).
        let factor = spinAccelDuration / 2.0 + spinSustainDuration + spinDecelDuration / 3.0
        let omegaMax = thetaFinal / factor
        let t = max(0, min(spinDuration, elapsed))
        if t <= spinAccelDuration {
            return omegaMax * t * t / (2 * spinAccelDuration)
        }
        let afterAccel = omegaMax * spinAccelDuration / 2.0
        if t <= spinAccelDuration + spinSustainDuration {
            return afterAccel + omegaMax * (t - spinAccelDuration)
        }
        let afterSustain = afterAccel + omegaMax * spinSustainDuration
        let dt = t - spinAccelDuration - spinSustainDuration
        // ∫₀^dt ωmax · (1 - s/Td)² ds = ωmax·Td/3 · [1 - (1 - dt/Td)³]
        let u = dt / spinDecelDuration
        return afterSustain + omegaMax * spinDecelDuration / 3.0 * (1.0 - pow(1.0 - u, 3))
    }
}
