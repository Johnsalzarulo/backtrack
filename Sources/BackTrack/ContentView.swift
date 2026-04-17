import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private let fg = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let dim = Color(white: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusBlock
            transportLine
            Spacer(minLength: 0)
            missingBlock
            keybindingBlock
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 500, height: 400, alignment: .topLeading)
        .background(Color.black)
        .foregroundColor(fg)
        .font(.system(.body, design: .monospaced))
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout(label: "KEY", value: state.keyString, pending: state.pendingKeyString)
            HStack(spacing: 8) {
                labelText("BPM")
                Text("\(Int(state.tempo.rounded()))")
                    .opacity(state.bpmFlash ? 0.35 : 1.0)
            }
            readout(
                label: "LVL",
                value: "\(state.complexity)",
                pending: state.pending.complexity.map(String.init)
            )
            HStack(spacing: 10) {
                labelText(" ")
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(beatColor(i))
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.top, 2)

            HStack(spacing: 14) {
                labelText("MIX")
                meter("K", level: state.kickLevel)
                meter("S", level: state.snareLevel)
                meter("H", level: state.hhLevel)
                meter("P", level: state.padLevel)
            }
            .padding(.top, 2)
        }
    }

    private func meter(_ label: String, level: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundColor(dim)
            HStack(spacing: 0) {
                Text(String(repeating: "█", count: level))
                Text(String(repeating: "·", count: AppState.maxLevel - level))
                    .foregroundColor(dim)
            }
        }
    }

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
            .frame(width: 44, alignment: .leading)
    }

    private func beatColor(_ i: Int) -> Color {
        if state.isPlaying && i == state.currentBeat {
            return fg
        }
        return dim.opacity(0.45)
    }

    private var transportLine: some View {
        Text(state.isPlaying ? "● PLAYING" : "○ STOPPED")
            .font(.system(size: 22, weight: .regular, design: .monospaced))
    }

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

    private var keybindingBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("SPACE", "start / stop", "A–G", "root note")
            row("T", "tap tempo", "M", "major / minor")
            row("↑ ↓", "tempo ± 1", "1 2 3", "complexity")
            row("R", "reload samples", "", "")
            row("K S H P", "mix (kick snare hh pad)", "", "")
        }
        .foregroundColor(dim)
        .font(.system(.caption, design: .monospaced))
    }

    private func row(_ k1: String, _ d1: String, _ k2: String, _ d2: String) -> some View {
        HStack(spacing: 0) {
            Text(k1).frame(width: 68, alignment: .leading)
            Text(d1).frame(width: 150, alignment: .leading)
            Text(k2).frame(width: 68, alignment: .leading)
            Text(d2)
        }
    }
}
