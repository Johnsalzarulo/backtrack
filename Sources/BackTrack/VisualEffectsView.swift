import SwiftUI

// Post-processing effects applied as a wrapping layer above the
// entire visuals window — sitting over the synth Canvas, GIF/video
// player, lyric typography, and countdown view alike. Each effect
// is a ViewModifier so callers can apply them with `.modifier(…)`.
//
// Beat-synced behavior reads `state.lastBeatTime` (stamped by Clock
// on every quarter-note advance and during count-in clicks). When
// the song isn't playing the timestamp stays at .distantPast so
// effects animate freely on wall-clock time instead.
//
// All effects stick to pure SwiftUI compositing — no Metal shaders —
// so they work on macOS 13+. That means no real posterize / shader
// filters, but blendMode + colorMultiply + Canvas overlays cover
// most of the perceptual space.

// MARK: - Glitch

// Digital corruption. Beat-synced: every quarter-note triggers a
// brief intense pulse that fades over ~180 ms — horizontal jitter
// shakes the whole frame, random horizontal slices flash in a
// .difference blend (instant inversion of whatever's underneath),
// and a thin hue/saturation pulse simulates chromatic aberration.
// Between beats, low-amplitude jitter keeps the frame breathing.
//
// Every 4th bar's downbeat triggers a *major* glitch — longer decay,
// roughly double jitter amplitude, more slices. That's the "every
// once in a while it goes really hard" beat the user asked for, and
// it lines up with phrase boundaries in 4-bar musical phrases.
struct GlitchModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let now = context.date
            let beatAge = now.timeIntervalSince(state.lastBeatTime)
            // Major glitch on every 4th bar's downbeat. Longer decay
            // window + larger amplitude — perceived as a section-
            // boundary "tearing" rather than a regular beat hit.
            let isMajor = (state.currentBar % 4 == 0 && state.currentBeat == 0)
            let burstDecay: TimeInterval = isMajor ? 0.45 : 0.18
            let burst = max(0, 1 - beatAge / burstDecay)
            let majorBoost: Double = isMajor ? 2.0 : 1.0

            let idle: Double = 0.08
            let seed = (state.currentBar * 4 + state.currentBeat)

            content
                .offset(
                    x: CGFloat(jitter(seed: seed, axis: 0) * (burst * 12 * majorBoost + idle * 1.5)),
                    y: CGFloat(jitter(seed: seed, axis: 1) * (burst * 4 * majorBoost + idle * 0.5))
                )
                .saturation(1 + burst * 0.6 * majorBoost)
                .hueRotation(.degrees(burst * 18 * jitter(seed: seed, axis: 2) * majorBoost))
                .overlay(
                    GlitchSliceOverlay(
                        intensity: burst,
                        idleIntensity: idle,
                        seed: seed,
                        majorBoost: majorBoost
                    )
                    .allowsHitTesting(false)
                )
        }
    }

    private func jitter(seed: Int, axis: Int) -> Double {
        let h = (seed &* 73856093) ^ (axis &* 19349663)
        let normalized = Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
        return normalized * 2 - 1
    }
}

private struct GlitchSliceOverlay: View {
    let intensity: Double
    let idleIntensity: Double
    let seed: Int
    let majorBoost: Double

    var body: some View {
        Canvas { ctx, size in
            let total = intensity + idleIntensity
            guard total > 0.01 else { return }

            // Major beats get ~3× the slice count for a denser tear.
            let sliceCount = Int(round(intensity * 6 * majorBoost + idleIntensity * 1))
            for i in 0..<sliceCount {
                let r1 = pseudo(seed: seed, salt: i * 7 + 1)
                let r2 = pseudo(seed: seed, salt: i * 7 + 2)
                let r3 = pseudo(seed: seed, salt: i * 7 + 3)
                let y = CGFloat(r1) * size.height
                let h = max(2, CGFloat(r2 * r2) * size.height * 0.06 * CGFloat(majorBoost))
                let alpha = 0.4 + r3 * 0.5
                let rect = CGRect(x: 0, y: y, width: size.width, height: h)
                ctx.fill(Path(rect), with: .color(.white.opacity(alpha)))
            }
        }
        .blendMode(.difference)
    }

    private func pseudo(seed: Int, salt: Int) -> Double {
        let h = (seed &* 2654435761) ^ (salt &* 40503)
        return Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
    }
}

// MARK: - Tracking

// VCR tracking artifact. Two layers of distortion:
//   • Continuous horizontal band of heavy slice noise that sweeps
//     down the screen, like a tape head perpetually out of alignment.
//   • Periodic vertical roll — every ~6 seconds the picture loses
//     vertical hold and rolls upward, top half disappearing off the
//     top while the bottom half climbs up to take its place. Sync
//     band of static fills the seam during the roll. Lasts ~0.7 s
//     per event.
//
// Plus the constant low-level VHS treatment outside the band: slight
// desaturation, brightness drop, and a tiny horizontal wobble.
struct TrackingModifier: ViewModifier {
    @ObservedObject var state: AppState

    // Tunables for the periodic roll. Cycle is the seconds between
    // rolls; duration is how long the roll itself takes.
    private static let rollCycle: Double = 6.0
    private static let rollDuration: Double = 0.7

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let now = context.date
            let timeRef = now.timeIntervalSinceReferenceDate
            // Continuous band sweep — one pass every 3.5 s.
            let bandFraction = (timeRef.truncatingRemainder(dividingBy: 3.5)) / 3.5
            // Per-beat distortion bump.
            let beatAge = now.timeIntervalSince(state.lastBeatTime)
            let beatPulse = max(0, 1 - beatAge / 0.25)
            // Roll progress — 0..1 during the roll window, 0 otherwise.
            let cyclePos = timeRef.truncatingRemainder(dividingBy: Self.rollCycle)
            let rollActive = cyclePos < Self.rollDuration
            let rollProgress = rollActive ? cyclePos / Self.rollDuration : 0

            // Subtle constant wobble so the picture always feels like a
            // worn tape, even between rolls.
            let wobble = CGFloat(sin(timeRef * 11) * 0.9 + sin(timeRef * 27) * 0.4)

            GeometryReader { geo in
                let h = geo.size.height
                let rollPx = CGFloat(rollProgress) * h

                ZStack {
                    if rollActive {
                        // Render the content twice, vertically stacked
                        // and clipped, so the picture really does roll
                        // off the top and reappear from below. Costs an
                        // extra render of `content` for the duration of
                        // the roll — only ~0.7 s out of every 6 s.
                        content
                            .saturation(0.78)
                            .brightness(-0.02)
                            .offset(x: wobble, y: -rollPx)
                        content
                            .saturation(0.78)
                            .brightness(-0.02)
                            .offset(x: wobble, y: h - rollPx)
                        // Sync band / dropout strip at the seam.
                        SyncSeam(seamY: h - rollPx, bandHeight: h * 0.06,
                                 timeSeed: Int(timeRef * 80))
                            .allowsHitTesting(false)
                    } else {
                        content
                            .saturation(0.78)
                            .brightness(-0.02)
                            .offset(x: wobble)
                    }

                    // Continuous tracking-band overlay. Stays on
                    // through the roll too — the audience sees the
                    // band continue across the seam, which sells the
                    // "broken tape" feel even harder.
                    TrackingBandOverlay(
                        bandFraction: bandFraction,
                        beatPulse: beatPulse,
                        timeSeed: Int(timeRef * 60)
                    )
                    .allowsHitTesting(false)
                }
                .clipped()
            }
        }
    }
}

// Heavy slice noise inside the rolling band, plus extra background
// lines outside the band so the whole image feels worn. The band
// itself has bright/dark sync lines top + bottom. Drawn in
// .difference blend mode so it inverts whatever's underneath rather
// than just slapping white pixels on top.
private struct TrackingBandOverlay: View {
    let bandFraction: Double  // 0..1, position of band center
    let beatPulse: Double
    let timeSeed: Int

    var body: some View {
        Canvas { ctx, size in
            let bandH = size.height * 0.15 + size.height * 0.05 * beatPulse
            // Band travels from -bandH (just off the top) to size.height
            // so it fully enters and exits the frame each pass.
            let bandCenter = CGFloat(bandFraction) * (size.height + bandH * 2) - bandH
            let bandTop = bandCenter - bandH / 2
            let bandBottom = bandCenter + bandH / 2

            // Heavy slice noise inside the band.
            let sliceCount = 28 + Int(beatPulse * 14)
            for i in 0..<sliceCount {
                let r1 = pseudo(seed: timeSeed, salt: i * 5 + 1)
                let r2 = pseudo(seed: timeSeed, salt: i * 5 + 2)
                let r3 = pseudo(seed: timeSeed, salt: i * 5 + 3)
                let y = bandTop + CGFloat(r1) * (bandBottom - bandTop)
                guard y >= 0, y <= size.height else { continue }
                let h = max(1, CGFloat(r2 * r2) * 5 + 1)
                let alpha = 0.5 + r3 * 0.4
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: h)),
                    with: .color(.white.opacity(alpha))
                )
            }

            // Sparse background lines outside the band — gives the
            // whole image that "tape's been chewed" feel rather than
            // a clean picture with one band of distortion.
            let bgLines = 8
            for i in 0..<bgLines {
                let r1 = pseudo(seed: timeSeed &+ 9000, salt: i * 3 + 1)
                let r2 = pseudo(seed: timeSeed &+ 9000, salt: i * 3 + 2)
                let y = CGFloat(r1) * size.height
                let alpha = 0.18 + r2 * 0.18
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white.opacity(alpha))
                )
            }

            // Bright top edge of the band — the iconic VCR sync line.
            if bandTop >= 0 && bandTop <= size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: bandTop, width: size.width, height: 2)),
                    with: .color(.white.opacity(0.85))
                )
            }
            // Dark bottom edge — the tracking dropout shadow.
            if bandBottom >= 0 && bandBottom <= size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: bandBottom, width: size.width, height: 2)),
                    with: .color(.black.opacity(0.7))
                )
            }
        }
        .blendMode(.difference)
    }

    private func pseudo(seed: Int, salt: Int) -> Double {
        let h = (seed &* 2654435761) ^ (salt &* 40503)
        return Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
    }
}

// Drawn during the vertical roll only. Black band of static at the
// seam where the picture wraps, with horizontal noise lines inside —
// reads as the "lost vertical hold" sync gap.
private struct SyncSeam: View {
    let seamY: CGFloat
    let bandHeight: CGFloat
    let timeSeed: Int

    var body: some View {
        Canvas { ctx, size in
            let top = max(0, seamY - bandHeight / 2)
            let bottom = min(size.height, seamY + bandHeight / 2)
            // Black band so the seam reads as a dropout, not just a
            // tinted overlay.
            ctx.fill(
                Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)),
                with: .color(.black.opacity(0.92))
            )
            // Horizontal noise lines inside the band.
            for i in 0..<16 {
                let r1 = pseudo(seed: timeSeed, salt: i * 7 + 1)
                let r2 = pseudo(seed: timeSeed, salt: i * 7 + 2)
                let y = top + CGFloat(r1) * (bottom - top)
                let lineH = max(1, CGFloat(r2 * r2) * 3)
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: lineH)),
                    with: .color(.white.opacity(0.7))
                )
            }
        }
    }

    private func pseudo(seed: Int, salt: Int) -> Double {
        let h = (seed &* 2654435761) ^ (salt &* 40503)
        return Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
    }
}

// MARK: - Chroma

// RGB channel separation. Three offset copies of the underlying
// content — tinted red, green, and blue via colorMultiply, combined
// with `.plusLighter` blend mode (additive) — so at zero offset they
// sum back to the original image exactly. As offset grows the red
// channel shifts in one direction and blue in the opposite, giving
// classic chromatic aberration / vintage 3D anaglyph fringing.
//
// Beat-reactive in three ways:
//   • Per-beat angle. Each beat picks a fresh direction (up, down,
//     diagonal, side-to-side) from a hash of (bar, beat) so the
//     channels don't always split along the same axis.
//   • Bar-start boost. Every downbeat (beat 0 of any bar) gets a
//     larger burst — the audience feels the bar grid through the
//     channels widening on the "1".
//   • Part-start blowout. The first beat of a part fires the largest
//     burst of all — the channels really tear open at section
//     transitions.
//
// Costs 3× the underlying content's render budget — that's the price
// of pure-SwiftUI channel separation without Metal shaders.
struct ChromaModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let beatAge = context.date.timeIntervalSince(state.lastBeatTime)
            let pulse = max(0, 1 - beatAge / 0.30)

            // Per-beat seed → angle in [0, 2π). Direction snaps on
            // each new beat instead of always splitting horizontally.
            let seed = state.currentBar * 4 + state.currentBeat
            let angle = pseudo(seed: seed, salt: 11) * 2.0 * .pi

            // Burst boost on bar/part starts. Downbeats (beat 0) feel
            // the bar grid; bar 0 beat 0 feels the part transition.
            let isDownbeat = state.currentBeat == 0
            let isPartStart = isDownbeat && state.currentBar == 0
            let burstBoost: CGFloat = isPartStart ? 2.6 : (isDownbeat ? 1.6 : 1.0)

            // Baseline +66% over the previous version, burst +55%.
            // The user wanted "30% more pronounced at least"; we land
            // safely above that.
            let baseline: CGFloat = 2.5
            let burstMag: CGFloat = 14 * burstBoost
            let magnitude = baseline + burstMag * CGFloat(pulse)
            let dx = CGFloat(cos(angle)) * magnitude
            let dy = CGFloat(sin(angle)) * magnitude

            ZStack {
                content
                    .colorMultiply(.red)
                    .offset(x: -dx, y: -dy)
                    .blendMode(.plusLighter)
                content
                    .colorMultiply(.green)
                    .blendMode(.plusLighter)
                content
                    .colorMultiply(.blue)
                    .offset(x: dx, y: dy)
                    .blendMode(.plusLighter)
            }
            .compositingGroup()
            // A black background so plusLighter has something to blend
            // against; without it the additive layers don't composite
            // cleanly when nothing else is behind them.
            .background(Color.black)
        }
    }

    private func pseudo(seed: Int, salt: Int) -> Double {
        let h = (seed &* 2654435761) ^ (salt &* 40503)
        return Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
    }
}

// MARK: - Apply helper

extension View {
    // Wraps the view in the chosen post-processing effect. Plain
    // pass-through for `.none` so we don't pay any TimelineView cost
    // when no effect is selected.
    @ViewBuilder
    func postEffect(_ effect: PostEffect, state: AppState) -> some View {
        switch effect {
        case .none:
            self
        case .glitch:
            self.modifier(GlitchModifier(state: state))
        case .tracking:
            self.modifier(TrackingModifier(state: state))
        case .chroma:
            self.modifier(ChromaModifier(state: state))
        }
    }
}
