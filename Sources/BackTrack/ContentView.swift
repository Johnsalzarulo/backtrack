import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    private let fg = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let dim = Color(white: 0.45)
    private let accent = Color(red: 0.82, green: 0.92, blue: 0.82)
    // Tweak-mode chrome — warm red so the editor surface is unmistakable
    // against the normal pale-green ink. Used for the EDITING header,
    // part section labels, and field label rows when tweakMode is on.
    private let editAccent = Color(red: 1.0, green: 0.42, blue: 0.42)
    private let editDim = Color(red: 0.7, green: 0.30, blue: 0.30)
    private let activityDecay: TimeInterval = 0.18

    // Left column is a fixed-width, stable layout (structure, chord, mix,
    // transport, keybindings). Right column holds the variable-height
    // content (song header + lyrics) so a long verse doesn't shove the
    // left-hand performance readout around.
    private let leftColumnWidth: CGFloat = 480

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            leftColumn
                .frame(width: leftColumnWidth, alignment: .topLeading)
            rightColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(
            minWidth: 1000,
            maxWidth: .infinity,
            minHeight: 560,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color.black)
        .foregroundColor(fg)
        .font(.system(.body, design: .monospaced))
        .onChange(of: state.visualsOpen) { open in
            if open {
                openWindow(id: "visuals")
            } else {
                closeVisualsWindow()
            }
        }
        .onAppear {
            // SwiftUI's secondary `Window` scene doesn't reliably
            // auto-open at launch on macOS 13. Force-open it here if
            // the user's visualsOpen preference is true (the default),
            // so videoClip / synth / GIF rendering all happen out of
            // the box without the user pressing V first.
            if state.visualsOpen {
                openWindow(id: "visuals")
            }
        }
    }

    // macOS 13 doesn't have SwiftUI.dismissWindow (macOS 14+). Walk
    // NSApp.windows and match on title (the scene-id route via
    // NSWindow.identifier isn't reliably populated by SwiftUI).
    private func closeVisualsWindow() {
        VisualsWindow.find()?.close()
    }

    // MARK: - Left column (context info)

    // Left column carries "context I glance at occasionally": which
    // song / where in the structure / what's loaded into the mix /
    // what's playing on the visuals. Performance-critical info
    // (chord, beat, bar progress, lyrics) lives in the right column
    // so the eye doesn't have to ping-pong across the screen mid-song.
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.currentSong != nil {
                songMetadataBlock
            }
            structureBlock
            if state.currentSong != nil {
                mixBlock
            }
            Spacer(minLength: 0)
            transportLine
            issuesBlock
            keybindingBlock
        }
    }

    // SONG / KEY / BPM — moved here from the right column as part of
    // the performance-column refactor. Shows for songs only; for
    // countdowns/interstitials the structureBlock below carries the
    // relevant per-item meta instead.
    @ViewBuilder
    private var songMetadataBlock: some View {
        if let song = state.currentSong {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("SONG").foregroundColor(dim).frame(width: 44, alignment: .leading)
                    Text(song.name)
                }
                if !song.key.isEmpty {
                    HStack(spacing: 10) {
                        Text("KEY").foregroundColor(dim).frame(width: 44, alignment: .leading)
                        Text(song.key)
                    }
                }
                HStack(spacing: 10) {
                    Text("BPM").foregroundColor(dim).frame(width: 44, alignment: .leading)
                    Text("\(Int(song.bpm.rounded()))")
                }
            }
        }
    }

    @ViewBuilder
    private var structureBlock: some View {
        if state.currentCountdown != nil {
            countdownDeckBlock
        } else if state.currentInterstitial != nil {
            interstitialDeckBlock
        } else if state.currentAudienceInteractive != nil {
            audienceInteractiveDeckBlock
        } else {
            songStructureBlock
        }
    }

    private var audienceInteractiveDeckBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AUDIENCE INTERACTIVE")
                .foregroundColor(dim)
                .font(.system(.caption, design: .monospaced))
            if let a = state.currentAudienceInteractive {
                partBadge(name: a.name, isActive: true, isQueued: false)
                HStack(spacing: 10) {
                    Text(a.kind.rawValue.uppercased())
                }
                .foregroundColor(dim)
                .font(.system(.caption, design: .monospaced))
            } else {
                Text("no audience-interactive selected").foregroundColor(dim)
            }
        }
    }

    private var interstitialDeckBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INTERSTITIAL")
                .foregroundColor(dim)
                .font(.system(.caption, design: .monospaced))
            if let i = state.currentInterstitial {
                partBadge(name: i.name, isActive: true, isQueued: false)
                HStack(spacing: 10) {
                    Text(i.kind.rawValue.uppercased())
                    if let d = i.duration {
                        Text("· \(Int(d))s")
                    }
                    if i.kind == .video && i.loop {
                        Text("· LOOP")
                    }
                }
                .foregroundColor(dim)
                .font(.system(.caption, design: .monospaced))
            } else {
                Text("no interstitial selected").foregroundColor(dim)
            }
        }
    }

    private var songStructureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("STRUCTURE")
                    .foregroundColor(dim)
                    .font(.system(.caption, design: .monospaced))
                if state.loopCurrentPart {
                    Text("LOOP")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(fg)
                }
            }
            if let song = state.currentSong {
                FlowLayout(spacing: 10) {
                    ForEach(Array(song.structure.enumerated()), id: \.offset) { idx, name in
                        partBadge(
                            name: name,
                            isActive: idx == state.currentPartIndex,
                            isQueued: idx == state.pendingPartIndex
                        )
                    }
                }
                // Bar counter + progress moved to the right column's
                // performanceChordBlock so it lives next to chord +
                // beat dots — all "where am I right now" info in one
                // glance, no eye ping-pong to the left column.
            } else {
                Text("no songs loaded").foregroundColor(dim)
            }
        }
    }

    // Countdown-mode equivalent of the song structure block. Shows
    // the active countdown's name as the "active" badge plus a live
    // remaining-time readout that ticks at 4 Hz (the giant timer in
    // the visuals window handles the smooth hundredths display).
    private var countdownDeckBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COUNTDOWN")
                .foregroundColor(dim)
                .font(.system(.caption, design: .monospaced))
            if let c = state.currentCountdown {
                partBadge(name: c.name, isActive: true, isQueued: false)
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(countdownStatusLine(for: c, at: context.date))
                        .foregroundColor(dim)
                        .font(.system(.caption, design: .monospaced))
                }
            } else {
                Text("no countdown selected").foregroundColor(dim)
            }
        }
    }

    private func countdownStatusLine(for c: Countdown, at now: Date) -> String {
        let elapsed = state.countdownTransport.elapsed(at: now)
        let remaining = max(0, c.duration - elapsed)
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return "\(m):\(String(format: "%02d", s)) remaining · \(Int(c.duration / 60)) min total"
    }

    private func partBadge(name: String, isActive: Bool, isQueued: Bool) -> some View {
        Text(isActive ? "▸\(name.uppercased())◂" : name)
            .foregroundColor(isActive ? fg : (isQueued ? accent.opacity(0.8) : dim))
    }

    // One cell per bar: filled (█) through the current bar, empty (░) for
    // bars remaining. Makes "how many bars are left" glanceable during
    // instrumental sections with no lyrics.
    private func partProgressBar(current: Int, total: Int) -> String {
        let filled = max(0, min(total, current + 1))
        let empty = max(0, total - filled)
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    private var divider: some View {
        Rectangle()
            .fill(dim.opacity(0.3))
            .frame(height: 1)
    }

    // Performance chord block — the right-column header above lyrics.
    // Big chord (56pt), smaller next-chord preview, beat dots at the
    // right, and the bar counter / progress underneath. Replaces the
    // smaller chord line that previously sat in the left column.
    private var chordLine: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                Text(state.currentChord?.display ?? "—")
                    .font(.system(size: 56, weight: .regular, design: .monospaced))
                if let next = state.nextChord {
                    Text("→ \(next.display)")
                        .foregroundColor(dim)
                        .font(.system(size: 32, design: .monospaced))
                }
                Spacer(minLength: 0)
                beatDots
            }
            if let part = state.currentPart {
                HStack(spacing: 12) {
                    Text("bar \(state.currentBar + 1) / \(part.bars)")
                    Text(partProgressBar(current: state.currentBar, total: part.bars))
                }
                .foregroundColor(dim)
                .font(.system(size: 18, design: .monospaced))
            }
        }
    }

    // 1 / 2 / 3 / 4 beat counter next to the chord display so you can see
    // where the downbeat is and come in on the one. Leftmost dot is
    // beat 1; lit dot tracks the current beat.
    private var beatDots: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(beatDotColor(i))
                        .frame(width: 18, height: 18)
                }
            }
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(dim)
                        .frame(width: 18)
                }
            }
        }
    }

    private func beatDotColor(_ i: Int) -> Color {
        if state.isPlaying && i == state.currentBeat { return fg }
        return dim.opacity(0.4)
    }

    // One row per role (drums / pad / bass). Each row surfaces:
    //   - activity light that fires on any trigger into that role
    //   - the role label
    //   - relevant meta: current drum pattern + kit, or pad/bass sound
    private var mixBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            drumsRow
            padRow
            bassRow
        }
    }

    private var drumsRow: some View {
        HStack(spacing: 14) {
            drumsActivityLight
            Text("DRUMS").foregroundColor(dim).frame(width: 60, alignment: .leading)
            patternField
            metaPair(label: "Kit", value: state.currentSong?.kit)
        }
    }

    @ViewBuilder
    private var patternField: some View {
        if let part = state.currentPart {
            HStack(spacing: 6) {
                Text("Pattern:").foregroundColor(dim.opacity(0.7))
                Text(part.pattern)
            }
        }
    }

    private var padRow: some View {
        HStack(spacing: 14) {
            activityLight(last: state.padLastTrigger)
            Text("PAD").foregroundColor(dim).frame(width: 60, alignment: .leading)
            metaPair(label: "Sound", value: state.currentSong?.padSound)
        }
    }

    private var bassRow: some View {
        HStack(spacing: 14) {
            activityLight(last: state.bassLastTrigger)
            Text("BASS").foregroundColor(dim).frame(width: 60, alignment: .leading)
            metaPair(label: "Sound", value: state.currentSong?.bassSound)
        }
    }

    // Aggregate drums light — fires on any kick / snare / hh hit.
    private var drumsActivityLight: some View {
        let latest = max(state.kickLastTrigger, max(state.snareLastTrigger, state.hhLastTrigger))
        return activityLight(last: latest)
    }

    @ViewBuilder
    private func metaPair(label: String, value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack(spacing: 6) {
                Text("\(label):").foregroundColor(dim.opacity(0.7))
                Text(value)
            }
        }
    }

    private func activityLight(last: Date) -> some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(last)
            let brightness = max(0, 1 - elapsed / activityDecay)
            Circle()
                .fill(fg)
                .opacity(max(0.12, brightness))
                .frame(width: 8, height: 8)
        }
    }

    private var transportLine: some View {
        Text(transportLabel)
            .font(.system(size: 18, design: .monospaced))
    }

    private var transportLabel: String {
        if state.currentCountdown != nil {
            switch state.countdownTransport {
            case .stopped: return "○ STOPPED"
            case .running: return "● COUNTING"
            case .paused: return "❙❙ PAUSED"
            }
        }
        if let beat = state.countInBeat, state.countInTotal > 0 {
            return "● COUNT-IN \(beat)/\(state.countInTotal)"
        }
        return state.isPlaying ? "● PLAYING" : "○ STOPPED"
    }

    @ViewBuilder
    private var issuesBlock: some View {
        let blocks = issuesToShow
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(blocks, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(dim)
                }
            }
        }
    }

    private var issuesToShow: [String] {
        var all: [String] = []
        if !state.missingSamples.isEmpty {
            all.append("MISSING SAMPLES")
            all.append(contentsOf: state.missingSamples)
        }
        if !state.songIssues.isEmpty {
            if !all.isEmpty { all.append("") }
            all.append("SONG ISSUES")
            all.append(contentsOf: state.songIssues)
        }
        if !state.countdownIssues.isEmpty {
            if !all.isEmpty { all.append("") }
            all.append("COUNTDOWN ISSUES")
            all.append(contentsOf: state.countdownIssues)
        }
        if !state.interstitialIssues.isEmpty {
            if !all.isEmpty { all.append("") }
            all.append("INTERSTITIAL ISSUES")
            all.append(contentsOf: state.interstitialIssues)
        }
        if !state.audienceInteractiveIssues.isEmpty {
            if !all.isEmpty { all.append("") }
            all.append("AUDIENCE-INTERACTIVE ISSUES")
            all.append(contentsOf: state.audienceInteractiveIssues)
        }
        if !state.setlistIssues.isEmpty {
            if !all.isEmpty { all.append("") }
            all.append("SETLIST ISSUES")
            all.append(contentsOf: state.setlistIssues)
        }
        return all
    }

    private var keybindingBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("SPACE", "start / stop",        "← →", "prev / next item")
            row("↑ ↓",   "next / prev part",    "L",   "loop current part")
            row("D",     "cycle setlist",       "V",   "show / hide visuals")
            row("F",     "visuals full-screen", "\\",  "tweak mode")
            row("1",     "song fx / cdn style", "2",   "telemetry / next msg")
        }
        .foregroundColor(dim)
        .font(.system(.caption, design: .monospaced))
    }

    private func row(_ k1: String, _ d1: String, _ k2: String, _ d2: String) -> some View {
        HStack(spacing: 0) {
            Text(k1).frame(width: 80, alignment: .leading)
            Text(d1).frame(width: 180, alignment: .leading)
            Text(k2).frame(width: 56, alignment: .leading)
            Text(d2)
        }
    }

    // MARK: - Right column (the performance column)

    // The right column is the singer's eye-line during a song:
    // setlist position (top), then chord + beat + bar progress, then
    // lyrics, then the next-part preview. All vertical, no horizontal
    // jumping. For non-song lineup items the chord block is replaced
    // by the appropriate header (countdown / interstitial). Tweak
    // mode hijacks the whole column for the field-list editor.
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            setlistPositionBlock
            if state.tweakMode {
                tweakHeader
                divider
                tweakFieldList
                tweakSaveToast
            } else if state.currentCountdown != nil {
                countdownHeaderBlock
            } else if let i = state.currentInterstitial {
                interstitialHeaderBlock
                divider
                interstitialNotesBlock(notes: i.notes)
            } else if state.currentAudienceInteractive != nil {
                audienceInteractiveHeaderBlock
            } else {
                // Song path — chord block as the eye-anchor, lyrics
                // immediately below. SONG/KEY/BPM moved to the left
                // column so this column is purely moment-to-moment
                // performance info.
                chordLine
                songLyricsBlock
            }
            Spacer(minLength: 0)
            visualsPreviewBlock
            outDeviceBlock
        }
    }

    // MARK: - Tweak mode

    private var tweakHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle()
                    .fill(editAccent)
                    .frame(width: 10, height: 10)
                Text("EDITING")
                    .foregroundColor(editAccent)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("—")
                    .foregroundColor(editDim)
                Text(state.currentSong?.name.uppercased() ?? "—")
                    .foregroundColor(editAccent)
                    .font(.system(size: 16, design: .monospaced))
            }
            HStack(spacing: 10) {
                Text("AUTO-SAVE")
                    .foregroundColor(editDim)
                    .font(.system(.caption2, design: .monospaced))
                Text("↑↓ field   ←→ value   \\ exit")
                    .foregroundColor(editDim)
                    .font(.system(.caption2, design: .monospaced))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(editAccent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(editAccent.opacity(0.45), lineWidth: 1)
        )
    }

    // Toast that flashes at the bottom of the field list each time a
    // cycle saves. Fades over ~1.5 s so consecutive cycles re-trigger
    // it cleanly, but it doesn't linger and clutter the layout.
    private var tweakSaveToast: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(state.tweakLastSaved)
            let visibleWindow: TimeInterval = 1.5
            let opacity = max(0, 1 - elapsed / visibleWindow)
            Text(state.tweakLastSavedNote)
                .foregroundColor(editAccent)
                .font(.system(.caption, design: .monospaced))
                .opacity(opacity)
        }
    }

    @ViewBuilder
    private var tweakFieldList: some View {
        if let song = state.currentSong {
            let fields = TweakField.fields(for: song)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { idx, field in
                            if let header = sectionHeader(at: idx, in: fields) {
                                Text(header)
                                    .foregroundColor(editAccent)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.top, idx == 0 ? 0 : 8)
                            }
                            tweakFieldRow(field, song: song, focused: idx == state.tweakCursor)
                                .id(idx)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 2)
                }
                .onChange(of: state.tweakCursor) { newIdx in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        } else {
            Text("no song selected").foregroundColor(dim)
        }
    }

    // A "PART NAME" header appears whenever the part name changes
    // between successive fields. Song-level fields (no part name)
    // get no header — the EDITING banner above is enough for them.
    private func sectionHeader(at idx: Int, in fields: [TweakField]) -> String? {
        let current = fields[idx].partName
        let prev = idx > 0 ? fields[idx - 1].partName : nil
        if current != prev, let p = current {
            return p.uppercased()
        }
        return nil
    }

    private func tweakFieldRow(_ field: TweakField, song: Song, focused: Bool) -> some View {
        HStack(spacing: 8) {
            Text(focused ? "▸" : " ")
                .foregroundColor(editAccent)
                .frame(width: 12, alignment: .leading)
            Text(field.label)
                .foregroundColor(focused ? editAccent : editDim)
                .frame(width: 130, alignment: .leading)
            Text(field.displayValue(in: song))
                .foregroundColor(focused ? fg : fg.opacity(0.7))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(focused ? editAccent.opacity(0.12) : Color.clear)
        )
    }

    // Setlist marquee shown above the song / countdown header. Tells
    // the performer at a glance: which setlist they're on (when one
    // is active), where they are within it, and what's coming next.
    // Hidden entirely when no setlist is active and there's only one
    // lineup item — there's nothing useful to say.
    @ViewBuilder
    private var setlistPositionBlock: some View {
        if state.lineup.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Text("SET")
                    .foregroundColor(dim)
                    .frame(width: 44, alignment: .leading)
                if let setlist = state.currentSetlist {
                    Text(setlist.name.uppercased())
                        .foregroundColor(fg)
                }
                Text("\(state.currentLineupIndex + 1) / \(state.lineup.count)")
                    .foregroundColor(dim)
                if let next = upcomingItemName {
                    Text("→  \(next.uppercased())")
                        .foregroundColor(dim)
                        .lineLimit(1)
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private var upcomingItemName: String? {
        let nextIdx = state.currentLineupIndex + 1
        guard nextIdx < state.lineup.count else { return nil }
        return state.lineup[nextIdx].name
    }

    // Live preview of the secondary visuals window, shown inline in
    // the HUD so the performer can see what the audience sees without
    // looking at the other monitor. Uses the same VisualsView in
    // preview mode (skips window-level modifiers).
    private var visualsPreviewBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VISUALS")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(dim)
            VisualsView(isPreview: true)
                .frame(width: 200, height: 150)
                .overlay(
                    Rectangle()
                        .stroke(dim.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var countdownHeaderBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("COUNT").foregroundColor(dim).frame(width: 44, alignment: .leading)
                Text(state.currentCountdown?.name ?? "—")
            }
            if let c = state.currentCountdown {
                HStack(spacing: 10) {
                    Text("LEN").foregroundColor(dim).frame(width: 44, alignment: .leading)
                    Text("\(Int(c.duration / 60)) min")
                }
            }
        }
    }

    private var interstitialHeaderBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("INTER").foregroundColor(dim).frame(width: 44, alignment: .leading)
                Text(state.currentInterstitial?.name ?? "—")
            }
            if let i = state.currentInterstitial {
                HStack(spacing: 10) {
                    Text("KIND").foregroundColor(dim).frame(width: 44, alignment: .leading)
                    Text(i.kind.rawValue)
                }
            }
        }
    }

    private var audienceInteractiveHeaderBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("AUDX").foregroundColor(dim).frame(width: 44, alignment: .leading)
                Text(state.currentAudienceInteractive?.name ?? "—")
            }
            if let a = state.currentAudienceInteractive {
                HStack(spacing: 10) {
                    Text("KIND").foregroundColor(dim).frame(width: 44, alignment: .leading)
                    Text(a.kind.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private func interstitialNotesBlock(notes: String) -> some View {
        if notes.isEmpty {
            EmptyView()
        } else {
            Text(notes)
                .font(.system(size: 16, design: .monospaced))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var songLyricsBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Active part's lyrics.
            if let part = state.currentPart, !part.lyrics.isEmpty {
                Text(part.lyrics)
                    .font(.system(size: 16, design: .monospaced))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(" ")
                    .font(.system(size: 16, design: .monospaced))
            }

            // Peek of what's coming next so the first lyric of a chorus /
            // verse isn't a surprise — especially useful when starting from
            // an instrumental intro.
            if let preview = nextPartPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT — \(preview.name.uppercased())")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(dim)
                    if !preview.firstLine.isEmpty {
                        Text(preview.firstLine)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(dim.opacity(0.75))
                    }
                }
            }
        }
    }

    // Next part to play: a queued jump if set, otherwise the next entry
    // in the song structure. Nil on the last part of the song with no
    // pending jump (song ends here).
    private var nextPartPreview: (name: String, firstLine: String)? {
        guard let song = state.currentSong else { return nil }
        let nextIdx: Int
        if let pending = state.pendingPartIndex {
            nextIdx = pending
        } else if state.currentPartIndex + 1 < song.structure.count {
            nextIdx = state.currentPartIndex + 1
        } else {
            return nil
        }
        guard nextIdx >= 0 && nextIdx < song.structure.count else { return nil }
        let name = song.structure[nextIdx]
        guard let part = song.parts[name] else { return nil }
        let first = part.lyrics.split(separator: "\n").first.map(String.init) ?? ""
        return (name, first)
    }

    private var outDeviceBlock: some View {
        HStack(spacing: 8) {
            smallSignalDot(last: state.outLastSignal)
            Text("OUT").foregroundColor(dim)
            Text(state.outputDevice ?? "—")
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func smallSignalDot(last: Date) -> some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(last)
            let brightness = max(0, 1 - elapsed / 0.35)
            Circle()
                .fill(fg)
                .opacity(max(0.12, brightness))
                .frame(width: 6, height: 6)
        }
    }
}

// Simple wrapping flow layout so the STRUCTURE row can wrap to multiple
// lines when a song has a long part list instead of clipping.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth && currentRowWidth > 0 {
                totalHeight += rowHeight + spacing
                rows.append(0)
                currentRowWidth = 0
                rowHeight = 0
            }
            currentRowWidth += size.width + (currentRowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
            rows[rows.count - 1] = currentRowWidth
        }
        totalHeight += rowHeight
        return CGSize(width: min(maxWidth, rows.max() ?? 0), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
