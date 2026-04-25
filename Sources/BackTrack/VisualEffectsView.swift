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
struct GlitchModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let now = context.date
            let beatAge = now.timeIntervalSince(state.lastBeatTime)
            let burst = max(0, 1 - beatAge / 0.18)
            let idle: Double = 0.08
            let seed = (state.currentBar * 4 + state.currentBeat)

            content
                .offset(
                    x: CGFloat(jitter(seed: seed, axis: 0) * (burst * 12 + idle * 1.5)),
                    y: CGFloat(jitter(seed: seed, axis: 1) * (burst * 4 + idle * 0.5))
                )
                .saturation(1 + burst * 0.6)
                .hueRotation(.degrees(burst * 18 * jitter(seed: seed, axis: 2)))
                .overlay(
                    GlitchSliceOverlay(intensity: burst, idleIntensity: idle, seed: seed)
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

    var body: some View {
        Canvas { ctx, size in
            let total = intensity + idleIntensity
            guard total > 0.01 else { return }

            let sliceCount = Int(round(intensity * 6 + idleIntensity * 1))
            for i in 0..<sliceCount {
                let r1 = pseudo(seed: seed, salt: i * 7 + 1)
                let r2 = pseudo(seed: seed, salt: i * 7 + 2)
                let r3 = pseudo(seed: seed, salt: i * 7 + 3)
                let y = CGFloat(r1) * size.height
                let h = max(2, CGFloat(r2 * r2) * size.height * 0.06)
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

// VCR tracking artifact. A horizontal band of heavy distortion rolls
// continuously down the screen — that's the iconic "tape head out of
// alignment" look — while the rest of the image gets a light VHS
// treatment (slight desaturation, constant tiny horizontal wobble).
// On every beat the band briefly intensifies, like the tracking is
// breaking worse on the hits.
struct TrackingModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let now = context.date
            let timeRef = now.timeIntervalSinceReferenceDate
            // One full sweep per ~3.5 s. Slow enough to feel "broken
            // tape" rather than "rolling shutter".
            let bandFraction = (timeRef.truncatingRemainder(dividingBy: 3.5)) / 3.5
            // Per-beat distortion bump.
            let beatAge = now.timeIntervalSince(state.lastBeatTime)
            let beatPulse = max(0, 1 - beatAge / 0.25)

            content
                // VHS look on the rest of the image.
                .saturation(0.78)
                .brightness(-0.02)
                // Continuous tiny horizontal wobble — non-beat-synced
                // so it always feels like a slightly worn tape.
                .offset(x: CGFloat(sin(timeRef * 11) * 0.9 + sin(timeRef * 27) * 0.4))
                .overlay(
                    TrackingBandOverlay(
                        bandFraction: bandFraction,
                        beatPulse: beatPulse,
                        timeSeed: Int(timeRef * 60)
                    )
                    .allowsHitTesting(false)
                )
        }
    }
}

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
            let sliceCount = 18 + Int(beatPulse * 10)
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

// MARK: - Chroma

// RGB channel separation. Three offset copies of the underlying
// content — tinted red, green, and blue via colorMultiply, combined
// with `.plusLighter` blend mode (additive) — so at zero offset they
// sum back to the original image exactly. As offset grows the red
// channel shifts left and blue right, giving classic chromatic
// aberration / vintage 3D anaglyph fringing.
//
// Beat-reactive: a small baseline offset is always there for the
// "Spider-Verse" feel, and on each beat the offset bursts outward
// and decays over ~250 ms. Costs 3× the underlying content's render
// budget — that's the price of pure-SwiftUI channel separation
// without Metal shaders.
struct ChromaModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let beatAge = context.date.timeIntervalSince(state.lastBeatTime)
            let pulse = max(0, 1 - beatAge / 0.25)
            // Continuous baseline so the separation never fully closes
            // (otherwise it'd look like the effect is off between beats).
            let baseline: CGFloat = 1.5
            let burst: CGFloat = CGFloat(pulse) * 9
            let offset = baseline + burst

            ZStack {
                content
                    .colorMultiply(.red)
                    .offset(x: -offset)
                    .blendMode(.plusLighter)
                content
                    .colorMultiply(.green)
                    .blendMode(.plusLighter)
                content
                    .colorMultiply(.blue)
                    .offset(x: offset)
                    .blendMode(.plusLighter)
            }
            .compositingGroup()
            // A black background so plusLighter has something to blend
            // against; without it the additive layers don't composite
            // cleanly when nothing else is behind them.
            .background(Color.black)
        }
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
