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
            jitter: r * 0.06,
            seed: 11,
            points: 56
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
            jitter: r * 0.07,
            seed: 23,
            points: 40
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
            jitter: minDim * 0.004,
            seed: 41,
            points: 80
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
            jitter: minDim * 0.0025,
            seed: 61,
            points: 48
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

    // A closed loop around `center` at `baseRadius` with subtle
    // per-vertex offsets. The silhouette should read as "a circle
    // that's just slightly off" — not a star, not a polygon.
    //
    // Two offset sources:
    //   1. Two low-frequency sine waves keyed to each vertex's *angular
    //      position* — produces 1 or 2 gentle lobes around the
    //      perimeter. (An earlier implementation keyed phase to vertex
    //      *index* with a golden-ratio increment, which produced an
    //      N-pointed star because the sine completed many full cycles
    //      around the perimeter.)
    //   2. Neighbor-smoothed carved noise — gives the edge a subtle
    //      hand-hewn roughness without any individual vertex sticking
    //      out as a tooth.
    //
    // Fill → blob; stroke → ring.
    private func chiseledBlob(
        center: CGPoint,
        baseRadius: CGFloat,
        time: Double,
        jitter: CGFloat,
        seed: Int,
        points: Int
    ) -> Path {
        var path = Path()
        // 5-wide box blur of the per-vertex carved noise so each vertex
        // averages with its 4 nearest neighbors — smoothes the edge
        // enough that no single vertex reads as a tooth.
        var raw = [Double](repeating: 0, count: points)
        for i in 0..<points {
            raw[i] = carvedNoise(index: i, seed: seed)
        }
        var smoothed = [Double](repeating: 0, count: points)
        for i in 0..<points {
            var sum = 0.0
            for k in -2...2 {
                let idx = ((i + k) % points + points) % points
                sum += raw[idx]
            }
            smoothed[i] = sum / 5.0
        }
        let seedPhase = Double(seed) * 0.71
        for i in 0..<points {
            let angle = Double(i) / Double(points) * 2 * .pi
            // sin(angle * k) completes exactly k full cycles around the
            // perimeter regardless of vertex count — 1 cycle = one
            // gentle lobe, 2 cycles = two lobes. Stays subtle.
            let lobe1 = sin(angle + seedPhase + time * 0.55) * 0.30
            let lobe2 = sin(angle * 2 + seedPhase * 1.3 + time * 0.38) * 0.20
            let chisel = smoothed[i] * 0.25
            let r = baseRadius + CGFloat((lobe1 + lobe2 + chisel) * Double(jitter))
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
