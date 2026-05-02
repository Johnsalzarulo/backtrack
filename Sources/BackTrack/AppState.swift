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
final class AppState: ObservableObject {
    // MARK: - Transport

    @Published var isPlaying: Bool = false
    @Published var currentBeat: Int = 0

    // Wall-clock timestamp of the last quarter-note tick. Stamped by
    // Clock when currentBeat advances (and by the count-in path).
    // Visual effects read this to drive beat-synced animation.
    @Published var lastBeatTime: Date = .distantPast

    // Count-in state. While the Clock is firing pre-roll clicks,
    // `countInBeat` is the 1-based beat number within the count-in
    // (1...countInTotal) and `countInTotal` is the total beats
    // (countIn × 4). Both reset to 0/nil once the song proper begins
    // or playback stops.
    @Published var countInBeat: Int? = nil
    @Published var countInTotal: Int = 0

    // MARK: - Inventories (loaded from disk; rarely changes)

    @Published var songs: [Song] = []
    @Published var countdowns: [Countdown] = []
    @Published var setlists: [Setlist] = []

    @Published var songIssues: [String] = []
    @Published var countdownIssues: [String] = []
    @Published var setlistIssues: [String] = []

    // MARK: - Lineup (the navigable arrangement)

    // The ordered list arrows + Space act on. Built by `rebuildLineup`
    // from the active setlist, or by concatenating songs + countdowns
    // when no setlist is active.
    @Published var lineup: [LineupItem] = []
    @Published var currentLineupIndex: Int = 0

    // Index of the active setlist within `setlists`. Cycled via the D
    // key. Only meaningful when !setlists.isEmpty — otherwise lineup
    // falls back to the "all songs + all countdowns" combined view.
    @Published var currentSetlistIndex: Int = 0

    var currentLineupItem: LineupItem? {
        guard lineup.indices.contains(currentLineupIndex) else { return nil }
        return lineup[currentLineupIndex]
    }

    var currentSetlist: Setlist? {
        guard setlists.indices.contains(currentSetlistIndex) else { return nil }
        return setlists[currentSetlistIndex]
    }

    // Legacy accessors — derived from the lineup item so existing call
    // sites (Clock, ContentView, VisualsView) keep working without
    // having to switch on LineupItem at every use. Mutually exclusive:
    // exactly one is non-nil at a time when the lineup isn't empty.
    var currentSong: Song? {
        if case .song(let s) = currentLineupItem { return s }
        return nil
    }

    var currentCountdown: Countdown? {
        if case .countdown(let c) = currentLineupItem { return c }
        return nil
    }

    // MARK: - Countdown transport

    @Published var countdownTransport: CountdownTransport = .stopped

    // MARK: - Per-song state (only meaningful when currentSong != nil)

    @Published var currentPartIndex: Int = 0    // index into current song's structure
    @Published var currentBar: Int = 0          // bar within current part (0-based)
    @Published var pendingPartIndex: Int? = nil // queued part jump on next bar
    @Published var loopCurrentPart: Bool = false

    // MARK: - Misc state

    @Published var visualsOpen: Bool = true

    // Tweak mode swaps the HUD's right column from lyrics to a
    // structured field list of every tweakable parameter on the
    // current song (kit, sounds, theme, visualizer, count-in, plus
    // per-part pad/bass levels and visual fields). Works whether
    // transport is playing or stopped — cycling values mid-playback
    // and hearing them land is the intended workflow. See
    // ContentView and KeyboardHandler for the editor surface.
    @Published var tweakMode: Bool = false

    // Cursor position into the tweak field list (built by
    // `TweakField.fields(for:)`). Reset to 0 on every entry into
    // tweak mode so it's always valid and predictable.
    @Published var tweakCursor: Int = 0

    // Filenames in ~/BackTrack/Visuals/, scanned once at launch via
    // VisualsLibrary.scanAll. Powers the `partVisuals` cycle in
    // tweak mode. Restart-only refresh (matches sample folders).
    @Published var visualsLibrary: [String] = []

    // Most recent successful tweak-mode save — used for the toast
    // shown beneath the field list ("saved → kit: 808"). The toast
    // fades over a short window via TimelineView reading lastSaved.
    @Published var tweakLastSaved: Date = .distantPast
    @Published var tweakLastSavedNote: String = ""

    // MARK: - Visual resolvers (read straight from JSON)

    var effectiveTheme: VisualTheme {
        currentSong?.theme ?? .dark
    }

    var effectiveVisualizer: VisualizerStyle {
        currentPart?.visualizer ?? currentSong?.visualizer ?? .constellation
    }

    var effectiveCountdownStyle: CountdownStyle {
        currentCountdown?.style ?? .digital
    }

    // visualEffect lives on Part for songs and on Countdown for countdowns.
    var effectiveVisualEffect: PostEffect {
        if let p = currentPart { return p.visualEffect }
        if let c = currentCountdown { return c.visualEffect }
        return .none
    }

    // MARK: - Per-song derived state

    var currentPartName: String? {
        guard let song = currentSong,
              currentPartIndex >= 0,
              currentPartIndex < song.structure.count else { return nil }
        return song.structure[currentPartIndex]
    }

    var currentPart: Part? {
        guard let name = currentPartName, let song = currentSong else { return nil }
        return song.parts[name]
    }

    var currentChord: Chord? {
        guard let part = currentPart else { return nil }
        return part.chord(atBar: currentBar)
    }

    var currentPartVisualURL: URL? {
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

    var nextChord: Chord? {
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

    @Published var kickLastTrigger: Date = .distantPast
    @Published var snareLastTrigger: Date = .distantPast
    @Published var hhLastTrigger: Date = .distantPast
    @Published var padLastTrigger: Date = .distantPast
    @Published var bassLastTrigger: Date = .distantPast
    @Published var outLastSignal: Date = .distantPast

    // MARK: - Sample directories (discovered at load)

    @Published var drumKitNames: [String] = []
    @Published var padSoundNames: [String] = []
    @Published var bassSoundNames: [String] = []
    @Published var missingSamples: [String] = []

    // MARK: - Device display

    @Published var outputDevice: String? = nil

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
    func rebuildLineup() {
        var resolveIssues: [String] = []
        let resolved: [LineupItem]

        if let active = currentSetlist {
            var items: [LineupItem] = []
            for ref in active.items {
                switch ref {
                case .song(let n):
                    if let s = songs.first(where: { $0.name == n }) {
                        items.append(.song(s))
                    } else {
                        resolveIssues.append(
                            "setlist '\(active.name)': song '\(n)' not found in Songs/"
                        )
                    }
                case .countdown(let n):
                    if let c = countdowns.first(where: { $0.name == n }) {
                        items.append(.countdown(c))
                    } else {
                        resolveIssues.append(
                            "setlist '\(active.name)': countdown '\(n)' not found in Countdowns/"
                        )
                    }
                }
            }
            resolved = items
        } else {
            // No setlist → fall back to "all songs then all countdowns".
            resolved = songs.map(LineupItem.song) + countdowns.map(LineupItem.countdown)
        }

        lineup = resolved
        // Resolve issues are appended to whatever the loader produced.
        // The loader writes to setlistIssues first; we additionally
        // append unresolved-ref issues here. Coordinator orchestrates
        // the order so the loader's setlistIssues are present when
        // rebuildLineup runs.
        setlistIssues = (setlistIssues + resolveIssues).filter { !$0.isEmpty }

        if currentLineupIndex >= lineup.count {
            currentLineupIndex = max(0, lineup.count - 1)
        }
    }
}
