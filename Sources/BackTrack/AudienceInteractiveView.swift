import SwiftUI

// Full-screen audience-driven screen. Aesthetic mirrors CountdownView:
// monospace, theme-aware, overscan-safe, centered. Only the message
// in the middle differs by kind.
//
// Currently a single rendering for all kinds — start_button shows
// "PRESS 🟢 TO START THE SHOW" with a momentary "WRONG BUTTON" pop
// when the red button is pressed. Future kinds (votes, branching,
// reactions, etc.) can extend the switch in `prompt` without changing
// the chrome.
struct AudienceInteractiveView: View {
    let interactive: AudienceInteractive
    // Wall-clock timestamp of the last "wrong button" press. Layered
    // on top of the per-kind prompt — for ~1.5 s after each press the
    // view reads "WRONG BUTTON" in the error tint instead. .distantPast
    // means no error currently displayed.
    let wrongButtonAt: Date
    let ink: Color
    let paper: Color

    // Same overscan inset CountdownView uses, for the same reason —
    // CRTs and projectors clip 5–10% off each edge.
    private let overscanMargin: CGFloat = 0.07
    // Window during which "WRONG BUTTON" replaces the per-kind prompt.
    private let errorHoldSeconds: TimeInterval = 1.5

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let inError = now.timeIntervalSince(wrongButtonAt) < errorHoldSeconds
            GeometryReader { geo in
                let inset = min(geo.size.width, geo.size.height) * overscanMargin
                let safeW = max(0, geo.size.width - inset * 2)
                let safeH = max(0, geo.size.height - inset * 2)
                let safe = min(safeW, safeH)
                let messageFont = safe * 0.13

                ZStack {
                    paper.ignoresSafeArea()
                    VStack {
                        Spacer(minLength: 0)
                        if inError {
                            Text("WRONG BUTTON")
                                .foregroundColor(errorTint)
                                .font(.system(size: messageFont, weight: .light, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .frame(maxWidth: safeW)
                        } else {
                            promptContent(font: messageFont)
                                .foregroundColor(ink)
                                .frame(maxWidth: safeW)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: safeW, height: safeH)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // Per-kind prompt content. Returns a fully composed view (rather
    // than a String) so we can mix typed colored dots into the
    // sentence — using emojis here renders inconsistently and the
    // user wanted plain colored circles. Each kind is responsible
    // for its own button-color semantics; future kinds add a case.
    @ViewBuilder
    private func promptContent(font: CGFloat) -> some View {
        switch interactive.kind {
        case .startButton:
            // "PRESS [green dot] TO\nSTART THE SHOW", with the dot
            // tinted green inside the same monospace block. Two-line
            // layout uses a VStack so the line break lands cleanly.
            VStack(spacing: font * 0.05) {
                let line1 = Text("PRESS ")
                    + Text("⬤").foregroundColor(.green)
                    + Text(" TO")
                line1
                    .font(.system(size: font, weight: .light, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text("START THE SHOW")
                    .font(.system(size: font, weight: .light, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
        }
    }

    // Error tint. Using a saturated red regardless of theme since
    // "WRONG" reads universally in red, and the panel itself is short
    // enough that the red doesn't fight any other on-screen content.
    private var errorTint: Color {
        Color(red: 1.0, green: 0.25, blue: 0.25)
    }
}
