import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private let fg = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let dim = Color(white: 0.45)
    private let activityDecay: TimeInterval = 0.18

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            musicalBlock
            mixBlock
            beatBarRow
            transportLine
            Spacer(minLength: 0)
            missingBlock
            keybindingBlock
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 500, height: 400, alignment: .topLeading)
        .background(Color.black)
        .foregroundColor(fg)
        .font(.system(.body, design: .monospaced))
        .overlay(alignment: .topTrailing) {
            devicesBlock
                .padding(.top, 18)
                .padding(.trailing, 24)
        }
    }

    // MARK: - Musical state

    private var musicalBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                labelText("BPM")
                Text("\(Int(state.tempo.rounded()))")
                    .opacity(state.bpmFlash ? 0.35 : 1.0)
            }
            readout(
                label: "COMPLEXITY",
                value: "\(state.complexity)",
                pending: state.pending.complexity.map(String.init)
            )
            HStack(spacing: 8) {
                labelText("DETECTED")
                Text(state.detectedNote ?? "—")
                    .foregroundColor(state.detectedNote == nil ? dim : fg)
            }
        }
    }

    private var beatBarRow: some View {
        HStack(spacing: 14) {
            labelText("BEAT / BAR")
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(beatColor(i))
                        .frame(width: 12, height: 12)
                }
            }
        }
    }

    // MARK: - Mix

    private var mixBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            instrumentRow(name: "KICK",  level: state.kickLevel,  last: state.kickLastTrigger)
            instrumentRow(name: "SNARE", level: state.snareLevel, last: state.snareLastTrigger)
            instrumentRow(name: "HH",    level: state.hhLevel,    last: state.hhLastTrigger)
            instrumentRow(name: "PAD",   level: state.padLevel,   last: nil)
        }
    }

    // `last` is nil for the live-processed pad (no discrete triggers), in
    // which case we show a static dim dot so the row alignment matches.
    private func instrumentRow(name: String, level: Int, last: Date?) -> some View {
        HStack(spacing: 12) {
            if let last = last {
                activityLight(last: last)
            } else {
                Circle().fill(dim).opacity(0.3).frame(width: 8, height: 8)
            }
            Text(name)
                .foregroundColor(dim)
                .frame(width: 60, alignment: .leading)
            levelMeter(level: level)
        }
    }

    private func levelMeter(level: Int) -> some View {
        HStack(spacing: 0) {
            Text(String(repeating: "█", count: level))
            Text(String(repeating: "·", count: AppState.maxLevel - level))
                .foregroundColor(dim)
        }
    }

    // A small pulse that illuminates on trigger and decays over ~180ms.
    // TimelineView(.animation) ticks every frame, re-evaluating brightness.
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

    // MARK: - Transport

    private var transportLine: some View {
        Text(state.isPlaying ? "● PLAYING" : "○ STOPPED")
            .font(.system(size: 20, weight: .regular, design: .monospaced))
    }

    // MARK: - Missing / devices / keybindings (dim footer)

    @ViewBuilder
    private var missingBlock: some View {
        if !state.missingSamples.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("MISSING SAMPLES")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(dim)
                ForEach(state.missingSamples, id: \.self) { s in
                    Text(s)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(dim)
                }
            }
        }
    }

    private var devicesBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("MIC").frame(width: 44, alignment: .leading)
                Text(state.inputDevice ?? "—")
            }
            HStack(spacing: 8) {
                Text("OUT").frame(width: 44, alignment: .leading)
                Text(state.outputDevice ?? "—")
            }
        }
        .foregroundColor(dim)
        .font(.system(.caption, design: .monospaced))
    }

    private var keybindingBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("SPACE", "start / stop",    "1 2 3", "complexity")
            row("T",     "tap tempo",       "R",     "reload samples")
            row("↑ ↓",   "tempo ± 1",       "",      "")
            row("K S H P", "instrument volume", "", "")
        }
        .foregroundColor(dim)
        .font(.system(.caption, design: .monospaced))
    }

    private func row(_ k1: String, _ d1: String, _ k2: String, _ d2: String) -> some View {
        HStack(spacing: 0) {
            Text(k1).frame(width: 72, alignment: .leading)
            Text(d1).frame(width: 150, alignment: .leading)
            Text(k2).frame(width: 56, alignment: .leading)
            Text(d2)
        }
    }

    // MARK: - Shared helpers

    private func readout(label: String, value: String, pending: String?) -> some View {
        HStack(spacing: 8) {
            labelText(label)
            Text(value)
            if let p = pending {
                Text("→ \(p)").foregroundColor(dim)
            }
        }
    }

    private func labelText(_ s: String) -> some View {
        Text(s)
            .foregroundColor(dim)
            .frame(width: 92, alignment: .leading)
    }

    private func beatColor(_ i: Int) -> Color {
        if state.isPlaying && i == state.currentBeat {
            return fg
        }
        return dim.opacity(0.45)
    }
}
