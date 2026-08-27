import BackTrackCore
import SwiftUI

struct PerformView: View {
    @ObservedObject var coordinator: PadCoordinator

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: min(320, geo.size.width * 0.32))
                Divider()
                lyricsPane
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !coordinator.libraryImported {
                Text("Import your BackTrack library to begin.")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            } else if coordinator.setlistIsEmpty {
                Text("No songs in this setlist")
                    .font(.headline.monospaced())
                    .foregroundStyle(.orange)
            }

            if let song = coordinator.state.currentSong {
                Text(song.name)
                    .font(.title2.bold().monospaced())
                Text("\(song.key) · \(Int(song.bpm)) BPM")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            } else if let item = coordinator.state.currentLineupItem {
                Text(item.displayName)
                    .font(.title2.monospaced())
            }

            if let partName = coordinator.state.currentPartName {
                Text(partName.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if coordinator.state.currentSong != nil {
                Text("Bar \(coordinator.state.currentBar + 1) · Beat \(coordinator.state.currentBeat + 1)")
                    .font(.caption.monospaced())
                if let chord = coordinator.state.currentChord {
                    Text(chord.display)
                        .font(.largeTitle.bold().monospaced())
                }
            }

            setlistPicker

            transportRow(label: "Song", prev: coordinator.show.previousLineupItem, next: coordinator.show.nextLineupItem)
            transportRow(label: "Part", prev: coordinator.show.previousPart, next: coordinator.show.nextPart)

            Button(coordinator.state.loopCurrentPart ? "Loop: ON" : "Loop: OFF") {
                coordinator.show.toggleLoop()
            }
            .buttonStyle(.bordered)

            let issues = coordinator.state.songIssues + coordinator.state.setlistIssues
            if !issues.isEmpty {
                Text("SONG ISSUES")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.red)
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.08))
    }

    private var lyricsPane: some View {
        ScrollView {
            Text(coordinator.state.currentPart?.lyrics ?? "")
                .font(.system(.title, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(Color.black)
    }

    private var setlistPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Setlist: \(coordinator.state.currentSetlist?.name ?? "All songs")")
                .font(.caption.monospaced())
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
            Button(coordinator.state.isPlaying ? "Stop" : "Play") {
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
