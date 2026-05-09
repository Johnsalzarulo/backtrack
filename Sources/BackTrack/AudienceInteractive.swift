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
    let kind: String       // "start_button" (more to come)
}

// Compiled, validated audience interactive ready for the lineup.
struct AudienceInteractive {
    let sourceURL: URL
    let name: String
    let kind: AudienceInteractiveKind
}

enum AudienceInteractiveKind: String, CaseIterable {
    // The audience presses green to advance the lineup. Pressing red
    // triggers a system error beep and a momentary "WRONG BUTTON"
    // overlay before reverting to the start prompt.
    case startButton = "start_button"
}
