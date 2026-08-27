import Foundation
import SwiftUI

// Observable source of truth for everything the HUD and visuals window
// need to display: transport (is-playing, current bar/beat), lineup +
// part navigation, and activity timestamps that drive the reactive
// visuals.
//
// Lifecycle: one instance per app session, created by Coordinator at
// launch and shared as an @EnvironmentObject with ContentView (HUD)
// and VisualsView (secondary window / preview).
//
// Concurrency: every mutation happens on the main queue. Clock drives
// the ticking fields (currentBar, currentBeat, trigger timestamps);
// KeyboardHandler drives transport; AudioEngineController stamps the
// trigger timestamps right after scheduling playback so the visuals
// fire in sync with the audio. Audio callbacks that need to write here
// dispatch back to main first.
//
// Lineup model (post-setlist refactor): the `lineup` array is the
// single ordered list of items the performer navigates through with
// ←/→. It's derived: when a setlist is active, lineup = that setlist's
// resolved items; when no setlist is active, lineup = all songs
// followed by all countdowns. The legacy `currentSong` /
// `currentCountdown` accessors stay as computed properties keyed off
// the current lineup item, so most existing call sites keep working.
package final class AppState: ObservableObject {
    package init() {}
    // MARK: - Transport

    @Published package var isPlaying: Bool = false
    @Published package var currentBeat: Int = 0

    // Wall-clock timestamp of the last quarter-note tick. Stamped by
    // Clock when currentBeat advances (and by the count-in path).
    // Visual effects read this to drive beat-synced animation.
    @Published package var lastBeatTime: Date = .distantPast

    // Count-in state. While the Clock is firing pre-roll clicks,
    // `countInBeat` is the 1-based beat number within the count-in
    // (1...countInTotal) and `countInTotal` is the total beats
    // (countIn × 4). Both reset to 0/nil once the song proper begins
    // or playback stops.
    @Published package var countInBeat: Int? = nil
    @Published package var countInTotal: Int = 0

    // MARK: - Inventories (loaded from disk; rarely changes)

    @Published package var songs: [Song] = []
    @Published package var countdowns: [Countdown] = []
    @Published package var interstitials: [Interstitial] = []
    @Published package var audienceInteractives: [AudienceInteractive] = []
    @Published package var setlists: [Setlist] = []

    @Published package var songIssues: [String] = []
    @Published package var countdownIssues: [String] = []
    @Published package var interstitialIssues: [String] = []
    @Published package var audienceInteractiveIssues: [String] = []
    @Published package var setlistIssues: [String] = []

    // MARK: - Lineup (the navigable arrangement)

    // The ordered list arrows + Space act on. Built by `rebuildLineup`
    // from the active setlist, or by concatenating songs + countdowns
    // when no setlist is active.
    @Published package var lineup: [LineupItem] = []
    @Published package var currentLineupIndex: Int = 0

    // Index of the active setlist within `setlists`. Cycled via the D
    // key. Only meaningful when !setlists.isEmpty — otherwise lineup
    // falls back to the "all songs + all countdowns" combined view.
    @Published package var currentSetlistIndex: Int = 0

    package var currentLineupItem: LineupItem? {
        guard lineup.indices.contains(currentLineupIndex) else { return nil }
        return lineup[currentLineupIndex]
    }

    package var currentSetlist: Setlist? {
        guard setlists.indices.contains(currentSetlistIndex) else { return nil }
        return setlists[currentSetlistIndex]
    }

    // Legacy accessors — derived from the lineup item so existing call
    // sites (Clock, ContentView, VisualsView) keep working without
    // having to switch on LineupItem at every use. Mutually exclusive:
    // exactly one is non-nil at a time when the lineup isn't empty.
    package var currentSong: Song? {
        if case .song(let s) = currentLineupItem { return s }
        return nil
    }

    package var currentCountdown: Countdown? {
        if case .countdown(let c) = currentLineupItem { return c }
        return nil
    }

    package var currentInterstitial: Interstitial? {
        if case .interstitial(let i) = currentLineupItem { return i }
        return nil
    }

    package var currentAudienceInteractive: AudienceInteractive? {
        if case .audienceInteractive(let a) = currentLineupItem { return a }
        return nil
    }

    // MARK: - Countdown transport

    @Published package var countdownTransport: CountdownTransport = .stopped

    // Runtime style override for the active countdown, set by the "1"
    // key (audience-facing red button). Cycles .digital → .pie →
    // .hourglass → .digital independently of the JSON `style`. Reset to
    // nil whenever the lineup cursor moves so each countdown starts
    // from its authored default.
    @Published package var countdownStyleOverride: CountdownStyle? = nil

    // Runtime message-rotation offset for the active countdown, advanced
    // by the "2" key (audience-facing green button). Each press adds 1;
    // CountdownView lays this over the time-based index so a press
    // immediately reveals the next message instead of waiting for the
    // next interval boundary. Reset to 0 when the lineup cursor moves.
    @Published package var countdownMessageOffset: Int = 0

    // Runtime post-effect override for the active song, set by the "1"
    // key (audience-facing red button) while a song is current. Cycles
    // through .glitch / .tracking / .chroma and reverts to nil after a
    // short timeout (managed by KeyboardHandler) so audience-triggered
    // effects always feel temporary. Layered on top of the part's JSON
    // visualEffect via effectiveVisualEffect.
    @Published package var songEffectOverride: PostEffect? = nil

    // Wall-clock timestamp of the most recent audience-triggered effect
    // press during a song. VisualsView reads this to render a brief
    // white-flash overlay on top of everything (post-effect included)
    // so the audience gets unambiguous feedback that their button press
    // landed. .distantPast = no flash currently visible.
    @Published package var audienceFlashTriggeredAt: Date = .distantPast

    // Wall-clock deadline for the active songEffectOverride. Set to
    // `Date() + holdSeconds` when the override is armed, .distantPast
    // when no override is active. The telemetry panel reads this to
    // show a live "Xs remaining" countdown without having to reach
    // into KeyboardHandler's DispatchWorkItem.
    @Published package var songEffectExpiresAt: Date = .distantPast

    // True while the telemetry panel is visible during a song. Toggled
    // by audience-facing "2" presses — first press shows, second press
    // hides early, and a timer in KeyboardHandler auto-hides after a
    // few seconds in case the audience forgets. (Was previously a
    // hold-to-show flag, but the hardware buttons in the rig only fire
    // on press, not release, so a tap-toggle is the only thing that
    // actually works.) Cleared on lineup move or videoClip onset.
    @Published package var telemetryVisible: Bool = false

    // Wall-clock timestamp of the last audience "wrong button" press
    // on an AudienceInteractive item. AudienceInteractiveView reads
    // this to flash a momentary "WRONG BUTTON" overlay (red, ~1.5 s)
    // before reverting to the per-kind prompt. .distantPast = no
    // error currently displayed.
    @Published package var wrongButtonAt: Date = .distantPast

    // Multi-step state for the active "transmission" audience-
    // interactive (e.g. The Breakup). .idle when none is running;
    // otherwise tracks which exchange is on screen and which
    // momentary phase (replyEcho, preIncomingBlank, deletedFlash)
    // the bit is in. Driven by KeyboardHandler-managed timers — the
    // view just renders whatever phase is current.
    @Published package var transmissionPhase: TransmissionPhase = .idle

    // Multi-step state for the active "lottery" audience-interactive
    // (The Lottery). .idle when none is running; otherwise tracks
    // which of the six bit phases (setup → wheel → spinning →
    // resultPending → revealIntro → prizeDisplay → fading) the screen
    // is in, plus the randomly-chosen landing slice and prize string.
    // Driven by KeyboardHandler timers + the audience green press;
    // the view renders off whichever phase is current.
    @Published package var lotteryPhase: LotteryPhase = .idle

    // MARK: - Per-song state (only meaningful when currentSong != nil)

    @Published package var currentPartIndex: Int = 0    // index into current song's structure
    @Published package var currentBar: Int = 0          // bar within current part (0-based)
    @Published package var pendingPartIndex: Int? = nil // queued part jump on next bar
    @Published package var loopCurrentPart: Bool = false

    // MARK: - Misc state

    @Published package var visualsOpen: Bool = true

    // Tweak mode swaps the HUD's right column from lyrics to a
    // structured field list of every tweakable parameter on the
    // current song (kit, sounds, theme, visualizer, count-in, plus
    // per-part pad/bass levels and visual fields). Works whether
    // transport is playing or stopped — cycling values mid-playback
    // and hearing them land is the intended workflow. See
    // ContentView and KeyboardHandler for the editor surface.
    @Published package var tweakMode: Bool = false

    // Cursor position into the tweak field list (built by
    // `TweakField.fields(for:)`). Reset to 0 on every entry into
    // tweak mode so it's always valid and predictable.
    @Published package var tweakCursor: Int = 0

    // Filenames in ~/BackTrack/Visuals/, scanned once at launch via
    // VisualsLibrary.scanAll. Powers the `partVisuals` cycle in
    // tweak mode. Restart-only refresh (matches sample folders).
    @Published package var visualsLibrary: [String] = []

    // Filenames in ~/BackTrack/VideoClips/. Same lifecycle as the
    // visuals library — scanned at launch; restart to pick up new
    // files. Powers the `partVideoClip` cycle in tweak mode.
    @Published package var videoClipsLibrary: [String] = []

    // URL of the video clip that's currently rendering in the
    // visuals window (nil = no clip). Set by Clock when the
    // transport enters a part with a `videoClip`; cleared when the
    // clip plays through to its end, when transport stops, or when
    // the part / lineup item changes. The visuals window observes
    // this and renders an unmuted AVPlayer over the rest of the
    // visual layers when set.
    @Published package var activeVideoClip: URL? = nil

    // Audio gain applied to `activeVideoClip` (0.0–1.0). Mirrors the
    // current part's `videoClipVolume / 100`.
    @Published package var activeVideoClipVolume: Float = 1.0

    // Most recent successful tweak-mode save — used for the toast
    // shown beneath the field list ("saved → kit: 808"). The toast
    // fades over a short window via TimelineView reading lastSaved.
    @Published package var tweakLastSaved: Date = .distantPast
    @Published package var tweakLastSavedNote: String = ""

    // Bridge from views (e.g. interstitial video onFinish) back to
    // KeyboardHandler's lineup-cursor logic. Set by KeyboardHandler
    // at init; called by VisualsView when an interstitial finishes
    // playing or its duration timer expires. Doing it through a
    // closure avoids a direct view→controller dependency in either
    // direction.
    package var advanceLineupCursor: (() -> Void)?

    // MARK: - Visual resolvers (read straight from JSON)

    package var effectiveTheme: VisualTheme {
        currentSong?.theme ?? .dark
    }

    package var effectiveVisualizer: VisualizerStyle {
        currentPart?.visualizer ?? currentSong?.visualizer ?? .constellation
    }

    package var effectiveCountdownStyle: CountdownStyle {
        countdownStyleOverride ?? currentCountdown?.style ?? .digital
    }

    // visualEffect lives on Part for songs and on Countdown for countdowns.
    // The audience "1" button can temporarily override the song-side
    // value via songEffectOverride; that override wins until it
    // auto-reverts a few seconds later (timer in KeyboardHandler).
    package var effectiveVisualEffect: PostEffect {
        if let override = songEffectOverride, currentSong != nil { return override }
        if let p = currentPart { return p.visualEffect }
        if let c = currentCountdown { return c.visualEffect }
        return .none
    }

    // MARK: - Per-song derived state

    package var currentPartName: String? {
        guard let song = currentSong,
              currentPartIndex >= 0,
              currentPartIndex < song.structure.count else { return nil }
        return song.structure[currentPartIndex]
    }

    package var currentPart: Part? {
        guard let name = currentPartName, let song = currentSong else { return nil }
        return song.parts[name]
    }

    package var currentChord: Chord? {
        guard let part = currentPart else { return nil }
        return part.chord(atBar: currentBar)
    }

    package var currentPartVisualURL: URL? {
        guard let part = currentPart,
              let name = part.visualFilename(bar: currentBar, beat: currentBeat),
              !name.isEmpty else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Visuals")
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    package var nextChord: Chord? {
        guard let part = currentPart else { return nil }
        if currentBar + 1 < part.bars {
            return part.chord(atBar: currentBar + 1)
        }
        guard let song = currentSong,
              currentPartIndex + 1 < song.structure.count,
              let nextPart = song.parts[song.structure[currentPartIndex + 1]] else { return nil }
        return nextPart.chord(atBar: 0)
    }

    // MARK: - Activity timestamps (HUD dots)

    @Published package var kickLastTrigger: Date = .distantPast
    @Published package var snareLastTrigger: Date = .distantPast
    @Published package var hhLastTrigger: Date = .distantPast
    @Published package var padLastTrigger: Date = .distantPast
    @Published package var bassLastTrigger: Date = .distantPast
    @Published package var outLastSignal: Date = .distantPast

    // MARK: - Sample directories (discovered at load)

    @Published package var drumKitNames: [String] = []
    @Published package var padSoundNames: [String] = []
    @Published package var bassSoundNames: [String] = []
    @Published package var missingSamples: [String] = []

    // MARK: - Device display

    @Published package var outputDevice: String? = nil

    // MARK: - Lineup construction

    // Resolves the active setlist's refs (or falls back to all songs +
    // all countdowns when none is active) and writes the result to
    // `lineup` + `setlistIssues`. Called by Coordinator whenever any
    // input changes — songs reload, countdowns reload, setlists
    // reload, or D-key changes the active setlist.
    //
    // Doesn't touch `currentLineupIndex` aside from clamping it into
    // range — preserving the cursor across reloads is the friendly
    // behavior (e.g. an unrelated countdown JSON edit shouldn't snap
    // you back to item 0). Index resets are the caller's job (e.g.
    // KeyboardHandler clears the cursor on D-cycle).
    package var platformCapabilities: PlatformCapabilities = .full

    package func rebuildLineup() {
        let built = LineupBuilder.build(
            LineupBuilder.Input(
                songs: songs,
                countdowns: countdowns,
                interstitials: interstitials,
                audienceInteractives: audienceInteractives,
                activeSetlist: currentSetlist,
                capabilities: platformCapabilities
            )
        )
        lineup = built.lineup
        setlistIssues = (setlistIssues + built.resolveIssues).filter { !$0.isEmpty }
        if currentLineupIndex >= lineup.count {
            currentLineupIndex = max(0, lineup.count - 1)
        }
    }
}
