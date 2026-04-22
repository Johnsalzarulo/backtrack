import SwiftUI

// Secondary window showing the synth layer — chunky, linocut-inspired
// ink shapes that react to drum / pad / bass triggers. Runs on SwiftUI's
// Canvas + TimelineView so it re-renders every display frame against the
// same trigger timestamps the HUD already uses. Aspect-agnostic: every
// dimension is derived from min(width, height).
//
// When the current part has a visual (still image, GIF, or video) that
// takes over the whole window and the synth layer is suppressed.
//
// The visual vocabulary is black-and-white linocut:
//   - Filled chiseled blobs for percussive hits (kick, snare)
//   - Chiseled rings (unfilled outlines) for bass + hi-hat
//   - Thick irregular ink strokes radiating from center for the pad,
//     more strokes at higher pad levels
//
// Each voice is binary — full shape visible for a short hold window
// after a trigger, then nothing until the next hit. No fades, no
// draw-in/out, no grain. Responsiveness matters more than transitions;
// the organic feel comes from the always-on wobble + chiseled edges
// on the shapes themselves.
//
// The palette follows the current song's `theme`:
//   .dark  → black background, white ink (default)
//   .light → white background, black ink
struct VisualsView: View {
    @EnvironmentObject var state: AppState

    // How long each voice's shape stays on after a trigger. Chosen to
    // feel snappy at typical tempos — at 120 BPM a quarter beat is
    // 500 ms, so the kick is visible for ~26% of the beat, clearly
    // on / clearly off. Pad + bass linger a bit because they're
    // sustained voices.
    private let kickHold: TimeInterval  = 0.13
    private let snareHold: TimeInterval = 0.10
    private let hhHold: TimeInterval    = 0.06
    private let bassHold: TimeInterval  = 0.20
    private let padHold: TimeInterval   = 0.45

    private var theme: VisualTheme {
        state.currentSong?.theme ?? .dark
    }
    private var ink: Color {
        theme == .dark ? .white : .black
    }
    private var paper: Color {
        theme == .dark ? .black : .white
    }

    var body: some View {
        ZStack {
            if let url = state.currentPartVisualURL {
                // Part has a visual: take over the window, suppress synth.
                VisualView(url: url)
                    .ignoresSafeArea()
            } else {
                // Synth layer. The .background draws the paper color so
                // Canvas only needs to stamp ink on top.
                TimelineView(.animation) { context in
                    Canvas { ctx, size in
                        render(ctx: ctx, size: size, now: context.date)
                    }
                }
                .background(paper)
                .ignoresSafeArea()
            }
        }
        .background(paper)
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
        let time = now.timeIntervalSinceReferenceDate

        // Back to front. Pad strokes are outside the rings; kick blob
        // covers the ring zone while firing; snare sits on top.
        drawPadInk(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawBassRing(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawHhRing(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawKickBlob(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawSnareBlob(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
    }

    // True if `last` fell within the last `hold` seconds of `now`.
    // Replaces the earlier envelope approach — shapes are now binary
    // on/off, no draw-in or draw-out animation.
    private func isFiring(last: Date, now: Date, hold: Double) -> Bool {
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= 0 && elapsed < hold
    }

    // MARK: - Voices

    // Large chunky filled blob in the center on each kick hit.
    private func drawKickBlob(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date
    ) {
        guard isFiring(last: state.kickLastTrigger, now: now, hold: kickHold) else { return }
        let r = minDim * 0.22
        let blob = chiseledBlob(
            center: center,
            baseRadius: r,
            time: time,
            jitter: r * 0.10,
            seed: 11,
            points: 44
        )
        ctx.fill(blob, with: .color(ink))
    }

    // Smaller filled blob layered on top of the kick area.
    private func drawSnareBlob(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date
    ) {
        guard isFiring(last: state.snareLastTrigger, now: now, hold: snareHold) else { return }
        let r = minDim * 0.075
        let blob = chiseledBlob(
            center: center,
            baseRadius: r,
            time: time,
            jitter: r * 0.14,
            seed: 23,
            points: 32
        )
        ctx.fill(blob, with: .color(ink))
    }

    // Large chiseled irregular ring at ~38% of min dim.
    private func drawBassRing(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date
    ) {
        guard isFiring(last: state.bassLastTrigger, now: now, hold: bassHold) else { return }
        let radius = minDim * 0.38
        let ring = chiseledBlob(
            center: center,
            baseRadius: radius,
            time: time,
            jitter: minDim * 0.006,
            seed: 41,
            points: 64
        )
        ctx.stroke(
            ring,
            with: .color(ink),
            style: StrokeStyle(lineWidth: minDim * 0.015, lineCap: .round, lineJoin: .round)
        )
    }

    // Small ring inside the kick blob zone; fires more often than bass.
    private func drawHhRing(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date
    ) {
        guard isFiring(last: state.hhLastTrigger, now: now, hold: hhHold) else { return }
        let radius = minDim * 0.11
        let ring = chiseledBlob(
            center: center,
            baseRadius: radius,
            time: time,
            jitter: minDim * 0.004,
            seed: 61,
            points: 40
        )
        ctx.stroke(
            ring,
            with: .color(ink),
            style: StrokeStyle(lineWidth: minDim * 0.010, lineCap: .round, lineJoin: .round)
        )
    }

    // Thick irregular ink strokes radiating from the center. The number
    // of strokes tracks pad complexity so level 3 parts feel denser.
    private func drawPadInk(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date
    ) {
        guard isFiring(last: state.padLastTrigger, now: now, hold: padHold) else { return }
        let count = padStrokeCount()
        let innerR = minDim * 0.26
        let outerR = minDim * 0.47
        let thickness = minDim * 0.018
        for i in 0..<count {
            let angle = Double(i) * 2 * .pi / Double(count)
            let cosA = CGFloat(cos(angle))
            let sinA = CGFloat(sin(angle))
            let start = CGPoint(x: center.x + cosA * innerR, y: center.y + sinA * innerR)
            let end = CGPoint(x: center.x + cosA * outerR, y: center.y + sinA * outerR)
            let ray = wobblyStroke(
                start: start,
                end: end,
                time: time,
                seed: i * 97 + 3,
                jitter: minDim * 0.012
            )
            ctx.stroke(
                ray,
                with: .color(ink),
                style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func padStrokeCount() -> Int {
        switch state.currentPart?.padLevel ?? 0 {
        case 1: return 4
        case 2: return 6
        case 3: return 8
        default: return 6
        }
    }

    // MARK: - Shape helpers

    // A closed loop around `center` at `baseRadius`, with per-vertex
    // offsets from two sources: a slow sine wobble (makes the shape
    // breathe continuously) and a neighbor-smoothed carved-noise offset
    // (gives the chiseled / linocut edge). Fill → blob; stroke → ring.
    private func chiseledBlob(
        center: CGPoint,
        baseRadius: CGFloat,
        time: Double,
        jitter: CGFloat,
        seed: Int,
        points: Int
    ) -> Path {
        var path = Path()
        // Smooth the chisel noise across neighbors so we don't get
        // alternating-vertex spikes that read as teeth. A 3-wide box
        // blur gives a roughened edge without sharp points.
        var chiselRaw = [Double](repeating: 0, count: points)
        for i in 0..<points {
            chiselRaw[i] = carvedNoise(index: i, seed: seed)
        }
        for i in 0..<points {
            let angle = Double(i) / Double(points) * 2 * .pi
            let phase = Double(i) * 1.618 + Double(seed) * 1.913
            let slow = sin(time * 0.55 + phase) * Double(jitter) * 0.7
            let fast = sin(time * 1.7 + phase * 2.3) * Double(jitter) * 0.2
            let prev = chiselRaw[(i + points - 1) % points]
            let curr = chiselRaw[i]
            let next = chiselRaw[(i + 1) % points]
            let chisel = (prev + curr + next) / 3.0 * Double(jitter) * 0.3
            let r = baseRadius + CGFloat(slow + fast + chisel)
            let x = center.x + CGFloat(cos(angle)) * r
            let y = center.y + CGFloat(sin(angle)) * r
            let p = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    // An open wobbly line from `start` to `end`, with perpendicular
    // offsets that fade to zero at both endpoints (so rays still
    // anchor at the inner/outer radius they're supposed to reach).
    private func wobblyStroke(
        start: CGPoint,
        end: CGPoint,
        time: Double,
        seed: Int,
        jitter: CGFloat,
        segments: Int = 10
    ) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = hypot(dx, dy)
        guard len > 0 else {
            var p = Path()
            p.move(to: start)
            p.addLine(to: end)
            return p
        }
        // Perpendicular unit vector.
        let px = -dy / len
        let py = dx / len
        // Same neighbor-smoothed chisel noise as chiseledBlob — keeps
        // strokes wavy rather than zigzag.
        var chiselRaw = [Double](repeating: 0, count: segments + 1)
        for i in 0...segments {
            chiselRaw[i] = carvedNoise(index: i, seed: seed)
        }
        var path = Path()
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let baseX = start.x + dx * CGFloat(t)
            let baseY = start.y + dy * CGFloat(t)
            // sin(π·t) is 0 at endpoints, 1 in the middle — fades jitter.
            let fade = sin(t * .pi)
            let wobble = sin(time * 0.7 + Double(seed) * 1.27 + t * 5.3) * fade
            let prev = i > 0 ? chiselRaw[i - 1] : chiselRaw[i]
            let curr = chiselRaw[i]
            let next = i < segments ? chiselRaw[i + 1] : chiselRaw[i]
            let chiselSmoothed = (prev + curr + next) / 3.0
            let chisel = chiselSmoothed * fade * 0.25
            let offset = (wobble + chisel) * Double(jitter)
            let x = baseX + px * CGFloat(offset)
            let y = baseY + py * CGFloat(offset)
            let p = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    // Deterministic pseudo-random in [-1, 1] from an (index, seed) pair.
    // Stable per-frame — same (i, seed) returns the same value every call,
    // so carved edges don't jitter each frame (the sine wobbles handle
    // continuous movement; this handles the fixed rough-edge character).
    private func carvedNoise(index: Int, seed: Int) -> Double {
        let raw = UInt32(bitPattern: Int32(truncatingIfNeeded: (index &+ seed) &* 2654435761))
        let mixed = (raw ^ (raw >> 16)) &* 2246822507
        let norm = Double(mixed & 0xFFFF) / Double(0xFFFF)
        return norm * 2 - 1
    }
}
