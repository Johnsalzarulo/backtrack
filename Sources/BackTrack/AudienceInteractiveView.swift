import SwiftUI

// Full-screen audience-driven screen. Each kind has its own visual
// language — start_button rides the song's theme; transmission
// overrides to a phosphor-green CRT terminal palette regardless of
// the current song's theme. The kind switch in `body` keeps the two
// rendering worlds cleanly separated.
struct AudienceInteractiveView: View {
    @EnvironmentObject var state: AppState

    let interactive: AudienceInteractive
    // Theme ink/paper from the surrounding song; only used by
    // start_button. Transmission ignores these in favor of phosphor.
    let ink: Color
    let paper: Color

    // Same overscan inset CountdownView uses — CRTs and projectors
    // clip 5–10% off each edge.
    private let overscanMargin: CGFloat = 0.07
    // Window during which "WRONG BUTTON" replaces the per-kind prompt
    // on start_button.
    private let errorHoldSeconds: TimeInterval = 1.5

    var body: some View {
        switch interactive.kind {
        case .startButton:
            startButtonView
        case .transmission:
            transmissionView
        case .lottery:
            lotteryView
        }
    }

    // MARK: - start_button

    private var startButtonView: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let inError = now.timeIntervalSince(state.wrongButtonAt) < errorHoldSeconds
            GeometryReader { geo in
                let inset = min(geo.size.width, geo.size.height) * overscanMargin
                let safeW = max(0, geo.size.width - inset * 2)
                let safeH = max(0, geo.size.height - inset * 2)
                let safe = min(safeW, safeH)
                let messageFont = safe * 0.13

                ZStack {
                    paper.ignoresSafeArea()
                    VStack {
                        Spacer(minLength: 0)
                        if inError {
                            Text("WRONG BUTTON")
                                .foregroundColor(errorTint)
                                .font(.system(size: messageFont, weight: .light, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .frame(maxWidth: safeW)
                        } else {
                            // "PRESS [green dot] TO\nSTART THE SHOW",
                            // dot tinted green inside the same monospace
                            // block. Two-line layout via VStack so the
                            // break lands cleanly.
                            VStack(spacing: messageFont * 0.05) {
                                let line1 = Text("PRESS ")
                                    + Text("⬤").foregroundColor(.green)
                                    + Text(" TO")
                                line1
                                    .font(.system(size: messageFont, weight: .light, design: .monospaced))
                                    .foregroundColor(ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.4)
                                Text("START THE SHOW")
                                    .font(.system(size: messageFont, weight: .light, design: .monospaced))
                                    .foregroundColor(ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.4)
                            }
                            .frame(maxWidth: safeW)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: safeW, height: safeH)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - transmission

    // Phosphor-green-on-black palette for the entire transmission
    // takeover, independent of the song theme. Reads as a vintage CRT
    // terminal — the right register for the texting fiction.
    private let phosphorInk = Color(red: 0.45, green: 1.0, blue: 0.55)
    private let phosphorPaper = Color.black

    private var transmissionView: some View {
        GeometryReader { geo in
            let inset = min(geo.size.width, geo.size.height) * overscanMargin
            let safeW = max(0, geo.size.width - inset * 2)
            let safeH = max(0, geo.size.height - inset * 2)
            let safe = min(safeW, safeH)

            ZStack {
                phosphorPaper.ignoresSafeArea()
                Group {
                    switch state.transmissionPhase {
                    case .idle:
                        // Pre-init fallback — render the first exchange
                        // directly so the screen is never blank when
                        // the audience first sees it. KeyboardHandler
                        // normally seeds .incoming(firstId, ...) on
                        // cursor arrival; this covers the gap with
                        // the typing animation skipped (charsRevealed
                        // = full).
                        if let first = interactive.transmission?.exchanges.first {
                            transmissionExchangeContent(exchange: first, safe: safe, charsRevealed: first.incoming.count)
                        }
                    case .incoming(let id, let startedAt):
                        if let ex = interactive.transmission?.exchange(id: id) {
                            // TimelineView re-renders each animation
                            // frame so the typing reveal advances
                            // smoothly. Reply prompts are gated on
                            // typing-complete inside the helper.
                            TimelineView(.animation) { context in
                                let elapsed = context.date.timeIntervalSince(startedAt)
                                let revealed = max(0, Int(elapsed / TransmissionPacing.charDuration))
                                transmissionExchangeContent(
                                    exchange: ex,
                                    safe: safe,
                                    charsRevealed: min(revealed, ex.incoming.count)
                                )
                            }
                        }
                    case .replyEcho(let text, _):
                        transmissionEchoContent(text: text, safe: safe)
                    case .preIncomingBlank:
                        EmptyView()  // intentional black beat
                    case .deletedFlash:
                        transmissionDeletedContent(safe: safe)
                    }
                }
                .frame(width: safeW, height: safeH)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func transmissionExchangeContent(
        exchange: TransmissionExchange,
        safe: CGFloat,
        charsRevealed: Int
    ) -> some View {
        let smallHeaderFont = safe * 0.045   // dim header on normal exchanges
        let gateHeaderFont = safe * 0.10     // centerpiece on the opening gate
        let bodyFont = safe * 0.085
        let optionFont = safe * 0.055        // bumped for the stacked layout
        let typingComplete = charsRevealed >= exchange.incoming.count
        // Gate-style exchanges (opening "NEW MESSAGE RECEIVED") have
        // no body — we treat the header as the centerpiece instead
        // of relegating it to a small dim line at the top.
        let isGate = exchange.incoming.isEmpty

        VStack(spacing: safe * 0.04) {
            if !isGate {
                // Top header for normal exchanges — small + dim so
                // the body is the eye-line.
                Text(exchange.header)
                    .font(.system(size: smallHeaderFont, weight: .light, design: .monospaced))
                    .foregroundColor(phosphorInk.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 0)

            if isGate {
                // Centerpiece header — large, full ink, dead-center.
                // This is the opening screen; the audience needs to
                // read this and decide whether to engage at all.
                Text(exchange.header)
                    .font(.system(size: gateHeaderFont, weight: .light, design: .monospaced))
                    .foregroundColor(phosphorInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Body — multi-line preserved exactly. Typing reveal:
                // ZStack with the FULL message rendered transparent
                // underneath so the layout reserves the final height
                // up-front (otherwise reply prompts and surrounding
                // content would jump as more characters appear). The
                // visible Text on top renders only the prefix.
                let visible = String(exchange.incoming.prefix(charsRevealed))
                ZStack {
                    Text(exchange.incoming)
                        .font(.system(size: bodyFont, weight: .light, design: .monospaced))
                        .foregroundColor(.clear)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(visible)
                        .font(.system(size: bodyFont, weight: .light, design: .monospaced))
                        .foregroundColor(phosphorInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            // Bottom area — gated on typing-complete. Three cases:
            //   1. Has reply choices → stacked 🟢/🔴 prompts.
            //   2. No choices but has bottomPrompt → render that
            //      (e.g. "Mash 🔴 and 🟢 to beg" — audience can
            //      press for feedback but nothing advances).
            //   3. Neither → nothing renders at the bottom.
            if typingComplete {
                if exchange.green != nil || exchange.red != nil {
                    // Stacked vertically (🟢 above 🔴) so each line
                    // is a full-width independent reading target.
                    // Extra bottom padding on top of the 7% overscan
                    // keeps the lower line off the bezel curve.
                    VStack(alignment: .center, spacing: optionFont * 0.65) {
                        if let green = exchange.green {
                            choiceLabel(dotColor: .green, label: green.label, font: optionFont)
                        }
                        if let red = exchange.red {
                            choiceLabel(dotColor: .red, label: red.label, font: optionFont)
                        }
                    }
                    .padding(.bottom, safe * 0.05)
                    .frame(maxWidth: .infinity)
                } else if let prompt = exchange.bottomPrompt {
                    bottomPromptLine(prompt, font: optionFont)
                        .padding(.bottom, safe * 0.05)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // Renders a `bottomPrompt` string with 🔴 / 🟢 emoji
    // substituted to colored ⬤ glyphs, matching the rest of the
    // transmission UI. Single dim line, centered, monospace.
    private func bottomPromptLine(_ raw: String, font: CGFloat) -> some View {
        styledPromptText(raw)
            .font(.system(size: font, weight: .light, design: .monospaced))
            .foregroundColor(phosphorInk.opacity(0.75))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
    }

    // Tokenizes the input by character, swapping 🔴 / 🟢 for
    // colored ⬤ runs. Returns a single composed Text so the host
    // can apply font / line-limit / scaling uniformly.
    private func styledPromptText(_ raw: String) -> Text {
        var result = Text("")
        var buffer = ""
        for char in raw {
            let s = String(char)
            if s == "🔴" {
                if !buffer.isEmpty {
                    result = result + Text(buffer)
                    buffer = ""
                }
                result = result + Text("⬤").foregroundColor(.red)
            } else if s == "🟢" {
                if !buffer.isEmpty {
                    result = result + Text(buffer)
                    buffer = ""
                }
                result = result + Text("⬤").foregroundColor(.green)
            } else {
                buffer.append(s)
            }
        }
        if !buffer.isEmpty {
            result = result + Text(buffer)
        }
        return result
    }

    private func choiceLabel(dotColor: Color, label: String, font: CGFloat) -> some View {
        let composed = Text("⬤").foregroundColor(dotColor)
            + Text(" \(label)").foregroundColor(phosphorInk)
        return composed
            .font(.system(size: font, weight: .light, design: .monospaced))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private func transmissionEchoContent(text: String, safe: CGFloat) -> some View {
        let headerFont = safe * 0.045
        let bodyFont = safe * 0.07
        VStack(spacing: safe * 0.04) {
            Spacer(minLength: 0)
            Text("YOU SENT")
                .font(.system(size: headerFont, weight: .light, design: .monospaced))
                .foregroundColor(phosphorInk.opacity(0.55))
            Text(text)
                .font(.system(size: bodyFont, weight: .light, design: .monospaced))
                .foregroundColor(phosphorInk)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .minimumScaleFactor(0.4)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func transmissionDeletedContent(safe: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text("DELETED")
                .font(.system(size: safe * 0.10, weight: .light, design: .monospaced))
                .foregroundColor(phosphorInk)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
        }
    }

    // Error tint for start_button's "WRONG BUTTON" overlay. Saturated
    // red regardless of theme — "WRONG" reads universally.
    private var errorTint: Color {
        Color(red: 1.0, green: 0.25, blue: 0.25)
    }

    // MARK: - lottery
    //
    // Black-background 8-bit takeover. Independent of the song's theme
    // (like transmission) — the bit's visual language is a NES-era
    // game show, not the surrounding song's palette. Phase switch in
    // `lotteryView` drives the six-screen sequence:
    //
    //   setup       → "CONGRATULATIONS! YOU HAVE A CHANCE TO SPIN..."
    //   wheel       → static wheel + "PRESS TO SPIN"
    //   spinning    → wheel rotating per LotteryPacing.spinAngle
    //   resultPending → wheel at rest, landed slice pulsing
    //   revealIntro → text-only "CONGRATULATIONS! / YOU HAVE WON..."
    //   prizeDisplay → big yellow prize text
    //   fading      → prizeDisplay with black overlay fading in
    //
    // Each phase carries its own `startedAt` so this view can drive
    // the spin angle, the pulse on the landed slice, and the fade
    // opacity off `now - startedAt` without storing any local state.

    private var lotteryView: some View {
        let slices = interactive.lottery?.sliceCount ?? 0
        return TimelineView(.animation) { context in
            let now = context.date
            GeometryReader { geo in
                let inset = min(geo.size.width, geo.size.height) * overscanMargin
                let safeW = max(0, geo.size.width - inset * 2)
                let safeH = max(0, geo.size.height - inset * 2)
                let safe = min(safeW, safeH)

                ZStack {
                    Color.black.ignoresSafeArea()
                    Group {
                        switch state.lotteryPhase {
                        case .idle:
                            // Pre-init fallback — cursor seeding moves
                            // us to .setup within a frame; this just
                            // keeps the screen non-blank in the gap.
                            lotterySetupContent(now: now, startedAt: now, safe: safe)
                        case .setup(let startedAt):
                            lotterySetupContent(now: now, startedAt: startedAt, safe: safe)
                        case .wheel:
                            lotteryWheelContent(
                                rotation: 0,
                                highlight: nil,
                                pulseElapsed: 0,
                                safe: safe,
                                slices: slices,
                                showPrompt: true
                            )
                        case .spinning(let landing, let startedAt):
                            let elapsed = now.timeIntervalSince(startedAt)
                            let rotation = LotteryPacing.spinAngle(
                                elapsed: elapsed,
                                landing: landing,
                                slices: slices
                            )
                            lotteryWheelContent(
                                rotation: rotation,
                                highlight: nil,
                                pulseElapsed: 0,
                                safe: safe,
                                slices: slices,
                                showPrompt: false
                            )
                        case .resultPending(let landing, let startedAt):
                            // Math: wheel rests at thetaFinal mod 2π =
                            // (landing/slices) × 2π, the same as the
                            // last value spinAngle would produce. The
                            // landed slice pulses with elapsed time.
                            let landAngle = (slices > 0)
                                ? 2 * Double.pi * Double(landing) / Double(slices)
                                : 0
                            let pulse = now.timeIntervalSince(startedAt)
                            lotteryWheelContent(
                                rotation: landAngle,
                                highlight: landing,
                                pulseElapsed: pulse,
                                safe: safe,
                                slices: slices,
                                showPrompt: false
                            )
                        case .revealIntro:
                            lotteryRevealIntroContent(safe: safe)
                        case .prizeDisplay(let prize, _):
                            lotteryPrizeContent(prize: prize, safe: safe)
                        case .fading(let prize, let startedAt):
                            let t = now.timeIntervalSince(startedAt) / LotteryPacing.fadingSeconds
                            let opacity = min(1, max(0, t))
                            lotteryPrizeContent(prize: prize, safe: safe)
                                .overlay(
                                    Color.black.opacity(opacity).allowsHitTesting(false)
                                )
                        }
                    }
                    .frame(width: safeW, height: safeH)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // Setup screen: triumphant text plus flashing stars at top/bottom
    // (rate ~2.5 Hz so the "celebration energy" reads at a glance,
    // not seizure-tier). Audience-facing green-dot CONTINUE hint
    // sits beneath the body copy.
    @ViewBuilder
    private func lotterySetupContent(now: Date, startedAt: Date, safe: CGFloat) -> some View {
        let starsOn = Int(now.timeIntervalSince(startedAt) / 0.4) % 2 == 0
        VStack(spacing: safe * 0.03) {
            Spacer(minLength: 0)
            lotteryStarRow(safe: safe, visible: starsOn)
            Spacer().frame(height: safe * 0.04)
            Text("CONGRATULATIONS!")
                .font(.system(size: safe * 0.10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Spacer().frame(height: safe * 0.02)
            Text("YOU HAVE A CHANCE TO")
                .font(.system(size: safe * 0.06, weight: .light, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("SPIN THE WHEEL")
                .font(.system(size: safe * 0.06, weight: .light, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer().frame(height: safe * 0.04)
            lotteryStarRow(safe: safe, visible: starsOn)
            Spacer().frame(height: safe * 0.05)
            (Text("⬤").foregroundColor(.green) + Text("  CONTINUE").foregroundColor(.white))
                .font(.system(size: safe * 0.045, weight: .light, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // Pixel-star decoration row, used at the top and bottom of every
    // text-only lottery screen. `visible: false` keeps the slot but
    // hides the glyphs — drives the celebratory flicker on the setup
    // screen without making text reflow when the stars vanish.
    @ViewBuilder
    private func lotteryStarRow(safe: CGFloat, visible: Bool = true) -> some View {
        Text("★  ★  ★")
            .font(.system(size: safe * 0.09, weight: .heavy, design: .monospaced))
            .foregroundColor(.yellow.opacity(visible ? 1.0 : 0.0))
            .lineLimit(1)
    }

    // Wheel screen — wheel centered with the optional press prompt
    // beneath. Used for both the static `.wheel` phase (showPrompt =
    // true) and the animated `.spinning` / `.resultPending` phases
    // (showPrompt = false), so the prompt only displays when the
    // audience is actually expected to press.
    @ViewBuilder
    private func lotteryWheelContent(
        rotation: Double,
        highlight: Int?,
        pulseElapsed: TimeInterval,
        safe: CGFloat,
        slices: Int,
        showPrompt: Bool
    ) -> some View {
        let wheelSize = safe * 0.68
        VStack(spacing: safe * 0.04) {
            Spacer(minLength: 0)
            lotteryWheel(
                wheelSize: wheelSize,
                rotation: rotation,
                highlight: highlight,
                pulseElapsed: pulseElapsed,
                slices: slices
            )
            if showPrompt {
                Spacer().frame(height: safe * 0.04)
                (Text("⬤").foregroundColor(.green) + Text("  PRESS TO SPIN").foregroundColor(.white))
                    .font(.system(size: safe * 0.05, weight: .light, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
    }

    // The wheel itself. Canvas-drawn N-slice pie with a black border
    // on each slice; the whole canvas rotates by `rotation` while a
    // static white triangle indicator floats above the wheel pointing
    // down at the top of the rim. Highlighting (the landed slice
    // pulses for the resultPending beat) is done by attenuating
    // every OTHER slice's fill opacity in time with the pulse — the
    // winner stays full-color, the field dims.
    private func lotteryWheel(
        wheelSize: CGFloat,
        rotation: Double,
        highlight: Int?,
        pulseElapsed: TimeInterval,
        slices: Int
    ) -> some View {
        // Pulse factor 0..1, oscillates ~3 Hz. When highlight is set,
        // the non-winning slices dim to (1 - pulse * dimAmount); when
        // pulse is high, the winner pops by contrast.
        let pulse = (sin(pulseElapsed * Double.pi * 6) + 1) / 2  // 0..1
        let dimAmount: Double = 0.55  // how dark non-winning slices get at peak
        return ZStack {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 4
                guard slices > 0 else { return }
                let twoPi = 2 * Double.pi
                let half = Double.pi / Double(slices)
                for i in 0..<slices {
                    // Slices arranged counterclockwise from top (slice
                    // 0 at -π/2). A clockwise rotation by k·(2π/N)
                    // brings slice k to top — matches startLotterySpin's
                    // landing math.
                    let centerAngle = -Double.pi / 2 - Double(i) * twoPi / Double(slices)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(
                        x: center.x + radius * cos(centerAngle - half),
                        y: center.y + radius * sin(centerAngle - half)
                    ))
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .radians(centerAngle - half),
                        endAngle: .radians(centerAngle + half),
                        clockwise: false
                    )
                    path.closeSubpath()

                    let base = lotterySliceColor(i)
                    let opacity: Double
                    if let h = highlight, h != i {
                        opacity = 1.0 - pulse * dimAmount
                    } else {
                        opacity = 1.0
                    }
                    ctx.fill(path, with: .color(base.opacity(opacity)))
                    ctx.stroke(path, with: .color(.black), lineWidth: 2)
                }
                // Center hub — a small dark disc that hides the
                // wedges' sharp inner points and reads as classic
                // prize-wheel hardware.
                let hubRadius = radius * 0.08
                let hub = Path(ellipseIn: CGRect(
                    x: center.x - hubRadius,
                    y: center.y - hubRadius,
                    width: hubRadius * 2,
                    height: hubRadius * 2
                ))
                ctx.fill(hub, with: .color(.black))
                ctx.stroke(hub, with: .color(.white), lineWidth: 1.5)
            }
            .frame(width: wheelSize, height: wheelSize)
            .rotationEffect(.radians(rotation))

            // Indicator triangle — white with black outline, point
            // down, perched at the top of the wheel pointing onto it.
            // Drawn OUTSIDE the rotation effect so it stays fixed.
            indicatorTriangle
                .frame(width: wheelSize * 0.10, height: wheelSize * 0.10)
                .offset(y: -wheelSize / 2 + wheelSize * 0.05)
        }
        .frame(width: wheelSize, height: wheelSize)
    }

    // Pointer triangle at the top of the wheel. Tip at bottom-center
    // of its frame so positioning the frame just above the wheel's
    // top edge makes the tip point INTO the wheel rim.
    private var indicatorTriangle: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: size.height))   // bottom tip
            path.addLine(to: CGPoint(x: 0, y: 0))                       // top-left
            path.addLine(to: CGPoint(x: size.width, y: 0))              // top-right
            path.closeSubpath()
            ctx.fill(path, with: .color(.white))
            ctx.stroke(path, with: .color(.black), lineWidth: 2)
        }
    }

    // 9-entry saturated palette tuned for the NES-era feel. Cycles
    // if the wheel has more than 9 slices; adjacency rarely
    // matters above 9 in practice.
    private func lotterySliceColor(_ i: Int) -> Color {
        let palette: [Color] = [
            Color(red: 1.00, green: 0.18, blue: 0.18),  // red
            Color(red: 1.00, green: 0.55, blue: 0.10),  // orange
            Color(red: 1.00, green: 0.93, blue: 0.00),  // yellow
            Color(red: 0.10, green: 0.85, blue: 0.20),  // green
            Color(red: 0.00, green: 0.88, blue: 0.85),  // cyan
            Color(red: 0.10, green: 0.40, blue: 1.00),  // blue
            Color(red: 0.55, green: 0.10, blue: 0.85),  // purple
            Color(red: 1.00, green: 0.20, blue: 0.85),  // magenta
            Color(red: 1.00, green: 0.55, blue: 0.78),  // pink
        ]
        return palette[((i % palette.count) + palette.count) % palette.count]
    }

    // "CONGRATULATIONS! / YOU HAVE WON..." text screen. No prize
    // yet — that's the next phase. Stars are static (no flash) here
    // so the eye reads the text cleanly.
    @ViewBuilder
    private func lotteryRevealIntroContent(safe: CGFloat) -> some View {
        VStack(spacing: safe * 0.03) {
            Spacer(minLength: 0)
            lotteryStarRow(safe: safe)
            Spacer().frame(height: safe * 0.04)
            Text("CONGRATULATIONS!")
                .font(.system(size: safe * 0.10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Spacer().frame(height: safe * 0.02)
            Text("YOU HAVE WON...")
                .font(.system(size: safe * 0.07, weight: .light, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer().frame(height: safe * 0.06)
            lotteryStarRow(safe: safe)
            Spacer(minLength: 0)
        }
    }

    // Final result screen — big yellow prize text framed by the
    // celebratory chrome. Held long enough (6 s) for the audience
    // to read it, recognize themselves in it, and sit with it; do
    // not shorten this beat — it's the bit's payload.
    @ViewBuilder
    private func lotteryPrizeContent(prize: String, safe: CGFloat) -> some View {
        VStack(spacing: safe * 0.025) {
            Spacer(minLength: 0)
            lotteryStarRow(safe: safe)
            Spacer().frame(height: safe * 0.02)
            Text("CONGRATULATIONS!")
                .font(.system(size: safe * 0.08, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text("YOU HAVE WON...")
                .font(.system(size: safe * 0.05, weight: .light, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer().frame(height: safe * 0.04)
            Text(prize)
                .font(.system(size: safe * 0.11, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: safe * 0.04)
            lotteryStarRow(safe: safe)
            Spacer(minLength: 0)
        }
    }
}
