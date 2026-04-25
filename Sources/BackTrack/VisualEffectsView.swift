import SwiftUI

// Post-processing effects applied as a wrapping layer above the
// entire visuals window — sitting over the synth Canvas, GIF/video
// player, lyric typography, and countdown view alike. Each effect
// is a ViewModifier so callers can apply them with `.modifier(…)`.
//
// Beat-synced behavior reads `state.lastBeatTime` (stamped by Clock
// on every quarter-note advance and during count-in clicks). When
// the song isn't playing, the timestamp stays at .distantPast so
// effects animate freely on wall-clock time instead.
//
// The implementations stick to pure SwiftUI modifiers (no Metal
// shaders) so they work on macOS 13+. That limits us to compositing
// + drawing in Canvas — but blendMode + opacity overlays + jitter
// transforms get most of the way to the desired vibe without a
// custom shader graph.

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
            // 0..1, peaks at the beat, decays over ~180 ms.
            let beatAge = now.timeIntervalSince(state.lastBeatTime)
            let burst = max(0, 1 - beatAge / 0.18)
            // Continuous low-amplitude jitter so the screen still
            // wobbles even between beats / when stopped.
            let idle: Double = 0.08
            // Deterministic per-beat seed so the glitch pattern
            // changes shape every beat instead of looking like the
            // same shake repeating.
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

    // Stable pseudo-random in [-1, 1] given a (seed, axis) pair.
    // Hash mixing is good enough for visual jitter — we don't need
    // cryptographic quality, just non-repeating values per beat.
    private func jitter(seed: Int, axis: Int) -> Double {
        let h = (seed &* 73856093) ^ (axis &* 19349663)
        let normalized = Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
        return normalized * 2 - 1
    }
}

// Horizontal slice flashes that drive most of the "digital corruption"
// vibe. Each slice is a thin rectangle in .difference blend mode, so
// it inverts the colors of whatever's under it for the burst window.
// Slice positions seed off the beat counter so they shift each beat.
private struct GlitchSliceOverlay: View {
    let intensity: Double  // 0..1, beat burst
    let idleIntensity: Double  // tiny baseline slice activity
    let seed: Int

    var body: some View {
        Canvas { ctx, size in
            let total = intensity + idleIntensity
            guard total > 0.01 else { return }

            // Number of slices scales with intensity. At burst peak we
            // get ~6 slices; idle gives 0–1 thin ones.
            let sliceCount = Int(round(intensity * 6 + idleIntensity * 1))
            for i in 0..<sliceCount {
                let r1 = pseudo(seed: seed, salt: i * 7 + 1)
                let r2 = pseudo(seed: seed, salt: i * 7 + 2)
                let r3 = pseudo(seed: seed, salt: i * 7 + 3)
                let y = CGFloat(r1) * size.height
                let h = max(2, CGFloat(r2 * r2) * size.height * 0.06)
                let alpha = 0.4 + r3 * 0.5
                let rect = CGRect(x: 0, y: y, width: size.width, height: h)
                ctx.fill(
                    Path(rect),
                    with: .color(.white.opacity(alpha))
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

// MARK: - Lofi

// Posterize-leaning lofi look — saturation pulled down, a yellowish
// color cast, and a Canvas-drawn grain overlay that re-seeds each
// beat. Pure-SwiftUI posterize isn't possible without a Metal shader
// so we approximate with `.saturation(0.55)` + warm tint + grain;
// the perceived effect is "compressed VHS / printed magazine" which
// matches the linocut aesthetic of the rest of the app.
struct LofiModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { _ in
            // Re-seed grain each beat so the texture shifts on time
            // with the music. Outside of playback / countdown, the
            // grain is still alive (24 fps timeline) but with a
            // stable seed it would look frozen.
            let seed = (state.currentBar * 4 + state.currentBeat) &* 31
                + Int(state.lastBeatTime.timeIntervalSinceReferenceDate * 1000) &* 7

            content
                .saturation(0.55)
                .contrast(1.15)
                .brightness(-0.02)
                .colorMultiply(Color(red: 1.0, green: 0.94, blue: 0.78))
                .overlay(
                    GrainOverlay(seed: seed, density: 0.18, alpha: 0.22)
                        .allowsHitTesting(false)
                        .blendMode(.overlay)
                )
        }
    }
}

private struct GrainOverlay: View {
    let seed: Int
    let density: Double  // 0..1, fraction of cells filled
    let alpha: Double

    var body: some View {
        Canvas { ctx, size in
            // Coarse grain — ~3px cells. Drawing per-pixel grain
            // tanks the framerate, but a chunky cell grid at low
            // alpha reads identically as "film grain".
            let cell: CGFloat = 3
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for r in 0..<rows {
                for c in 0..<cols {
                    let h = (seed &+ r &* 73856093) ^ (c &* 19349663)
                    let v = Double(UInt32(truncatingIfNeeded: h)) / Double(UInt32.max)
                    if v > density { continue }
                    let bright = v / density  // 0..1 inside the cells we draw
                    let rect = CGRect(
                        x: CGFloat(c) * cell,
                        y: CGFloat(r) * cell,
                        width: cell,
                        height: cell
                    )
                    ctx.fill(
                        Path(rect),
                        with: .color(.white.opacity(bright * alpha))
                    )
                }
            }
        }
    }
}

// MARK: - CRT

// Phosphor-glow scanline overlay. Static horizontal scanlines at 3 px
// pitch + a subtle per-beat brightness pulse that mimics the rolling
// brightness artifact you used to see on a tube TV. Pulls saturation
// up slightly so the underlying ink reads with a faint analog warmth.
struct CRTModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let beatAge = context.date.timeIntervalSince(state.lastBeatTime)
            // Brief brightness lift on each beat (~120 ms decay).
            let beatPulse = max(0, 1 - beatAge / 0.12)

            content
                .saturation(1.08)
                .brightness(beatPulse * 0.04)
                .overlay(ScanlineOverlay().allowsHitTesting(false))
                .overlay(VignetteOverlay().allowsHitTesting(false))
        }
    }
}

private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            // 1.5 px dark line every 3 px. Subtle alpha so the
            // underlying image still dominates — scanlines should
            // texture, not occlude.
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1.5)),
                    with: .color(.black.opacity(0.22))
                )
                y += 3
            }
        }
    }
}

private struct VignetteOverlay: View {
    var body: some View {
        // Radial gradient fading to dark at the corners. CRT phosphor
        // tubes always darken in the corners; this sells the look
        // even on a flat LCD.
        RadialGradient(
            colors: [
                Color.black.opacity(0),
                Color.black.opacity(0),
                Color.black.opacity(0.35)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 800
        )
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
        case .lofi:
            self.modifier(LofiModifier(state: state))
        case .crt:
            self.modifier(CRTModifier(state: state))
        }
    }
}
