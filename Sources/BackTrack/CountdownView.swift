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
                let h = geo.size.height
                let w = geo.size.width
                let pad = min(w, h) * 0.06

                VStack(alignment: .center, spacing: h * 0.025) {
                    Spacer(minLength: 0)
                    // Label — stays small, sits above the timer like
                    // a marquee header.
                    Text(countdown.label.uppercased())
                        .font(.system(size: h * 0.07, weight: .light, design: .monospaced))
                        .foregroundColor(ink.opacity(0.7))
                        .multilineTextAlignment(.center)

                    // The big counter — sized to the frame so it
                    // dominates the screen at any window size.
                    Text(formatTime(remaining))
                        .font(.system(size: h * 0.32, weight: .light, design: .monospaced))
                        .foregroundColor(ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    // Progress bar — thin wobbly outline to match the
                    // synth layer's hand-drawn feel.
                    progressBar(progress: progress, width: w - pad * 2, height: max(6, h * 0.018))

                    Spacer(minLength: 0)

                    // Rotating message — empty if the countdown has
                    // no `messages` configured. Stays at one line so
                    // the layout above doesn't shift when text changes.
                    Text(message)
                        .font(.system(size: h * 0.06, weight: .light, design: .monospaced))
                        .foregroundColor(ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: w - pad * 2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(.bottom, h * 0.08)
                }
                .frame(width: w, height: h)
                .padding(.horizontal, pad)
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
