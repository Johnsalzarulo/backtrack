import SwiftUI

// Full-screen countdown display: label, big timer, progress bar,
// rotating message line. Mirrors the secondary visuals window's
// "linocut" aesthetic — ink on paper, monospaced, no chrome — so
// pre-show countdowns feel like the same show as the songs.
//
// Drives off TimelineView(.animation) so the timer + message rotate
// every display frame against the current `CountdownTransport` and
// wall clock — no separate ticker/timer state to keep in sync.
struct CountdownView: View {
    let countdown: Countdown
    let transport: CountdownTransport
    // Theme colors come from the visuals window so the countdown
    // honors the same dark/light setting as the surrounding app.
    let ink: Color
    let paper: Color

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let elapsed = min(countdown.duration, transport.elapsed(at: now))
            let remaining = max(0, countdown.duration - elapsed)
            let progress = countdown.duration > 0
                ? min(1.0, elapsed / countdown.duration)
                : 0
            let message = currentMessage(elapsed: elapsed)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                // All sizing comes off the *smaller* dimension so the
                // layout reads the same on landscape, portrait, square,
                // ultrawide — anything. Using `h` alone (as the original
                // pass did) blew out the timer and label past the width
                // whenever the window was taller than it was wide.
                let safe = min(w, h)
                let pad = safe * 0.06
                let availW = w - pad * 2
                let labelFont = safe * 0.06
                let timerFont = safe * 0.20
                let messageFont = safe * 0.05
                let barHeight = max(4, safe * 0.012)

                VStack(alignment: .center, spacing: safe * 0.03) {
                    Spacer(minLength: 0)

                    // Header above the timer. `.minimumScaleFactor` is
                    // intentionally aggressive (0.3) so weirdly narrow
                    // windows shrink the text instead of clipping it.
                    Text(countdown.label.uppercased())
                        .font(.system(size: labelFont, weight: .light, design: .monospaced))
                        .foregroundColor(ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: availW)

                    // The big counter — fills the frame at any size,
                    // capped to availW so SwiftUI's auto-shrink can
                    // actually engage when the chosen font would
                    // otherwise overflow horizontally.
                    Text(formatTime(remaining))
                        .font(.system(size: timerFont, weight: .light, design: .monospaced))
                        .foregroundColor(ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: availW)

                    progressBar(
                        progress: progress,
                        width: availW * 0.9,
                        height: barHeight
                    )

                    Spacer(minLength: 0)

                    // Rotating message. Empty when no messages are
                    // configured; otherwise wraps to up to 3 lines so
                    // a long sentence can breathe instead of clipping.
                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: messageFont, weight: .light, design: .monospaced))
                            .foregroundColor(ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: availW)
                            .padding(.bottom, safe * 0.06)
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .background(paper)
    }

    // M:SS:cc — minutes, seconds, hundredths. Matches the spec the
    // user wrote ("9:59:12") so the timer reads as a stopwatch rather
    // than a boring digital clock.
    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let m = Int(total) / 60
        let s = Int(total) % 60
        let cs = Int((total - floor(total)) * 100) % 100
        return String(format: "%d:%02d:%02d", m, s, cs)
    }

    // Rotating message lookup. Index advances by 1 every
    // `messageInterval` seconds of countdown elapsed. When stopped,
    // sticks at message[0] so the user sees a representative line.
    private func currentMessage(elapsed: TimeInterval) -> String {
        guard !countdown.messages.isEmpty else { return "" }
        let interval = max(0.1, countdown.messageInterval)
        let idx = Int(floor(elapsed / interval)) % countdown.messages.count
        return countdown.messages[idx]
    }

    // Linear progress bar: outlined track, filled portion shows
    // elapsed time. Sized to whatever the layout above gives us.
    private func progressBar(progress: Double, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .stroke(ink.opacity(0.5), lineWidth: 1)
                .frame(width: width, height: height)
            Rectangle()
                .fill(ink)
                .frame(width: max(0, width * CGFloat(progress)), height: height)
        }
        .frame(width: width, height: height)
    }
}
