import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private let fg = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let dim = Color(white: 0.45)
    private let accent = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let activityDecay: TimeInterval = 0.18

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBlock
            structureBlock
            divider
            chordLyricsBlock
            divider
            mixBlock
            Spacer(minLength: 0)
            transportLine
            issuesBlock
            keybindingBlock
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 700, height: 500, alignment: .topLeading)
        .background(Color.black)
        .foregroundColor(fg)
        .font(.system(.body, design: .monospaced))
        .overlay(alignment: .topTrailing) {
            outDeviceBlock
                .padding(.top, 18)
                .padding(.trailing, 24)
        }
    }

    // MARK: - Header (song / key / bpm)

    private var headerBlock: some View {
        HStack(spacing: 28) {
            HStack(spacing: 8) {
                Text("SONG").foregroundColor(dim)
                Text(state.currentSong?.name ?? "—")
            }
            if let key = state.currentSong?.key, !key.isEmpty {
                HStack(spacing: 8) {
                    Text("KEY").foregroundColor(dim)
                    Text(key)
                }
            }
            HStack(spacing: 8) {
                Text("BPM").foregroundColor(dim)
                Text("\(Int(state.tempo.rounded()))")
                    .opacity(state.bpmFlash ? 0.35 : 1.0)
            }
        }
    }

    // MARK: - Structure

    private var structureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STRUCTURE").foregroundColor(dim).font(.system(.caption, design: .monospaced))
            if let song = state.currentSong {
                HStack(spacing: 10) {
                    ForEach(Array(song.structure.enumerated()), id: \.offset) { idx, name in
                        partBadge(name: name, isActive: idx == state.currentPartIndex, isQueued: idx == state.pendingPartIndex)
                    }
                }
                if let part = state.currentPart {
                    Text("bar \(state.currentBar + 1) / \(part.bars)")
                        .foregroundColor(dim)
                        .font(.system(.caption, design: .monospaced))
                }
            } else {
                Text("no songs loaded").foregroundColor(dim)
            }
        }
    }

    private func partBadge(name: String, isActive: Bool, isQueued: Bool) -> some View {
        Text(isActive ? "▸\(name.uppercased())◂" : name)
            .foregroundColor(isActive ? fg : (isQueued ? accent.opacity(0.8) : dim))
    }

    private var divider: some View {
        Rectangle()
            .fill(dim.opacity(0.3))
            .frame(height: 1)
    }

    // MARK: - Chord + lyrics

    private var chordLyricsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            chordLine
            lyricsBlock
        }
    }

    private var chordLine: some View {
        HStack(spacing: 16) {
            Text(state.currentChord?.display ?? "—")
                .font(.system(size: 32, weight: .regular, design: .monospaced))
            if let next = state.nextChord {
                Text("→ \(next.display)")
                    .foregroundColor(dim)
                    .font(.system(size: 18, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var lyricsBlock: some View {
        if let part = state.currentPart, !part.lyrics.isEmpty {
            Text(part.lyrics)
                .font(.system(size: 15, design: .monospaced))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(" ")
                .font(.system(size: 15, design: .monospaced))
        }
    }

    // MARK: - Mix (compact)

    private var mixBlock: some View {
        HStack(spacing: 20) {
            instrumentChip(name: "KICK", level: state.kickLevel, last: state.kickLastTrigger)
            instrumentChip(name: "SNARE", level: state.snareLevel, last: state.snareLastTrigger)
            instrumentChip(name: "HH", level: state.hhLevel, last: state.hhLastTrigger)
            instrumentChip(
                name: "PAD",
                level: state.padVolume,
                last: state.padLastTrigger,
                subtitle: padSubtitle
            )
            instrumentChip(
                name: "BASS",
                level: state.bassVolume,
                last: state.bassLastTrigger,
                subtitle: bassSubtitle
            )
        }
    }

    private var padSubtitle: String? {
        guard let song = state.currentSong, let sound = song.padSound else { return nil }
        return sound
    }

    private var bassSubtitle: String? {
        guard let song = state.currentSong, let sound = song.bassSound else { return nil }
        return sound
    }

    private func instrumentChip(
        name: String,
        level: Int,
        last: Date,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            activityLight(last: last)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).foregroundColor(dim).font(.system(.caption, design: .monospaced))
                levelMeter(level: level)
                    .font(.system(.caption, design: .monospaced))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .foregroundColor(dim.opacity(0.8))
                        .font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }

    private func levelMeter(level: Int) -> some View {
        HStack(spacing: 0) {
            Text(String(repeating: "█", count: level))
            Text(String(repeating: "·", count: AppState.maxLevel - level))
                .foregroundColor(dim)
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

    // MARK: - Transport + footer

    private var transportLine: some View {
        Text(state.isPlaying ? "● PLAYING" : "○ STOPPED")
            .font(.system(size: 18, design: .monospaced))
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
        return all
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

    private var keybindingBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("SPACE", "start / stop",        "← →",   "prev / next song")
            row("↑ ↓",   "next / prev part",    "T",     "tap tempo")
            row("K S H", "drum volume",         "P B",   "pad / bass volume")
            row("R",     "reload songs & samples", "",   "")
        }
        .foregroundColor(dim)
        .font(.system(.caption, design: .monospaced))
    }

    private func row(_ k1: String, _ d1: String, _ k2: String, _ d2: String) -> some View {
        HStack(spacing: 0) {
            Text(k1).frame(width: 80, alignment: .leading)
            Text(d1).frame(width: 200, alignment: .leading)
            Text(k2).frame(width: 56, alignment: .leading)
            Text(d2)
        }
    }
}
