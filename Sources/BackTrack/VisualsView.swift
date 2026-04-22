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
//   - Ink speckle scattered inside filled shapes (re-seeded per bar)
//
// Each voice's shape "draws in" on trigger and "draws out" during decay,
// animated via geometry (radius for blobs, trimmed stroke length for
// rings/rays) rather than opacity so the ink stays fully saturated —
// no greys.
//
// The synth layer palette follows the current song's `theme`:
//   .dark  → black background, white ink (default)
//   .light → white background, black ink
struct VisualsView: View {
    @EnvironmentObject var state: AppState

    // Per-voice envelope shape. `attack` is how long the draw-in takes;
    // `decay` is the draw-out. The sum is how long the shape is on screen.
    private let kickAttack: TimeInterval = 0.04
    private let kickDecay: TimeInterval  = 0.26
    private let snareAttack: TimeInterval = 0.04
    private let snareDecay: TimeInterval  = 0.20
    private let hhAttack: TimeInterval   = 0.03
    private let hhDecay: TimeInterval    = 0.12
    private let bassAttack: TimeInterval = 0.07
    private let bassDecay: TimeInterval  = 0.30
    private let padAttack: TimeInterval  = 0.10
    private let padDecay: TimeInterval   = 0.50

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
        // Deterministic per-bar seed so ink speckle re-seeds at each bar
        // boundary but stays stable within the bar (no strobing).
        let barSeed = seed(for: state.currentSong?.name ?? "", bar: state.currentBar)

        // Back to front. Pad strokes are outside the rings; kick blob can
        // cover rings momentarily on a hit; snare sits on top in the middle.
        drawPadInk(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawBassRing(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawHhRing(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        drawKickBlob(ctx: ctx, center: center, minDim: minDim, time: time, now: now, barSeed: barSeed)
        drawSnareBlob(ctx: ctx, center: center, minDim: minDim, time: time, now: now, barSeed: barSeed)
    }

    // Triangular envelope: rises 0→1 during `attack`, falls 1→0 during
    // `decay`, then clamps to 0. Used for both opacity-equivalent effects
    // (we instead drive geometry with this value) and path trimming.
    private func envelope(last: Date, now: Date, attack: Double, decay: Double) -> Double {
        let elapsed = now.timeIntervalSince(last)
        if elapsed < 0 { return 0 }
        if elapsed < attack { return elapsed / attack }
        let e = elapsed - attack
        if e < decay { return 1.0 - e / decay }
        return 0
    }

    // MARK: - Voices

    // Large chunky filled blob in the center on each kick hit.
    private func drawKickBlob(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date,
        barSeed: Int
    ) {
        let env = envelope(last: state.kickLastTrigger, now: now, attack: kickAttack, decay: kickDecay)
        guard env > 0 else { return }
        let peakRadius = minDim * 0.22
        let r = peakRadius * CGFloat(env)
        let blob = chiseledBlob(
            center: center,
            baseRadius: r,
            time: time,
            jitter: r * 0.22,
            seed: 11,
            points: 30
        )
        ctx.fill(blob, with: .color(ink))
        // Ink speckle inside the blob — opposite color, sparse.
        drawGrain(
            ctx: ctx,
            inside: blob,
            color: paper,
            count: 26,
            seed: barSeed &+ 101,
            area: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2),
            dotRadius: minDim * 0.0035
        )
    }

    // Smaller filled blob layered on top of the kick area.
    private func drawSnareBlob(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date,
        barSeed: Int
    ) {
        let env = envelope(last: state.snareLastTrigger, now: now, attack: snareAttack, decay: snareDecay)
        guard env > 0 else { return }
        let peakRadius = minDim * 0.075
        let r = peakRadius * CGFloat(env)
        let blob = chiseledBlob(
            center: center,
            baseRadius: r,
            time: time,
            jitter: r * 0.25,
            seed: 23,
            points: 22
        )
        ctx.fill(blob, with: .color(ink))
        drawGrain(
            ctx: ctx,
            inside: blob,
            color: paper,
            count: 8,
            seed: barSeed &+ 233,
            area: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2),
            dotRadius: minDim * 0.0025
        )
    }

    // Large chiseled irregular ring at ~40% of min dim.
    private func drawBassRing(
        ctx: GraphicsContext,
        center: CGPoint,
        minDim: CGFloat,
        time: Double,
        now: Date
    ) {
        let env = envelope(last: state.bassLastTrigger, now: now, attack: bassAttack, decay: bassDecay)
        guard env > 0 else { return }
        let radius = minDim * 0.38
        let ring = chiseledBlob(
            center: center,
            baseRadius: radius,
            time: time,
            jitter: minDim * 0.012,
            seed: 41,
            points: 48
        )
        let trimmed = ring.trimmedPath(from: 0, to: env)
        ctx.stroke(
            trimmed,
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
        let env = envelope(last: state.hhLastTrigger, now: now, attack: hhAttack, decay: hhDecay)
        guard env > 0 else { return }
        let radius = minDim * 0.11
        let ring = chiseledBlob(
            center: center,
            baseRadius: radius,
            time: time,
            jitter: minDim * 0.006,
            seed: 61,
            points: 32
        )
        let trimmed = ring.trimmedPath(from: 0, to: env)
        ctx.stroke(
            trimmed,
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
        let env = envelope(last: state.padLastTrigger, now: now, attack: padAttack, decay: padDecay)
        guard env > 0 else { return }
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
                jitter: minDim * 0.025
            )
            let trimmed = ray.trimmedPath(from: 0, to: env)
            ctx.stroke(
                trimmed,
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
    // breathe continuously) and a stable carved-noise offset (gives the
    // chiseled / linocut edge). Fill → filled blob; stroke → irregular
    // ring. Trimming the stroked form gives the draw-in/out animation.
    private func chiseledBlob(
        center: CGPoint,
        baseRadius: CGFloat,
        time: Double,
        jitter: CGFloat,
        seed: Int,
        points: Int
    ) -> Path {
        var path = Path()
        for i in 0..<points {
            let angle = Double(i) / Double(points) * 2 * .pi
            let phase = Double(i) * 1.618 + Double(seed) * 1.913
            let slow = sin(time * 0.55 + phase) * Double(jitter) * 0.6
            let fast = sin(time * 1.7 + phase * 2.3) * Double(jitter) * 0.25
            let chisel = carvedNoise(index: i, seed: seed) * Double(jitter) * 0.7
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
        var path = Path()
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let baseX = start.x + dx * CGFloat(t)
            let baseY = start.y + dy * CGFloat(t)
            // sin(π·t) is 0 at endpoints, 1 in the middle — fades jitter.
            let fade = sin(t * .pi)
            let wobble = sin(time * 0.7 + Double(seed) * 1.27 + t * 5.3) * fade
            let chisel = carvedNoise(index: i, seed: seed) * fade * 0.6
            let offset = (wobble + chisel) * Double(jitter)
            let x = baseX + px * CGFloat(offset)
            let y = baseY + py * CGFloat(offset)
            let p = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    // Scatter `count` small dots inside `path` using the opposite ink
    // color, seeded so they stay stable within a bar. Used to give
    // filled shapes the ink-speckle texture visible in the album art.
    private func drawGrain(
        ctx: GraphicsContext,
        inside path: Path,
        color: Color,
        count: Int,
        seed: Int,
        area: CGRect,
        dotRadius: CGFloat
    ) {
        guard count > 0 else { return }
        var clipped = ctx
        clipped.clip(to: path)
        for i in 0..<count {
            let rx = carvedNoise(index: i * 2, seed: seed)
            let ry = carvedNoise(index: i * 2 + 1, seed: seed &+ 7919)
            let x = area.midX + CGFloat(rx) * area.width / 2
            let y = area.midY + CGFloat(ry) * area.height / 2
            let rect = CGRect(
                x: x - dotRadius,
                y: y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            clipped.fill(Path(ellipseIn: rect), with: .color(color))
        }
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

    // Per-song × bar seed so ink grain re-lays out at each bar line but
    // stays stable within the bar. Hashing through the song name makes
    // two songs at the same bar count produce different speckle.
    private func seed(for songName: String, bar: Int) -> Int {
        var h = 5381
        for scalar in songName.unicodeScalars {
            h = (h &* 33) &+ Int(scalar.value)
        }
        return h &+ bar &* 2654435761
    }
}
