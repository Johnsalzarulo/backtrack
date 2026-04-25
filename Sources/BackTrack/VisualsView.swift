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
// Each voice is binary — full shape visible for a short hold window
// after a trigger, then nothing until the next hit. No fades, no
// draw-in/out. Organic feel comes from two permanent properties of
// the shapes (not from animation):
//   - subtle low-frequency sine wobble keyed to angular position
//   - per-vertex carved-noise smoothed across 5 neighbors
//
// Palette follows the current song's theme (`.dark` default). Style
// follows the song's visualizer field (`.sun` default). Both can be
// overridden live via the `I` and `M` hotkeys; overrides live in
// AppState.
struct VisualsView: View {
    @EnvironmentObject var state: AppState

    // When true, this VisualsView is embedded in the main HUD as a
    // small live preview of the secondary visuals window. Preview mode
    // skips the window-level modifiers (onDisappear toggle, full-bleed
    // ignoresSafeArea) so embedding doesn't trigger the "window was
    // closed" handler or try to extend past its SwiftUI frame.
    let isPreview: Bool

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
    }

    // How long each voice's shape stays on after a trigger. At 120 BPM
    // a quarter beat is 500 ms, so the kick is visible for ~26% of the
    // beat — clearly on / clearly off. Pad + bass linger because they're
    // sustained voices.
    private let kickHold: TimeInterval  = 0.13
    private let snareHold: TimeInterval = 0.10
    private let hhHold: TimeInterval    = 0.06
    private let bassHold: TimeInterval  = 0.20
    private let padHold: TimeInterval   = 0.45

    private var theme: VisualTheme { state.effectiveTheme }
    private var visualizer: VisualizerStyle { state.effectiveVisualizer }
    private var ink: Color { theme == .dark ? .white : .black }
    private var paper: Color { theme == .dark ? .black : .white }

    // Overscan safe margin, as a fraction of min(width, height), applied
    // to every non-GIF mode. CRTs and projectors routinely clip 5–10%
    // off each edge; this keeps shapes and text inside the visible area.
    // GIFs/images/videos skip the margin: the source is intended
    // full-bleed and cropping would just show paper-colored bars.
    private let overscanMargin: CGFloat = 0.07

    var body: some View {
        let content = ZStack {
            if state.lineupKind == .countdowns, let countdown = state.currentCountdown {
                // Countdown deck takes over the entire visuals window.
                // Bypasses the synth layer + GIF logic — countdowns have
                // their own dedicated UI (label + timer + progress + msg).
                CountdownView(
                    countdown: countdown,
                    transport: state.countdownTransport,
                    ink: ink,
                    paper: paper
                )
            } else if let beat = state.countInBeat {
                // Count-in pre-roll. The song hasn't started yet — show
                // a giant beat-in-bar number ("1, 2, 3, 4") that flips
                // with each click, ignoring whatever GIF/visualizer the
                // first part is configured with.
                LyricsBlockView(
                    text: "\(((beat - 1) % 4) + 1)",
                    ink: nsInk,
                    paper: nsPaper
                )
            } else if let url = state.currentPartVisualURL, !userOverridingVisuals {
                // Part has a visual and the user hasn't asked to see
                // the synth layer instead — GIF/image/video takes over.
                // Keeps playing even when transport is stopped, matching
                // the loop behavior of the source media.
                VisualView(url: url)
            } else if !state.isPlaying {
                // No part-level visual and transport is stopped — the
                // synth layer would be empty, so show TV static as the
                // idle / "no signal" state instead. Also covers app
                // launch, between songs, and any pause.
                IdleStaticView(ink: ink, paper: paper)
            } else {
                // Playing the synth layer. Either no part-level visual,
                // or the user pressed I or M to pull into the synth
                // layer. Their override beats the song's configured
                // visual so `M` actually cycles something visible even
                // on parts with a GIF.
                GeometryReader { geo in
                    let inset = min(geo.size.width, geo.size.height) * overscanMargin
                    synthContent
                        .padding(inset)
                }
            }
        }
        .background(paper)

        if isPreview {
            // Embedded in HUD — skip the window-level modifiers so the
            // HUD's appearance/disappearance doesn't trigger the
            // "window closed" handler.
            content
        } else {
            content
                .ignoresSafeArea()
                .onDisappear {
                    // Window was closed (either via X or programmatic
                    // dismiss). Reflect in state so the next V press
                    // re-opens cleanly.
                    state.visualsOpen = false
                }
        }
    }

    // True once the user has expressed intent to see a specific synth
    // motif via the M key. Theme override is deliberately ignored here:
    // theme doesn't affect GIF display, so pressing I on a part with a
    // GIF shouldn't hide the GIF. The theme override just waits in
    // memory until the user navigates to a synth view.
    private var userOverridingVisuals: Bool {
        state.visualizerOverride != nil
    }

    // Synth-layer content — geometric motifs render into a Canvas;
    // lyric motifs render typographically via SwiftUI / NSTextView.
    @ViewBuilder
    private var synthContent: some View {
        switch visualizer {
        case .constellation, .orbit, .ink, .squares, .dots, .lines, .ripple:
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    render(ctx: ctx, size: size, now: context.date)
                }
            }
        case .lyricsBlock:
            // Whole-part lyrics, newlines → spaces, auto-fit binary
            // search finds the largest size that fills the frame.
            LyricsBlockView(
                text: blockLyricsText,
                ink: nsInk,
                paper: nsPaper
            )
        case .lyricsLine:
            // Same auto-fit view, different source text. A single line
            // is typically short enough to end up much bigger than the
            // whole paragraph after auto-fit — the frame fills with
            // just those words, justified and wrapping as needed.
            LyricsBlockView(
                text: currentLyricLine,
                ink: nsInk,
                paper: nsPaper
            )
        }
    }

    // NSColor bridges for the block view (NSTextView uses AppKit colors).
    private var nsInk: NSColor { theme == .dark ? .white : .black }
    private var nsPaper: NSColor { theme == .dark ? .black : .white }

    // MARK: - Lyric timing

    // All lyrics for the current part, newlines replaced with spaces
    // so the whole thing flows as a single paragraph.
    private var blockLyricsText: String {
        guard let lyrics = state.currentPart?.lyrics else { return "" }
        return lyrics
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // Lines of lyric in the current part, non-empty only.
    private var lyricLines: [String] {
        guard let lyrics = state.currentPart?.lyrics, !lyrics.isEmpty else { return [] }
        return lyrics
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    // Fraction [0, 1] of the way through the current part, quantized
    // to quarter-note beats — good enough for line advancement without
    // needing sub-beat audio-clock precision.
    private var playbackFraction: Double {
        guard let part = state.currentPart else { return 0 }
        let total = part.bars * 4
        guard total > 0 else { return 0 }
        let elapsed = max(0, state.currentBar * 4 + state.currentBeat)
        return min(1.0, Double(elapsed) / Double(total))
    }

    // Current line of lyric based on playback position. Divides the
    // part evenly among the available lines.
    private var currentLyricLine: String {
        let lines = lyricLines
        guard !lines.isEmpty else { return "" }
        let idx = min(lines.count - 1, Int(playbackFraction * Double(lines.count)))
        return lines[idx]
    }

    // MARK: - Dispatch

    private func render(ctx: GraphicsContext, size: CGSize, now: Date) {
        let minDim = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let time = now.timeIntervalSinceReferenceDate

        switch visualizer {
        case .constellation:
            renderConstellation(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        case .orbit:
            renderOrbit(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        case .ink:
            renderInk(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        case .squares:
            renderSquares(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        case .dots:
            renderDots(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        case .lines:
            renderLines(ctx: ctx, size: size, minDim: minDim, time: time, now: now)
        case .ripple:
            renderRipple(ctx: ctx, center: center, minDim: minDim, time: time, now: now)
        case .lyricsBlock, .lyricsLine:
            // Lyric motifs don't use Canvas — handled by synthContent
            // at the SwiftUI view level. render() never sees them in
            // practice, but the switch has to be exhaustive.
            break
        }
    }

    // True if `last` fell within the last `hold` seconds of `now`.
    // Binary on/off — no attack/decay, no fade.
    private func isFiring(last: Date, now: Date, hold: Double) -> Bool {
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= 0 && elapsed < hold
    }

    // Pad stroke/dot/tile count per part's pad level.
    private func padCount() -> Int {
        switch state.currentPart?.padLevel ?? 0 {
        case 1: return 4
        case 2: return 6
        case 3: return 8
        default: return 6
        }
    }

    // MARK: - Style: orbit

    // Celestial bodies orbit the center on their own rings. Each voice
    // has a fixed orbit radius + period, so the bodies trace Kepler-ish
    // paths — inner orbits run faster. Bodies are always visible and
    // pulse (radius × 1.6) during their trigger's hold window. The
    // outermost ring doubles as a progress arc showing how far through
    // the current part we are.
    private func renderOrbit(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Outer progress ring. Thin outline of the whole circle plus
        // a thicker arc filled to the current playback fraction.
        drawProgressRing(ctx: ctx, center: center, radius: minDim * 0.56, minDim: minDim)

        // Single-body voices. (radius, body radius, period, seed, voice)
        let bodies: [(CGFloat, CGFloat, Double, Int, Bool)] = [
            (0.14, 0.055, 6.0,  11, isFiring(last: state.kickLastTrigger,  now: now, hold: kickHold)),
            (0.22, 0.040, 9.0,  23, isFiring(last: state.snareLastTrigger, now: now, hold: snareHold)),
            (0.30, 0.028, 12.0, 61, isFiring(last: state.hhLastTrigger,    now: now, hold: hhHold)),
            (0.40, 0.045, 18.0, 41, isFiring(last: state.bassLastTrigger,  now: now, hold: bassHold))
        ]
        for (rFrac, bodyFrac, period, seed, firing) in bodies {
            let orbitR = minDim * rFrac
            let pos = orbitPosition(time: time, center: center, radius: orbitR, period: period, phase: Double(seed) * 0.1)
            let body = minDim * bodyFrac * (firing ? 1.6 : 1.0)
            let blob = chiseledBlob(center: pos, baseRadius: body, time: time, jitter: body * 0.08, seed: seed, points: 28)
            ctx.fill(blob, with: .color(ink))
        }

        // Pad — 1, 2, or 3 bodies depending on pad level, evenly
        // distributed around the outermost orbit (but inside progress ring).
        let padBodies = max(1, padCount() / 2)       // 4/6/8 → 2/3/4
        let padFiring = isFiring(last: state.padLastTrigger, now: now, hold: padHold)
        let padR = minDim * 0.48
        let padBodySize = minDim * 0.033 * (padFiring ? 1.6 : 1.0)
        for i in 0..<padBodies {
            let orbitPhase = Double(i) / Double(padBodies)
            let pos = orbitPosition(time: time, center: center, radius: padR, period: 24.0, phase: orbitPhase)
            let blob = chiseledBlob(center: pos, baseRadius: padBodySize, time: time, jitter: padBodySize * 0.08, seed: 301 + i * 7, points: 24)
            ctx.fill(blob, with: .color(ink))
        }
    }

    private func orbitPosition(time: Double, center: CGPoint, radius: CGFloat, period: Double, phase: Double) -> CGPoint {
        // Start at 12 o'clock so a phase of 0 is visually "top".
        let angle = (time / period + phase) * 2 * .pi - .pi / 2
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private func drawProgressRing(ctx: GraphicsContext, center: CGPoint, radius: CGFloat, minDim: CGFloat) {
        // Thin always-on ring outline (so the progress track is visible
        // even at 0%).
        let ring = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        ctx.stroke(ring, with: .color(ink), lineWidth: minDim * 0.004)

        let progress = playbackFraction
        guard progress > 0 else { return }
        // Filled arc from 12 o'clock clockwise, thick stroke.
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        ctx.stroke(
            arc,
            with: .color(ink),
            style: StrokeStyle(lineWidth: minDim * 0.014, lineCap: .round)
        )
    }

    // MARK: - Style: ink

    // Ferrofluid-inspired central mass that deforms in response to each
    // voice. Each voice applies a characteristic "force" to the blob's
    // perimeter:
    //   kick   — uniform radial expansion (whole mass inflates)
    //   bass   — horizontal polarization (mass elongates L/R)
    //   snare  — sharp spikes at a few seeded vertices (local protrusions)
    //   hh     — high-frequency ripples around the perimeter (shimmer)
    //   pad    — slow sine wobble (2 lobes around the perimeter)
    //
    // Forces decay *smoothly* over their hold window rather than snapping
    // off — a deliberate exception to the "binary on/off" rule we follow
    // elsewhere. Ferrofluid is fundamentally about continuous liquid
    // motion; without the decay the mass would teleport between shapes.
    // The ink color stays 100% saturated the whole time; it's only the
    // shape that smoothly deforms, so the no-greys rule still holds.
    //
    // Splatter drops around the main mass add the Petri-dish character
    // from the reference photos. Positions re-seeded each bar so they
    // feel organic without flickering within a bar.
    private func renderInk(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Longer decay than other motifs' hold windows — the visible
        // motion of the mass IS the instrument response here, so the
        // forces need time to actually move the perimeter.
        let kickForce  = inkForce(last: state.kickLastTrigger,  now: now, decay: 0.35)
        let snareForce = inkForce(last: state.snareLastTrigger, now: now, decay: 0.28)
        let hhForce    = inkForce(last: state.hhLastTrigger,    now: now, decay: 0.18)
        let bassForce  = inkForce(last: state.bassLastTrigger,  now: now, decay: 0.50)
        let padForce   = inkForce(last: state.padLastTrigger,   now: now, decay: 0.70)

        let baseRadius = Double(minDim) * 0.20
        let points = 96

        // Snare spike pattern — which vertices get sharp protrusions
        // when snare fires. Seeded per beat so positions shift
        // naturally between snare hits rather than spiking the same
        // three points every time.
        let spikeSeed = (state.currentBar &* 4) &+ state.currentBeat
        var isSpike = [Bool](repeating: false, count: points)
        for i in 0..<points {
            // Threshold 0.88 ≈ top 6% of vertices → roughly 5 spikes.
            isSpike[i] = carvedNoise(index: i, seed: spikeSeed) > 0.88
        }

        // Main mass.
        var path = Path()
        for i in 0..<points {
            let angle = Double(i) / Double(points) * 2 * .pi
            let cosA = cos(angle)
            var r = baseRadius

            // Always-on resting wobble — low-freq sines, small amplitude.
            // Keeps a resting mass from looking like a perfect circle.
            let resting = sin(angle + time * 0.3) * 0.5
                + sin(angle * 3 + time * 0.5) * 0.3
            r += resting * Double(minDim) * 0.006

            // Kick — uniform radial push.
            r += kickForce * Double(minDim) * 0.08

            // Bass — horizontal polarization (max at left/right).
            r += bassForce * abs(cosA) * Double(minDim) * 0.12

            // Snare — sharp narrow spikes (NOT smoothed across neighbors;
            // we want teeth here, that's the whole point of the effect).
            if isSpike[i] {
                r += snareForce * Double(minDim) * 0.10
            }

            // HH — high-freq ripple (period ~5 vertices). Reads as shimmer.
            r += hhForce * sin(angle * 18 + time * 3.0) * Double(minDim) * 0.018

            // Pad — slow 2-lobe wobble, drifts over time.
            r += padForce * sin(angle * 2 + time * 0.7) * Double(minDim) * 0.025

            let x = Double(center.x) + cos(angle) * r
            let y = Double(center.y) + sin(angle) * r
            let p = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(ink))

        // Splatter drops — small fixed circles around the mass, positions
        // re-seeded per bar for organic variety.
        let dropCount = 6
        let dropSeedBase = state.currentBar &* 101
        for i in 0..<dropCount {
            let angle = carvedNoise(index: i, seed: dropSeedBase) * .pi * 2
            let distUnit = (carvedNoise(index: i, seed: dropSeedBase &+ 7) + 1) / 2  // [0,1]
            let sizeUnit = (carvedNoise(index: i, seed: dropSeedBase &+ 13) + 1) / 2
            let dist = Double(minDim) * (0.30 + 0.12 * distUnit)
            let dropR = Double(minDim) * (0.006 + 0.010 * sizeUnit)
            let dropX = Double(center.x) + cos(angle) * dist
            let dropY = Double(center.y) + sin(angle) * dist
            let rect = CGRect(
                x: dropX - dropR,
                y: dropY - dropR,
                width: dropR * 2,
                height: dropR * 2
            )
            ctx.fill(Path(ellipseIn: rect), with: .color(ink))
        }
    }

    // Ferrofluid-only helper: returns 1.0 at trigger time, linearly
    // decaying to 0 at the end of the decay window, negative elsewhere.
    // Unlike isFiring (which is binary), this lets the ink mass settle
    // smoothly back to resting shape.
    private func inkForce(last: Date, now: Date, decay: Double) -> Double {
        let elapsed = now.timeIntervalSince(last)
        if elapsed < 0 || elapsed >= decay { return 0 }
        return 1.0 - (elapsed / decay)
    }

    // MARK: - Style: squares

    // Everything is a wobbly-edged rectangle. Pad tiles arranged radially,
    // bass/hh as outlines, kick/snare as filled squares.
    private func renderSquares(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Pad — small filled square tiles at angles.
        if isFiring(last: state.padLastTrigger, now: now, hold: padHold) {
            let count = padCount()
            let orbitR = minDim * 0.37
            let half = minDim * 0.035
            for i in 0..<count {
                let angle = Double(i) * 2 * .pi / Double(count)
                let cx = center.x + CGFloat(cos(angle)) * orbitR
                let cy = center.y + CGFloat(sin(angle)) * orbitR
                let tile = chiseledRect(center: CGPoint(x: cx, y: cy), halfSize: half, time: time, jitter: half * 0.10, seed: 301 + i * 7)
                ctx.fill(tile, with: .color(ink))
            }
        }
        // Bass — large hollow square outline.
        if isFiring(last: state.bassLastTrigger, now: now, hold: bassHold) {
            let sq = chiseledRect(center: center, halfSize: minDim * 0.36, time: time, jitter: minDim * 0.005, seed: 41)
            ctx.stroke(sq, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.015, lineCap: .round, lineJoin: .round))
        }
        // HH — small hollow square.
        if isFiring(last: state.hhLastTrigger, now: now, hold: hhHold) {
            let sq = chiseledRect(center: center, halfSize: minDim * 0.11, time: time, jitter: minDim * 0.003, seed: 61)
            ctx.stroke(sq, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.010, lineCap: .round, lineJoin: .round))
        }
        // Kick — big filled square.
        if isFiring(last: state.kickLastTrigger, now: now, hold: kickHold) {
            let half = minDim * 0.19
            let sq = chiseledRect(center: center, halfSize: half, time: time, jitter: half * 0.08, seed: 11)
            ctx.fill(sq, with: .color(ink))
        }
        // Snare — smaller filled square.
        if isFiring(last: state.snareLastTrigger, now: now, hold: snareHold) {
            let half = minDim * 0.065
            let sq = chiseledRect(center: center, halfSize: half, time: time, jitter: half * 0.09, seed: 23)
            ctx.fill(sq, with: .color(ink))
        }
    }

    // MARK: - Style: dots

    // Every voice is expressed as circles. Big central blobs for
    // kick/snare, rings of many small dots for bass/hh, a scatter of
    // dots at fixed angles for the pad.
    private func renderDots(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Pad — scattered dots at golden-ratio angles around the orbit.
        if isFiring(last: state.padLastTrigger, now: now, hold: padHold) {
            let count = padCount()
            let orbitR = minDim * 0.42
            let dotR = minDim * 0.022
            for i in 0..<count {
                // Spread via golden ratio so 4/6/8 dots land at pleasing
                // non-symmetric angles.
                let angle = Double(i) * 2.39996 + 0.3
                let cx = center.x + CGFloat(cos(angle)) * orbitR
                let cy = center.y + CGFloat(sin(angle)) * orbitR
                let dot = chiseledBlob(center: CGPoint(x: cx, y: cy), baseRadius: dotR, time: time, jitter: dotR * 0.08, seed: 501 + i * 13, points: 24)
                ctx.fill(dot, with: .color(ink))
            }
        }
        // Bass — ring of 12 small dots at ~38% radius.
        if isFiring(last: state.bassLastTrigger, now: now, hold: bassHold) {
            dotRing(ctx: ctx, center: center, radius: minDim * 0.38, dotRadius: minDim * 0.014, count: 12, time: time, seedBase: 700)
        }
        // HH — tight ring of 8 tiny dots at ~11% radius.
        if isFiring(last: state.hhLastTrigger, now: now, hold: hhHold) {
            dotRing(ctx: ctx, center: center, radius: minDim * 0.11, dotRadius: minDim * 0.008, count: 8, time: time, seedBase: 800)
        }
        // Kick — big filled dot in the center.
        if isFiring(last: state.kickLastTrigger, now: now, hold: kickHold) {
            let r = minDim * 0.22
            let dot = chiseledBlob(center: center, baseRadius: r, time: time, jitter: r * 0.06, seed: 11, points: 56)
            ctx.fill(dot, with: .color(ink))
        }
        // Snare — smaller filled dot.
        if isFiring(last: state.snareLastTrigger, now: now, hold: snareHold) {
            let r = minDim * 0.075
            let dot = chiseledBlob(center: center, baseRadius: r, time: time, jitter: r * 0.07, seed: 23, points: 40)
            ctx.fill(dot, with: .color(ink))
        }
    }

    // Helper used by dots-style bass + hh: N small filled dots arranged
    // on a circle of the given radius.
    private func dotRing(ctx: GraphicsContext, center: CGPoint, radius: CGFloat, dotRadius: CGFloat, count: Int, time: Double, seedBase: Int) {
        for i in 0..<count {
            let angle = Double(i) * 2 * .pi / Double(count)
            let cx = center.x + CGFloat(cos(angle)) * radius
            let cy = center.y + CGFloat(sin(angle)) * radius
            let dot = chiseledBlob(center: CGPoint(x: cx, y: cy), baseRadius: dotRadius, time: time, jitter: dotRadius * 0.08, seed: seedBase + i * 11, points: 18)
            ctx.fill(dot, with: .color(ink))
        }
    }

    // MARK: - Style: lines

    // Every voice is a horizontal bar at a fixed Y. Reads like a
    // sparse sheet of music / barcode. Each bar has slightly wobbly
    // top + bottom edges (built from chiseledRect).
    private func renderLines(ctx: GraphicsContext, size: CGSize, minDim: CGFloat, time: Double, now: Date) {
        let cx = size.width / 2
        // Pad — N stacked dashes distributed across the upper half.
        if isFiring(last: state.padLastTrigger, now: now, hold: padHold) {
            let count = padCount()
            let spacing = minDim * 0.06
            // Center the stack vertically above the kick bar.
            let top = size.height / 2 - minDim * 0.20
            for i in 0..<count {
                let y = top - CGFloat(i) * spacing
                let halfW = minDim * 0.08
                let halfH = minDim * 0.008
                let bar = chiseledBar(center: CGPoint(x: cx, y: y), halfW: halfW, halfH: halfH, time: time, seed: 301 + i * 5)
                ctx.fill(bar, with: .color(ink))
            }
        }
        // Bass — long wide bar above center.
        if isFiring(last: state.bassLastTrigger, now: now, hold: bassHold) {
            let bar = chiseledBar(center: CGPoint(x: cx, y: size.height / 2 - minDim * 0.10), halfW: minDim * 0.36, halfH: minDim * 0.012, time: time, seed: 41)
            ctx.fill(bar, with: .color(ink))
        }
        // Kick — thickest, full-width, at center Y.
        if isFiring(last: state.kickLastTrigger, now: now, hold: kickHold) {
            let bar = chiseledBar(center: CGPoint(x: cx, y: size.height / 2), halfW: minDim * 0.42, halfH: minDim * 0.035, time: time, seed: 11)
            ctx.fill(bar, with: .color(ink))
        }
        // Snare — thin, narrower, just below kick.
        if isFiring(last: state.snareLastTrigger, now: now, hold: snareHold) {
            let bar = chiseledBar(center: CGPoint(x: cx, y: size.height / 2 + minDim * 0.09), halfW: minDim * 0.18, halfH: minDim * 0.008, time: time, seed: 23)
            ctx.fill(bar, with: .color(ink))
        }
        // HH — short tick-mark further below.
        if isFiring(last: state.hhLastTrigger, now: now, hold: hhHold) {
            let bar = chiseledBar(center: CGPoint(x: cx, y: size.height / 2 + minDim * 0.20), halfW: minDim * 0.045, halfH: minDim * 0.006, time: time, seed: 61)
            ctx.fill(bar, with: .color(ink))
        }
    }

    // MARK: - Style: ripple

    // Everything is a concentric ring at a fixed radius. When multiple
    // voices fire, you see a bullseye of nested circles.
    private func renderRipple(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Pad — N thin rings at radii spread across the mid-band.
        if isFiring(last: state.padLastTrigger, now: now, hold: padHold) {
            let count = padCount()
            // Evenly space between 18% and 60% of min dim.
            for i in 0..<count {
                let t = Double(i) / Double(max(count - 1, 1))
                let radius = minDim * (0.18 + 0.42 * CGFloat(t))
                let ring = chiseledBlob(center: center, baseRadius: radius, time: time, jitter: minDim * 0.003, seed: 301 + i * 9, points: 72)
                ctx.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.006, lineCap: .round, lineJoin: .round))
            }
        }
        // Bass — biggest ring, thickest.
        if isFiring(last: state.bassLastTrigger, now: now, hold: bassHold) {
            let ring = chiseledBlob(center: center, baseRadius: minDim * 0.54, time: time, jitter: minDim * 0.004, seed: 41, points: 96)
            ctx.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.016, lineCap: .round, lineJoin: .round))
        }
        // Kick — large thick ring (~42%).
        if isFiring(last: state.kickLastTrigger, now: now, hold: kickHold) {
            let ring = chiseledBlob(center: center, baseRadius: minDim * 0.42, time: time, jitter: minDim * 0.004, seed: 11, points: 80)
            ctx.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.020, lineCap: .round, lineJoin: .round))
        }
        // Snare — mid ring (~26%).
        if isFiring(last: state.snareLastTrigger, now: now, hold: snareHold) {
            let ring = chiseledBlob(center: center, baseRadius: minDim * 0.26, time: time, jitter: minDim * 0.003, seed: 23, points: 60)
            ctx.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.013, lineCap: .round, lineJoin: .round))
        }
        // HH — tiny inner ring (~11%).
        if isFiring(last: state.hhLastTrigger, now: now, hold: hhHold) {
            let ring = chiseledBlob(center: center, baseRadius: minDim * 0.11, time: time, jitter: minDim * 0.002, seed: 61, points: 48)
            ctx.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: minDim * 0.009, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Style: constellation

    // Fixed star-like positions on the canvas; each voice lights up its
    // star when fired. Positions feel star-chart-ish — no angular
    // symmetry to the arrangement. Same positions every frame, so you
    // can learn the layout.
    private func renderConstellation(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Fixed offsets from center, as fractions of min dim.
        let kickPos   = center
        let snarePos  = CGPoint(x: center.x + minDim * 0.26, y: center.y - minDim * 0.18)
        let bassPos   = CGPoint(x: center.x - minDim * 0.34, y: center.y + minDim * 0.15)
        let hhPos     = CGPoint(x: center.x + minDim * 0.36, y: center.y + minDim * 0.28)
        // Kick blob (big) in center.
        if isFiring(last: state.kickLastTrigger, now: now, hold: kickHold) {
            let r = minDim * 0.08
            let blob = chiseledBlob(center: kickPos, baseRadius: r, time: time, jitter: r * 0.08, seed: 11, points: 36)
            ctx.fill(blob, with: .color(ink))
        }
        // Snare star (upper right).
        if isFiring(last: state.snareLastTrigger, now: now, hold: snareHold) {
            let r = minDim * 0.05
            let blob = chiseledBlob(center: snarePos, baseRadius: r, time: time, jitter: r * 0.09, seed: 23, points: 28)
            ctx.fill(blob, with: .color(ink))
        }
        // Bass star (lower left).
        if isFiring(last: state.bassLastTrigger, now: now, hold: bassHold) {
            let r = minDim * 0.06
            let blob = chiseledBlob(center: bassPos, baseRadius: r, time: time, jitter: r * 0.08, seed: 41, points: 32)
            ctx.fill(blob, with: .color(ink))
        }
        // HH star (lower right).
        if isFiring(last: state.hhLastTrigger, now: now, hold: hhHold) {
            let r = minDim * 0.035
            let blob = chiseledBlob(center: hhPos, baseRadius: r, time: time, jitter: r * 0.10, seed: 61, points: 24)
            ctx.fill(blob, with: .color(ink))
        }
        // Pad stars — N fixed positions ringing the outside of the canvas.
        if isFiring(last: state.padLastTrigger, now: now, hold: padHold) {
            let count = padCount()
            let orbitR = minDim * 0.44
            let r = minDim * 0.028
            for i in 0..<count {
                // Irregular angular spacing via golden-ratio increments
                // so the stars don't land in a regular polygon.
                let angle = Double(i) * 2.39996 + 1.1
                let cx = center.x + CGFloat(cos(angle)) * orbitR
                let cy = center.y + CGFloat(sin(angle)) * orbitR
                let blob = chiseledBlob(center: CGPoint(x: cx, y: cy), baseRadius: r, time: time, jitter: r * 0.10, seed: 901 + i * 7, points: 22)
                ctx.fill(blob, with: .color(ink))
            }
        }
    }

    // MARK: - Shape helpers

    // A closed loop around `center` at `baseRadius` with subtle
    // per-vertex offsets. The silhouette should read as "a circle that's
    // just slightly off" — not a star, not a polygon. Two offset
    // sources: low-frequency sine waves keyed to vertex angle (1-2
    // gentle lobes around the perimeter) plus neighbor-smoothed carved
    // noise for a hand-hewn edge.
    private func chiseledBlob(
        center: CGPoint,
        baseRadius: CGFloat,
        time: Double,
        jitter: CGFloat,
        seed: Int,
        points: Int
    ) -> Path {
        var path = Path()
        var raw = [Double](repeating: 0, count: points)
        for i in 0..<points { raw[i] = carvedNoise(index: i, seed: seed) }
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

    // Wobbly rectangle centered on `center`, extending halfSize in each
    // direction. Fills with a chunky square with subtle edge jitter.
    // Used by the "squares" style. Points per side fixed; corners stay
    // roughly sharp because jitter fades toward zero at corners (so
    // neighboring edges don't disagree about where the corner is).
    private func chiseledRect(
        center: CGPoint,
        halfSize: CGFloat,
        time: Double,
        jitter: CGFloat,
        seed: Int
    ) -> Path {
        // 4 corners in CW order.
        let corners = [
            CGPoint(x: center.x - halfSize, y: center.y - halfSize),
            CGPoint(x: center.x + halfSize, y: center.y - halfSize),
            CGPoint(x: center.x + halfSize, y: center.y + halfSize),
            CGPoint(x: center.x - halfSize, y: center.y + halfSize)
        ]
        let pointsPerSide = 14
        let total = pointsPerSide * 4
        var raw = [Double](repeating: 0, count: total)
        for i in 0..<total { raw[i] = carvedNoise(index: i, seed: seed) }
        var smoothed = [Double](repeating: 0, count: total)
        for i in 0..<total {
            var sum = 0.0
            for k in -2...2 {
                let idx = ((i + k) % total + total) % total
                sum += raw[idx]
            }
            smoothed[i] = sum / 5.0
        }
        var path = Path()
        let seedPhase = Double(seed) * 0.71
        var globalIdx = 0
        for side in 0..<4 {
            let a = corners[side]
            let b = corners[(side + 1) % 4]
            let dx = (b.x - a.x) / CGFloat(pointsPerSide)
            let dy = (b.y - a.y) / CGFloat(pointsPerSide)
            let len = hypot(b.x - a.x, b.y - a.y)
            // Perpendicular, outward.
            let px = (b.y - a.y) / len
            let py = -(b.x - a.x) / len
            for j in 0..<pointsPerSide {
                let t = Double(j) / Double(pointsPerSide)
                let baseX = a.x + dx * CGFloat(j)
                let baseY = a.y + dy * CGFloat(j)
                // Fade to zero at both ends so corners stay crisp.
                let fade = sin(t * .pi)
                let wobble = sin(Double(globalIdx) * 0.45 + seedPhase + time * 0.45) * 0.5
                let chisel = smoothed[globalIdx] * 0.35
                let offset = (wobble + chisel) * fade * Double(jitter)
                let x = baseX + px * CGFloat(offset)
                let y = baseY + py * CGFloat(offset)
                let p = CGPoint(x: x, y: y)
                if side == 0 && j == 0 {
                    path.move(to: p)
                } else {
                    path.addLine(to: p)
                }
                globalIdx += 1
            }
        }
        path.closeSubpath()
        return path
    }

    // Horizontal bar centered on `center`, halfW wide and halfH tall.
    // Thin wrapper around chiseledRect with different jitter tuning so
    // the bar's short ends stay tidy and the long edges get a subtle
    // vertical wobble.
    private func chiseledBar(
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        time: Double,
        seed: Int
    ) -> Path {
        // Hack: build from the rect helper using the smaller dimension
        // as the jitter scale, so wobble reads as "subtle edge" rather
        // than "dramatically irregular".
        let jitter = min(halfW, halfH) * 0.18
        return chiseledRectAsymmetric(
            center: center,
            halfW: halfW,
            halfH: halfH,
            time: time,
            jitter: jitter,
            seed: seed
        )
    }

    // Non-square version of chiseledRect. Same edge-fading philosophy.
    private func chiseledRectAsymmetric(
        center: CGPoint,
        halfW: CGFloat,
        halfH: CGFloat,
        time: Double,
        jitter: CGFloat,
        seed: Int
    ) -> Path {
        let corners = [
            CGPoint(x: center.x - halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y + halfH),
            CGPoint(x: center.x - halfW, y: center.y + halfH)
        ]
        let pointsPerSide = 14
        let total = pointsPerSide * 4
        var raw = [Double](repeating: 0, count: total)
        for i in 0..<total { raw[i] = carvedNoise(index: i, seed: seed) }
        var smoothed = [Double](repeating: 0, count: total)
        for i in 0..<total {
            var sum = 0.0
            for k in -2...2 {
                let idx = ((i + k) % total + total) % total
                sum += raw[idx]
            }
            smoothed[i] = sum / 5.0
        }
        var path = Path()
        let seedPhase = Double(seed) * 0.71
        var globalIdx = 0
        for side in 0..<4 {
            let a = corners[side]
            let b = corners[(side + 1) % 4]
            let dx = (b.x - a.x) / CGFloat(pointsPerSide)
            let dy = (b.y - a.y) / CGFloat(pointsPerSide)
            let len = hypot(b.x - a.x, b.y - a.y)
            let px = (b.y - a.y) / len
            let py = -(b.x - a.x) / len
            for j in 0..<pointsPerSide {
                let t = Double(j) / Double(pointsPerSide)
                let baseX = a.x + dx * CGFloat(j)
                let baseY = a.y + dy * CGFloat(j)
                let fade = sin(t * .pi)
                let wobble = sin(Double(globalIdx) * 0.45 + seedPhase + time * 0.45) * 0.5
                let chisel = smoothed[globalIdx] * 0.35
                let offset = (wobble + chisel) * fade * Double(jitter)
                let x = baseX + px * CGFloat(offset)
                let y = baseY + py * CGFloat(offset)
                let p = CGPoint(x: x, y: y)
                if side == 0 && j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                globalIdx += 1
            }
        }
        path.closeSubpath()
        return path
    }

    // Open wobbly line from start → end with perpendicular offsets that
    // fade to 0 at both endpoints. Used by the sun style for pad rays.
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
        let px = -dy / len
        let py = dx / len
        var chiselRaw = [Double](repeating: 0, count: segments + 1)
        for i in 0...segments { chiselRaw[i] = carvedNoise(index: i, seed: seed) }
        var path = Path()
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let baseX = start.x + dx * CGFloat(t)
            let baseY = start.y + dy * CGFloat(t)
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
    // Stable per-frame — same (i, seed) returns the same value every
    // call, so carved edges don't jitter each frame.
    private func carvedNoise(index: Int, seed: Int) -> Double {
        let raw = UInt32(bitPattern: Int32(truncatingIfNeeded: (index &+ seed) &* 2654435761))
        let mixed = (raw ^ (raw >> 16)) &* 2246822507
        let norm = Double(mixed & 0xFFFF) / Double(0xFFFF)
        return norm * 2 - 1
    }
}
