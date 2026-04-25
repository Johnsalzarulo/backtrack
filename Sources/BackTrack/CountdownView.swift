import SwiftUI

// Full-screen countdown display. Three styles share the same chrome
// — a centered label up top, a rotating one-liner down the bottom —
// and just differ in how the timer itself renders:
//
//   .digital   → giant M:SS:cc digits + thin progress bar
//   .pie       → clock-face pie shrinking clockwise from 12 o'clock
//   .hourglass → sand draining from a top triangle into a bottom one
//
// Every dimension scales off `min(w, h)` and every text element has a
// `frame(maxWidth:)` cap so the layout reads the same on landscape,
// portrait, square, and ultrawide displays.
//
// Drives off TimelineView(.animation) so the timer + visuals + message
// rotate every frame against the current `CountdownTransport` and wall
// clock — no separate ticker state to keep in sync.
struct CountdownView: View {
    let countdown: Countdown
    let transport: CountdownTransport
    // Render style — usually `countdown.style` from JSON, but the
    // visuals window resolves it through AppState.effectiveCountdownStyle
    // so an `M`-key override can take precedence at runtime.
    let style: CountdownStyle
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
                let safe = min(w, h)
                let pad = safe * 0.06
                let availW = w - pad * 2
                let labelFont = safe * 0.06
                let messageFont = safe * 0.05

                VStack(alignment: .center, spacing: safe * 0.03) {
                    Spacer(minLength: 0)
                    headerLabel(font: labelFont, availW: availW)
                    Spacer(minLength: 0)

                    timerBlock(
                        progress: progress,
                        remaining: remaining,
                        w: w,
                        h: h,
                        safe: safe,
                        availW: availW
                    )

                    Spacer(minLength: 0)
                    if !message.isEmpty {
                        messageLine(message: message, font: messageFont, availW: availW)
                            .padding(.bottom, safe * 0.06)
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .background(paper)
    }

    // MARK: - Shared chrome

    private func headerLabel(font: CGFloat, availW: CGFloat) -> some View {
        Text(countdown.label.uppercased())
            .font(.system(size: font, weight: .light, design: .monospaced))
            .foregroundColor(ink.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(maxWidth: availW)
    }

    private func messageLine(message: String, font: CGFloat, availW: CGFloat) -> some View {
        Text(message)
            .font(.system(size: font, weight: .light, design: .monospaced))
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: availW)
    }

    // MARK: - Style switch

    @ViewBuilder
    private func timerBlock(
        progress: Double,
        remaining: TimeInterval,
        w: CGFloat,
        h: CGFloat,
        safe: CGFloat,
        availW: CGFloat
    ) -> some View {
        switch style {
        case .digital:
            digitalContent(progress: progress, remaining: remaining, safe: safe, availW: availW)
        case .pie:
            pieContent(progress: progress, remaining: remaining, safe: safe, availW: availW)
        case .hourglass:
            hourglassContent(progress: progress, remaining: remaining, safe: safe, availW: availW)
        }
    }

    // MARK: - Digital style

    // Big M:SS:cc digits with a thin progress bar underneath. The
    // numbers are the dominant element; the bar adds a glanceable
    // "how far through am I" cue that pure digits don't give you.
    private func digitalContent(
        progress: Double,
        remaining: TimeInterval,
        safe: CGFloat,
        availW: CGFloat
    ) -> some View {
        let timerFont = safe * 0.20
        let barHeight = max(4, safe * 0.012)

        return VStack(alignment: .center, spacing: safe * 0.03) {
            Text(formatTimeDetailed(remaining))
                .font(.system(size: timerFont, weight: .light, design: .monospaced))
                .foregroundColor(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: availW)

            progressBar(progress: progress, width: availW * 0.9, height: barHeight)
        }
    }

    // MARK: - Pie style

    // Clock-face pie. Filled wedge represents *remaining* time and
    // shrinks clockwise from 12 o'clock as the countdown runs — the
    // same direction as the analog clock the audience already
    // understands. Smaller M:SS digits sit underneath.
    private func pieContent(
        progress: Double,
        remaining: TimeInterval,
        safe: CGFloat,
        availW: CGFloat
    ) -> some View {
        let pieSize = min(availW * 0.85, safe * 0.55)
        let smallFont = safe * 0.10

        return VStack(alignment: .center, spacing: safe * 0.04) {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 2
                let lineWidth = max(1.5, safe * 0.005)

                // Outer outline — full circle behind the wedge so the
                // empty area still reads as "the whole pie".
                let circle = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                ctx.stroke(circle, with: .color(ink), lineWidth: lineWidth)

                // Filled wedge = remaining fraction. SwiftUI's
                // addArc(clockwise: false) draws clockwise on screen
                // (y-down coords), so sweeping from -90° (12 o'clock)
                // to -90° + 360°·remaining traces the time left.
                let remainingFraction = max(0, 1 - progress)
                if remainingFraction > 0.0001 {
                    let wedge = Path { p in
                        p.move(to: center)
                        p.addArc(
                            center: center,
                            radius: radius - lineWidth / 2,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * remainingFraction),
                            clockwise: false
                        )
                        p.closeSubpath()
                    }
                    ctx.fill(wedge, with: .color(ink))
                }
            }
            .frame(width: pieSize, height: pieSize)

            Text(formatTimeShort(remaining))
                .font(.system(size: smallFont, weight: .light, design: .monospaced))
                .foregroundColor(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: availW)
        }
    }

    // MARK: - Hourglass style

    // Two stacked triangles — top point-down, bottom point-up — with
    // sand draining from one to the other. Top sand level falls as
    // time elapses; bottom rises to mirror it. Smaller M:SS digits
    // beneath. Reads as classic sand-clock without any chrome.
    private func hourglassContent(
        progress: Double,
        remaining: TimeInterval,
        safe: CGFloat,
        availW: CGFloat
    ) -> some View {
        let glassH = min(safe * 0.62, availW * 1.0)
        let glassW = min(availW * 0.5, glassH * 0.7)
        let smallFont = safe * 0.10

        return VStack(alignment: .center, spacing: safe * 0.04) {
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let halfW = size.width / 2
                let halfH = size.height / 2
                let lineWidth = max(1.5, safe * 0.005)

                // Top triangle: wide base on top, apex at the waist.
                let topTri = Path { p in
                    p.move(to: CGPoint(x: cx - halfW, y: cy - halfH))
                    p.addLine(to: CGPoint(x: cx + halfW, y: cy - halfH))
                    p.addLine(to: CGPoint(x: cx, y: cy))
                    p.closeSubpath()
                }
                // Bottom triangle: apex at the waist, wide base on bottom.
                let bottomTri = Path { p in
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx - halfW, y: cy + halfH))
                    p.addLine(to: CGPoint(x: cx + halfW, y: cy + halfH))
                    p.closeSubpath()
                }

                // Sand levels. As `progress` rises, the top sand line
                // moves down toward the apex (cy) and the bottom sand
                // line rises away from the bottom edge toward cy.
                let topSandY = cy - (1 - CGFloat(progress)) * halfH
                let bottomSandY = cy + (1 - CGFloat(progress)) * halfH

                // Fill the top sand: clip to the triangle, fill a rect
                // from the sand line down to the waist. The clip turns
                // the rect into the trapezoid (or triangle) that
                // actually fits inside the triangle outline.
                if topSandY < cy {
                    var topCtx = ctx
                    topCtx.clip(to: topTri)
                    topCtx.fill(
                        Path(CGRect(
                            x: cx - halfW,
                            y: topSandY,
                            width: halfW * 2,
                            height: cy - topSandY
                        )),
                        with: .color(ink)
                    )
                }

                // Bottom sand: clip + fill from sand line down to base.
                if bottomSandY < cy + halfH {
                    var bottomCtx = ctx
                    bottomCtx.clip(to: bottomTri)
                    bottomCtx.fill(
                        Path(CGRect(
                            x: cx - halfW,
                            y: bottomSandY,
                            width: halfW * 2,
                            height: (cy + halfH) - bottomSandY
                        )),
                        with: .color(ink)
                    )
                }

                // Outlines on top so the silhouette stays crisp where
                // sand meets the edge.
                ctx.stroke(topTri, with: .color(ink), lineWidth: lineWidth)
                ctx.stroke(bottomTri, with: .color(ink), lineWidth: lineWidth)
            }
            .frame(width: glassW, height: glassH)

            Text(formatTimeShort(remaining))
                .font(.system(size: smallFont, weight: .light, design: .monospaced))
                .foregroundColor(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: availW)
        }
    }

    // MARK: - Helpers

    // M:SS:cc — minutes, seconds, hundredths. Used by the digital
    // style where the digits are huge enough that hundredths flicker
    // reads as "live & precise" rather than distracting noise.
    private func formatTimeDetailed(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let m = Int(total) / 60
        let s = Int(total) % 60
        let cs = Int((total - floor(total)) * 100) % 100
        return String(format: "%d:%02d:%02d", m, s, cs)
    }

    // M:SS — used by pie/hourglass where the visual element handles
    // sub-second precision and small flickering centiseconds would
    // just be hard to read at the smaller font.
    private func formatTimeShort(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let m = Int(total) / 60
        let s = Int(total) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func currentMessage(elapsed: TimeInterval) -> String {
        guard !countdown.messages.isEmpty else { return "" }
        let interval = max(0.1, countdown.messageInterval)
        let idx = Int(floor(elapsed / interval)) % countdown.messages.count
        return countdown.messages[idx]
    }

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
