import Foundation

// An "interstitial" is the third lineup-item kind alongside Song and
// Countdown. Where a Song plays a backing track and a Countdown runs a
// timer, an Interstitial just shows a static thing on screen — a text
// card, a still image, or a video clip with audio. Useful between
// songs while the performer is tuning, taking a beat, or introducing
// what's next.
//
// Stored as JSON files under ~/BackTrack/Interstitials/, referenced
// from setlists by name with `kind: "interstitial"`. Three flavors,
// distinguished by the `kind` field; one of `text` / `image` / `video`
// is required depending on kind.
//
// Optional shared fields:
//   - notes:   talking points shown in the HUD's right column where
//              song lyrics normally appear
//   - duration: auto-advance to the next lineup item after N seconds
//              (text + image only — for video, the clip's actual
//              length determines auto-advance, regardless of duration)
//   - theme:   "dark" / "light" — affects text color on text kind
//
// Video-specific fields:
//   - volume: 0–100, default 100
//   - loop:   default false. When true, video keeps replaying until
//             the performer navigates away. When false, video plays
//             once then auto-advances to the next lineup item.
package struct InterstitialJSON: Codable {
    package let name: String
    package let kind: String           // "text" | "image" | "video"
    package let text: String?          // required for kind == "text"
    package let image: String?         // filename in ~/BackTrack/Visuals/ — required for kind == "image"
    package let video: String?         // filename in ~/BackTrack/VideoClips/ — required for kind == "video"
    package let volume: Int?           // 0–100, default 100. Video only.
    package let loop: Bool?            // Video only. Default false.
    package let duration: Int?         // seconds, optional auto-advance. Text/image only.
    package let notes: String?
    package let theme: String?         // "dark" | "light", default "dark"
}

// Compiled, validated interstitial ready for the lineup.
package struct Interstitial {
    package let sourceURL: URL
    package let name: String
    package let kind: InterstitialKind
    package let text: String?          // populated when kind == .text
    package let image: String?         // populated when kind == .image
    package let video: String?         // populated when kind == .video
    package let volume: Int            // 0–100; meaningful only when kind == .video
    package let loop: Bool             // meaningful only when kind == .video
    package let duration: TimeInterval?// auto-advance for text/image; ignored for video
    package let notes: String          // empty string if not provided
    package let theme: VisualTheme
}

package enum InterstitialKind: String, CaseIterable {
    case text
    case image
    case video
}
