import SwiftUI

// Audience-facing "look under the hood" panel, shown for the duration
// of a held green-button ("2") press during a song. Replaces the
// visuals window's normal output entirely with a 1:1 amber-on-black
// console-style readout of show / song / audio / visual telemetry.
//
// Design intent: communicate the technical depth of the rig without a
// single word of explanation. The audience sees fifteen lines of live
// data ticking with the music — bar/beat, chord, instrument hits,
// effect overrides — and reads "this is a real piece of custom
// software" from the gestalt, not any one line.
//
// Live-ness:
//   - Whole panel re-renders every animation frame via TimelineView so
//     bar / beat / chord / hit-dots / effect-remaining all stay in sync
//     with the audio.
//   - One single Text composed from a multi-line String so monospace
//     column alignment is preserved without per-row layout work, and
//     `.minimumScaleFactor` can shrink the whole block uniformly to
//     fit any 1:1 frame size.
struct TelemetryView: View {
    @EnvironmentObject var state: AppState

    // Phosphor / amber-CRT palette. Override the song's theme entirely
    // — this isn't part of the song, it's a system overlay. Amber
    // chosen over the cliché green for vintage-terminal feel.
    private let panelInk = Color(red: 1.0, green: 0.72, blue: 0.0)
    private let panelPaper = Color.black

    // Activity-hold windows. Match VisualsView's synth-layer values so
    // the dots flicker on the same beats the visuals do — visually
    // consistent across the takeover boundary.
    private let kickHold: TimeInterval  = 0.13
    private let snareHold: TimeInterval = 0.10
    private let hhHold: TimeInterval    = 0.06
    private let bassHold: TimeInterval  = 0.20
    private let padHold: TimeInterval   = 0.45

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            GeometryReader { geo in
                // 1:1 square centered in whatever aspect ratio the
                // visuals window happens to be running at. Non-square
                // bezels become panel-paper (black) — reads as the
                // CRT housing, not as letterboxing.
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    panelPaper.ignoresSafeArea()
                    panelText(now: now)
                        .font(.system(size: side * 0.026, weight: .regular, design: .monospaced))
                        .foregroundColor(panelInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.5)
                        .frame(width: side * 0.94, height: side * 0.94, alignment: .center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Panel text

    private func panelText(now: Date) -> Text {
        Text(verbatim: composedPanel(now: now))
    }

    private func composedPanel(now: Date) -> String {
        let header = "═══ TELEMETRY ════════════════════════════"
        let footer = "══════════════════════════════════════════"

        // SET — overall lineup progress.
        let setLine: String = {
            let count = state.lineup.count
            let idx = state.currentLineupIndex
            let pct = count > 0 ? Int(round(Double(idx) / Double(max(1, count - 1)) * 100)) : 0
            return "  SET     \(progressBar(filled: pct, width: 16)) \(pad("\(pct)%", 4)) (\(idx + 1)/\(count))"
        }()

        // SONG / KEY / BPM / STATE — invariants of the current item.
        let song = state.currentSong
        let songLine = "  SONG    \(song?.name.uppercased() ?? "—")"
        let keyBpmLine = "  KEY     \(pad(song?.key ?? "—", 12))BPM    \(song.map { String(Int($0.bpm)) } ?? "—")"
        let stateLine = "  STATE   \(state.isPlaying ? "● PLAYING" : "○ STOPPED")"

        // PROG / PART / BAR / BEAT — moment-to-moment fields. Three
        // progress bars at three different time scales (set / song /
        // bar) plus a 4-dot beat indicator give the audience a strong
        // "I can see the music breathing" read.
        let songPct = songProgressPct()
        let progLine = "  PROG    \(progressBar(filled: songPct, width: 16)) \(pad("\(songPct)%", 4))"

        let partName = state.currentPartName ?? "—"
        let partIdx = state.currentPartIndex + 1
        let partCount = song?.structure.count ?? 0
        let partLine = "  PART    \(partName) (\(partIdx)/\(partCount))"

        let barCount = state.currentPart?.bars ?? 0
        let barPct = barCount > 0
            ? Int(round(Double(state.currentBar + 1) / Double(barCount) * 100))
            : 0
        let barLine = "  BAR     \(progressBar(filled: barPct, width: 16)) \(state.currentBar + 1)/\(max(1, barCount))"
        let beatLine = "  BEAT    \(beatDots(current: state.currentBeat))"

        // CHORD / PATTERN / KIT.
        let chord = state.currentChord.map(chordString) ?? "—"
        let nextChord = state.nextChord.map(chordString) ?? "—"
        let chordLine = "  CHORD   \(chord) → \(nextChord)"

        let pattern = state.currentPart?.pattern ?? "—"
        let kit = song?.kit ?? "—"
        let kitPatternLine = "  PATTERN \(pad(pattern, 14))KIT    \(kit)"

        // INSTRUMENT METERS — each row shows a decay bar (energy
        // level, smoothly fading after each trigger) plus a binary
        // "currently firing" dot. Two views of the same data: the
        // meter for ambient activity, the dot for instant feedback.
        let kickRow = meterRow(label: "KICK", last: state.kickLastTrigger, now: now, decay: 0.8, holdDot: kickHold)
        let snareRow = meterRow(label: "SNARE", last: state.snareLastTrigger, now: now, decay: 0.6, holdDot: snareHold)
        let hhRow = meterRow(label: "HH", last: state.hhLastTrigger, now: now, decay: 0.3, holdDot: hhHold)
        let padLevel = state.currentPart?.padLevel ?? 0
        let bassLevel = state.currentPart?.bassLevel ?? 0
        let padRow = meterRow(label: "PAD", last: state.padLastTrigger, now: now, decay: 1.4, holdDot: padHold, suffix: "L\(padLevel)")
        let bassRow = meterRow(label: "BASS", last: state.bassLastTrigger, now: now, decay: 1.0, holdDot: bassHold, suffix: "L\(bassLevel)")

        // VIZ / THEME / FX.
        let viz = state.effectiveVisualizer.rawValue
        let theme = state.effectiveTheme.rawValue.uppercased()
        let vizLine = "  VIZ     \(pad(viz, 14))THEME  \(theme)"

        let fxLine: String = {
            let fx = state.effectiveVisualEffect.rawValue
            if state.songEffectOverride != nil {
                let remaining = max(0, state.songEffectExpiresAt.timeIntervalSince(now))
                return "  FX      \(fx) (override · \(Int(ceil(remaining)))s)"
            }
            return "  FX      \(fx)"
        }()

        return [
            header,
            "",
            setLine,
            songLine,
            keyBpmLine,
            stateLine,
            "",
            progLine,
            partLine,
            barLine,
            beatLine,
            "",
            chordLine,
            kitPatternLine,
            "",
            kickRow,
            snareRow,
            hhRow,
            padRow,
            bassRow,
            "",
            vizLine,
            fxLine,
            footer,
        ].joined(separator: "\n")
    }

    // MARK: - Helpers

    private func progressBar(filled pct: Int, width: Int) -> String {
        let clamped = max(0, min(100, pct))
        let on = Int(round(Double(width) * Double(clamped) / 100.0))
        let off = max(0, width - on)
        return "[" + String(repeating: "█", count: on)
                   + String(repeating: "░", count: off) + "]"
    }

    private func isFiring(last: Date, now: Date, hold: Double) -> Bool {
        now.timeIntervalSince(last) < hold
    }

    // Build a "label METER fired-dot [suffix]" instrument row. The
    // meter decays linearly from full to empty over `decay` seconds
    // since the last trigger — gives the panel a constant ambient
    // shimmer locked to the music. The fired-dot uses the same short
    // hold window as the synth-layer dots, so it pops binary on the
    // exact frame each instrument fires.
    private func meterRow(
        label: String,
        last: Date,
        now: Date,
        decay: Double,
        holdDot: Double,
        suffix: String = ""
    ) -> String {
        let elapsed = now.timeIntervalSince(last)
        let level = max(0, min(1, 1 - elapsed / decay))
        let width = 22
        let on = Int(round(Double(width) * level))
        let off = max(0, width - on)
        let bar = "[" + String(repeating: "█", count: on)
                      + String(repeating: "░", count: off) + "]"
        let dot = isFiring(last: last, now: now, hold: holdDot) ? "◉" : "◯"
        let suffixPart = suffix.isEmpty ? "" : "  \(suffix)"
        return "  \(pad(label, 8))\(bar) \(dot)\(suffixPart)"
    }

    // Four 1-2-3-4 beat dots; the current beat is filled, the others
    // are empty. Mirrors the HUD's beatDots block on the operator
    // side so the audience and operator see the same downbeat.
    private func beatDots(current: Int) -> String {
        // currentBeat is 0-based (Clock writes beatIndex % 4).
        var parts: [String] = []
        for i in 0..<4 {
            parts.append(i == current ? "●" : "○")
        }
        return parts.joined(separator: "  ")
    }

    // How far into the song we are, as a percentage, by counting
    // bars actually played. Sums the bar-counts of completed parts
    // plus the current bar within the active part, divided by the
    // song's totalBars. Read across loop / pendingPart cleanly: we
    // use the *visited* index, not the structure index.
    private func songProgressPct() -> Int {
        guard let song = state.currentSong else { return 0 }
        let total = song.totalBars
        guard total > 0 else { return 0 }
        var completed = 0
        let endIdx = min(state.currentPartIndex, song.structure.count)
        for i in 0..<endIdx {
            if let p = song.parts[song.structure[i]] {
                completed += p.bars
            }
        }
        completed += state.currentBar
        return Int(round(Double(min(completed, total)) / Double(total) * 100.0))
    }

    // Right-pad a string to width with spaces so adjacent fields line
    // up in monospace columns. Truncates anything overlong rather than
    // letting it push the next column out of alignment.
    private func pad(_ s: String, _ width: Int) -> String {
        if s.count >= width { return String(s.prefix(width)) }
        return s + String(repeating: " ", count: width - s.count)
    }

    // Short chord representation for the CHORD line — uses the chord's
    // existing display string. Falls back to "—" when nil.
    private func chordString(_ chord: Chord) -> String {
        chord.display
    }
}
