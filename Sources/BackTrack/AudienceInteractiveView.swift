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
}
