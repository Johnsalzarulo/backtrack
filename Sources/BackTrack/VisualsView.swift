import SwiftUI

// Secondary window showing console-style geometric visuals that react to
// drum/pad/bass triggers. Runs on SwiftUI's Canvas + TimelineView, so it
// re-renders every display frame and reads the same trigger timestamps
// the HUD already uses. Aspect-agnostic — every dimension is derived
// from min(width, height).
//
// When the current part has a visual (still image, GIF, or video), that
// takes over the whole window and the synth layer is hidden — stacking
// both was too busy. The synth layer only shows for parts with no visual.
//
// Synth layer order (back to front):
//   1. Idle border        — always on, for projector / screen alignment
//   2. Pad sun-rays       — always rotating, brightness tracks pad activity
//   3. Kick outer flash   — thick border pulse
//   4. Bass ring          — ~40% radius pulse
//   5. HH ring            — ~13% radius pulse
//   6. Snare dot          — center pulse
struct VisualsView: View {
    @EnvironmentObject var state: AppState

    private let fg = Color(red: 0.82, green: 0.92, blue: 0.82)
    private let rayCount = 12
    private let rotationPeriod: Double = 8.0

    // Decay durations per voice. Chosen to feel like each hit has an
    // echo rather than snapping off.
    private let kickDecay: TimeInterval = 0.30
    private let snareDecay: TimeInterval = 0.22
    private let hhDecay: TimeInterval = 0.14
    private let bassDecay: TimeInterval = 0.28
    private let padDecay: TimeInterval = 0.45

    var body: some View {
        ZStack {
            if let url = state.currentPartVisualURL {
                // Part has a visual: take over the window, suppress synth.
                VisualView(url: url)
                    .ignoresSafeArea()
            } else {
                // No visual: fall back to the console-style synth layer.
                TimelineView(.animation) { context in
                    Canvas { ctx, size in
                        render(ctx: ctx, size: size, now: context.date)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onDisappear {
            // Window was closed (either via X or programmatic dismiss).
            // Reflect in state so the next V press re-opens cleanly.
            state.visualsOpen = false
        }
    }

    // MARK: - Render

    private func render(ctx: GraphicsContext, size: CGSize, now: Date) {
        let minDim = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        drawIdleBorder(ctx: ctx, size: size, minDim: minDim)
        drawPadRays(ctx: ctx, center: center, minDim: minDim, now: now)
        drawKickFlash(ctx: ctx, size: size, minDim: minDim, now: now)
        drawBassRing(ctx: ctx, center: center, minDim: minDim, now: now)
        drawHhRing(ctx: ctx, center: center, minDim: minDim, now: now)
        drawSnareDot(ctx: ctx, center: center, minDim: minDim, now: now)
    }

    private func brightness(last: Date, now: Date, decay: TimeInterval) -> Double {
        let elapsed = now.timeIntervalSince(last)
        return max(0, 1 - elapsed / decay)
    }

    // MARK: - Layers

    // A thin rectangle at the edge. Faint but always on so you can line
    // the output up to a projector / screen even when nothing's playing.
    private func drawIdleBorder(ctx: GraphicsContext, size: CGSize, minDim: CGFloat) {
        let inset = minDim * 0.005
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        ctx.stroke(
            Path(rect),
            with: .color(fg.opacity(0.18)),
            lineWidth: 1
        )
    }

    // Spinning ray segments in a donut band around the center. Only
    // visible when the pad has fired recently — idle shows just the
    // border. Each ray starts at an inner radius (past the HH ring)
    // and extends outward into the bass-ring zone.
    private func drawPadRays(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, now: Date) {
        let padB = brightness(last: state.padLastTrigger, now: now, decay: padDecay)
        guard padB > 0 else { return }

        let innerRadius = minDim * 0.22
        let outerRadius = minDim * 0.48
        let thickness = minDim * 0.004
        let rotation = now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: rotationPeriod) / rotationPeriod * 2 * .pi

        for i in 0..<rayCount {
            let angle = rotation + Double(i) * 2 * .pi / Double(rayCount)
            let cosA = CGFloat(cos(angle))
            let sinA = CGFloat(sin(angle))
            let start = CGPoint(x: center.x + cosA * innerRadius, y: center.y + sinA * innerRadius)
            let end = CGPoint(x: center.x + cosA * outerRadius, y: center.y + sinA * outerRadius)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            ctx.stroke(path, with: .color(fg.opacity(padB)), lineWidth: thickness)
        }
    }

    // Thick rectangular border, pulses on every kick hit.
    private func drawKickFlash(ctx: GraphicsContext, size: CGSize, minDim: CGFloat, now: Date) {
        let b = brightness(last: state.kickLastTrigger, now: now, decay: kickDecay)
        guard b > 0 else { return }
        let lineWidth = minDim * 0.045
        let inset = lineWidth / 2
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        ctx.stroke(
            Path(rect),
            with: .color(fg.opacity(b)),
            lineWidth: lineWidth
        )
    }

    private func drawBassRing(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, now: Date) {
        let b = brightness(last: state.bassLastTrigger, now: now, decay: bassDecay)
        guard b > 0 else { return }
        strokeCircle(
            ctx: ctx,
            center: center,
            radius: minDim * 0.40,
            lineWidth: minDim * 0.010,
            opacity: b
        )
    }

    private func drawHhRing(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, now: Date) {
        let b = brightness(last: state.hhLastTrigger, now: now, decay: hhDecay)
        guard b > 0 else { return }
        strokeCircle(
            ctx: ctx,
            center: center,
            radius: minDim * 0.13,
            lineWidth: minDim * 0.006,
            opacity: b
        )
    }

    private func drawSnareDot(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, now: Date) {
        let b = brightness(last: state.snareLastTrigger, now: now, decay: snareDecay)
        guard b > 0 else { return }
        let r = minDim * 0.05
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(fg.opacity(b)))
    }

    private func strokeCircle(
        ctx: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        opacity: Double
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        ctx.stroke(
            Path(ellipseIn: rect),
            with: .color(fg.opacity(opacity)),
            lineWidth: lineWidth
        )
    }
}
