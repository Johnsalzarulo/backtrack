import BackTrackCore
import SwiftUI

public struct PerformView: View {
    @ObservedObject private var coordinator: PadCoordinator
    @ObservedObject private var state: AppState

    private let fg = Color.white
    private let dim = Color(white: 0.55)
    private let sidebarWidth: CGFloat = 280
    private let titleLineHeight: CGFloat = 22

    public init(coordinator: PadCoordinator) {
        self.coordinator = coordinator
        self._state = ObservedObject(wrappedValue: coordinator.state)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
            Divider()
            performancePane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.black)
        .ignoresSafeArea(edges: [.leading, .bottom])
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !coordinator.libraryImported {
                sidebarCaption("Import your BackTrack library to begin.")
            } else if coordinator.setlistIsEmpty {
                Text("No songs in this setlist")
                    .font(.headline.monospaced())
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            songTitleBlock

            if let partName = state.currentPartName {
                Text(partName.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            setlistPicker

            transportRow(label: "Song", prev: coordinator.show.previousLineupItem, next: coordinator.show.nextLineupItem)
            transportRow(label: "Part", prev: coordinator.show.previousPart, next: coordinator.show.nextPart)

            Button(state.loopCurrentPart ? "Loop: ON" : "Loop: OFF") {
                coordinator.show.toggleLoop()
            }
            .buttonStyle(.bordered)

            let issues = state.songIssues + state.setlistIssues
            if !issues.isEmpty {
                Text("SONG ISSUES")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.red)
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.08))
    }

    @ViewBuilder
    private var songTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let song = state.currentSong {
                Text(song.name)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(song.key) · \(Int(song.bpm)) BPM")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let item = state.currentLineupItem {
                Text(item.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(" ")
                    .font(.system(size: 17, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, minHeight: titleLineHeight + 18, alignment: .topLeading)
    }

    private func sidebarCaption(_ text: String) -> some View {
        Text(text)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var performancePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.currentSong != nil {
                chordBlock
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                Divider().overlay(dim.opacity(0.3))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let part = state.currentPart, !part.lyrics.isEmpty {
                        Text(part.lyrics)
                            .font(.system(.title, design: .monospaced))
                            .foregroundStyle(fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if state.currentSong != nil {
                        Text("No lyrics for this part")
                            .font(.body.monospaced())
                            .foregroundStyle(dim)
                    } else {
                        Text("Select a song to perform")
                            .font(.body.monospaced())
                            .foregroundStyle(dim)
                    }

                    if let preview = nextPartPreview {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NEXT — \(preview.name.uppercased())")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(dim)
                            if !preview.firstLine.isEmpty {
                                Text(preview.firstLine)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(dim.opacity(0.75))
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    private var chordBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                Text(state.currentChord?.display ?? "—")
                    .font(.system(size: 48, weight: .regular, design: .monospaced))
                    .foregroundStyle(fg)
                if let next = state.nextChord {
                    Text("→ \(next.display)")
                        .foregroundStyle(dim)
                        .font(.system(size: 28, design: .monospaced))
                }
                Spacer(minLength: 0)
                beatDots
            }
            if let part = state.currentPart {
                HStack(spacing: 12) {
                    Text("bar \(state.currentBar + 1) / \(part.bars)")
                    Text(partProgressBar(current: state.currentBar, total: part.bars))
                }
                .foregroundStyle(dim)
                .font(.system(size: 18, design: .monospaced))
            }
        }
    }

    private var beatDots: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(beatDotColor(i))
                        .frame(width: 16, height: 16)
                }
            }
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(dim)
                        .frame(width: 16)
                }
            }
        }
    }

    private func beatDotColor(_ i: Int) -> Color {
        if state.isPlaying && i == state.currentBeat { return fg }
        return dim.opacity(0.4)
    }

    private func partProgressBar(current: Int, total: Int) -> String {
        let filled = max(0, min(total, current + 1))
        let empty = max(0, total - filled)
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

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
        guard nextIdx >= 0, nextIdx < song.structure.count else { return nil }
        let name = song.structure[nextIdx]
        guard let part = song.parts[name] else { return nil }
        let first = part.lyrics.split(separator: "\n").first.map(String.init) ?? ""
        return (name, first)
    }

    private var setlistPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Setlist: \(state.currentSetlist?.name ?? "All songs")")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.tail)
            Button("Cycle setlist") {
                coordinator.show.cycleSetlist()
            }
            .buttonStyle(.bordered)
        }
    }

    private func transportRow(label: String, prev: @escaping () -> Void, next: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(.caption.monospaced())
                .frame(width: 36, alignment: .leading)
            Button("◀") { prev() }
                .buttonStyle(.bordered)
            Button(state.isPlaying ? "Stop" : "Play") {
                coordinator.show.toggleTransport()
            }
            .buttonStyle(.borderedProminent)
            Button("▶") { next() }
                .buttonStyle(.bordered)
        }
    }
}

private extension LineupItem {
    var displayName: String {
        switch self {
        case .song(let s): return s.name
        case .countdown(let c): return c.name
        case .interstitial(let i): return i.name
        case .audienceInteractive(let a): return a.name
        }
    }
}
