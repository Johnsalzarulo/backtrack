import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private let fg = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let dim = Color(white: 0.45)
    private let accent = Color(red: 0.82, green: 0.92, blue: 0.82)
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
        .frame(width: 1000, height: 560, alignment: .topLeading)
        .background(Color.black)
        .foregroundColor(fg)
        .font(.system(.body, design: .monospaced))
    }

    // MARK: - Left column (fixed layout)

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            structureBlock
            divider
            chordLine
            mixBlock
            Spacer(minLength: 0)
            transportLine
            issuesBlock
            keybindingBlock
        }
    }

    private var structureBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STRUCTURE").foregroundColor(dim).font(.system(.caption, design: .monospaced))
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
                if let part = state.currentPart {
                    HStack(spacing: 10) {
                        Text("bar \(state.currentBar + 1) / \(part.bars)")
                        Text(partProgressBar(current: state.currentBar, total: part.bars))
                    }
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

    private var chordLine: some View {
        HStack(spacing: 16) {
            Text(state.currentChord?.display ?? "—")
                .font(.system(size: 40, weight: .regular, design: .monospaced))
            if let next = state.nextChord {
                Text("→ \(next.display)")
                    .foregroundColor(dim)
                    .font(.system(size: 22, design: .monospaced))
            }
            Spacer(minLength: 0)
            beatDots
        }
    }

    // 1 / 2 / 3 / 4 beat counter next to the chord display so you can see
    // where the downbeat is and come in on the one. Leftmost dot is
    // beat 1; lit dot tracks the current beat.
    private var beatDots: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(beatDotColor(i))
                        .frame(width: 14, height: 14)
                }
            }
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(dim)
                        .frame(width: 14)
                }
            }
        }
    }

    private func beatDotColor(_ i: Int) -> Color {
        if state.isPlaying && i == state.currentBeat { return fg }
        return dim.opacity(0.4)
    }

    // Mix split into two rows — drums on top, harmonic on bottom — so the
    // left column doesn't have to be wide enough to fit five chips in a line.
    private var mixBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                instrumentChip(name: "KICK", level: state.kickLevel, last: state.kickLastTrigger)
                instrumentChip(name: "SNARE", level: state.snareLevel, last: state.snareLastTrigger)
                instrumentChip(name: "HH", level: state.hhLevel, last: state.hhLastTrigger)
            }
            HStack(spacing: 24) {
                instrumentChip(name: "PAD", level: state.padVolume, last: state.padLastTrigger, subtitle: padSubtitle)
                instrumentChip(name: "BASS", level: state.bassVolume, last: state.bassLastTrigger, subtitle: bassSubtitle)
            }
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
                levelMeter(level: level).font(.system(.caption, design: .monospaced))
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
            Text(d1).frame(width: 180, alignment: .leading)
            Text(k2).frame(width: 56, alignment: .leading)
            Text(d2)
        }
    }

    // MARK: - Right column (song header + lyrics)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            songHeaderBlock
            divider
            lyricsBlock
            Spacer(minLength: 0)
            outDeviceBlock
        }
    }

    private var songHeaderBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("SONG").foregroundColor(dim).frame(width: 44, alignment: .leading)
                Text(state.currentSong?.name ?? "—")
            }
            if let key = state.currentSong?.key, !key.isEmpty {
                HStack(spacing: 10) {
                    Text("KEY").foregroundColor(dim).frame(width: 44, alignment: .leading)
                    Text(key)
                }
            }
            HStack(spacing: 10) {
                Text("BPM").foregroundColor(dim).frame(width: 44, alignment: .leading)
                Text("\(Int(state.tempo.rounded()))")
                    .opacity(state.bpmFlash ? 0.35 : 1.0)
            }
        }
    }

    @ViewBuilder
    private var lyricsBlock: some View {
        if let part = state.currentPart, !part.lyrics.isEmpty {
            Text(part.lyrics)
                .font(.system(size: 16, design: .monospaced))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(" ")
                .font(.system(size: 16, design: .monospaced))
        }
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
