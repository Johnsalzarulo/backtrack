import SwiftUI

// Full-frame TV snow, used as the "no signal" resting state when the
// app is open but nothing is playing — replaces the blank paper screen
// that used to appear at launch and between songs.
//
// Regenerates at ~15 Hz. Faster feels digital (frame-perfect noise),
// slower feels like a stuttering image. 15 Hz hits the sweet spot that
// reads as analog snow. Theme-aware: dark renders as white flecks on
// black paper, light as black flecks on white.
//
// Intentionally goes edge-to-edge with no overscan inset — static is
// the "signal lost" vibe, and CRT clipping just eats a bit of snow,
// which is harmless.
struct IdleStaticView: View {
    let ink: Color
    let paper: Color

    // Cell size in points. Smaller = finer-grained noise, but more
    // draw calls. 5 pt reads as analog snow on a projector / CRT
    // without blowing the frame budget on large displays.
    private let cellSize: CGFloat = 5
    // Updates per second.
    private let refreshHz: Double = 15
    // Fraction of cells painted in ink (vs paper). 0.5 = classic
    // 50/50 salt-and-pepper TV snow.
    private let density: Double = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / refreshHz)) { context in
            Canvas { ctx, size in
                render(ctx: ctx, size: size, seedDate: context.date)
            }
        }
        .background(paper)
    }

    private func render(ctx: GraphicsContext, size: CGSize, seedDate: Date) {
        let cols = Int(ceil(size.width / cellSize))
        let rows = Int(ceil(size.height / cellSize))
        let frameSeed = Int(seedDate.timeIntervalSince1970 * refreshHz)
        // xorshift32 wants a non-zero state; also mix the frame seed
        // into a large odd constant so consecutive frames diverge fast.
        var state = UInt32(bitPattern: Int32(truncatingIfNeeded: frameSeed &* 2654435761))
        if state == 0 { state = 1 }
        let threshold = UInt32(Double(UInt32.max) * density)
        for y in 0..<rows {
            for x in 0..<cols {
                // xorshift32 — one step per cell, cheap and passes
                // visual uniformity.
                state ^= state << 13
                state ^= state >> 17
                state ^= state << 5
                guard state < threshold else { continue }
                let rect = CGRect(
                    x: CGFloat(x) * cellSize,
                    y: CGFloat(y) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                ctx.fill(Path(rect), with: .color(ink))
            }
        }
    }
}
