import SwiftUI
import AppKit

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
// follows the song's visualizer field (`.constellation` default).
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
        let baseContent = ZStack {
            if state.telemetryVisible
                && state.currentSong != nil
                && state.activeVideoClip == nil {
                // Audience tapped the green button during a song (and
                // not during a videoClip moment, where the clip owns
                // the visuals). Telemetry takes the entire window —
                // no synth, no GIF, no post-effect, no audience flash
                // — for the duration of the auto-hide timer or until
                // the audience taps again to dismiss early.
                TelemetryView()
            } else if let countdown = state.currentCountdown {
                // Current lineup item is a countdown — its dedicated
                // UI (label + timer + progress + message) takes over
                // the entire visuals window. Bypasses the synth /
                // GIF / lyric layers, which only apply to songs.
                CountdownView(
                    countdown: countdown,
                    transport: state.countdownTransport,
                    style: state.effectiveCountdownStyle,
                    messageOffset: state.countdownMessageOffset,
                    ink: ink,
                    paper: paper
                )
            } else if let inter = state.currentInterstitial {
                // Current lineup item is an interstitial — render
                // text / image / video full-bleed depending on kind.
                interstitialContent(inter)
            } else if let interactive = state.currentAudienceInteractive {
                // Current lineup item is an audience-interactive
                // piece (e.g. the start-button gate). Full-bleed
                // takeover with the same monospace / themed aesthetic
                // the countdown uses.
                AudienceInteractiveView(
                    interactive: interactive,
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
            } else if let clip = state.activeVideoClip {
                // Active part has a `videoClip` set. Plays once,
                // sitting above the visuals layer for its duration.
                // When done, Clock clears state.activeVideoClip and we
                // fall back into the normal visuals branches below.
                //
                // The preview thumbnail in the HUD also renders the
                // clip (so the performer sees the same thing the
                // audience sees), but with volume forced to 0 — the
                // main visuals window owns the audio for the clip,
                // and we don't want a second AVPlayer playing the
                // soundtrack on top of itself. Only the main-window
                // instance fires `onFinish`; the preview's callback
                // is a no-op so the lifecycle stays single-sourced.
                VideoClipView(
                    url: clip,
                    volume: isPreview ? 0 : state.activeVideoClipVolume,
                    onFinish: isPreview ? {} : { state.activeVideoClip = nil }
                )
            } else if let url = state.currentPartVisualURL {
                // Part has a visual — GIF/image/video takes over. Keeps
                // playing even when transport is stopped, matching the
                // loop behavior of the source media.
                VisualView(url: url)
            } else if !state.isPlaying {
                // No part-level visual and transport is stopped — the
                // synth layer would be empty, so show TV static as the
                // idle / "no signal" state instead. Also covers app
                // launch, between songs, and any pause.
                IdleStaticView(ink: ink, paper: paper)
            } else {
                // Playing the synth layer.
                GeometryReader { geo in
                    let inset = min(geo.size.width, geo.size.height) * overscanMargin
                    synthContent
                        .padding(inset)
                }
            }
        }
        .background(paper)

        // Wrap with the active post-processing effect (glitch / lofi
        // / crt / none). `.none` is a pass-through, so we don't pay
        // any TimelineView cost when no effect is selected. While
        // telemetry is up the panel must read clean — force .none
        // so an in-flight effect override doesn't tear the readout.
        let activeEffect: PostEffect = state.telemetryVisible
            ? .none
            : state.effectiveVisualEffect
        let postEffected = baseContent.postEffect(activeEffect, state: state)

        // Audience-feedback flash. Sits ABOVE the post-effect layer so
        // the white pop itself isn't itself glitched/chroma'd — it
        // reads as a clean "your press registered" beat regardless of
        // which effect was just triggered. Suppressed while telemetry
        // is on screen so an in-flight flash from a "1" press a moment
        // ago doesn't wash out the panel as it appears.
        let content = ZStack {
            postEffected
            if !state.telemetryVisible {
                audienceFlashOverlay
            }
        }

        if isPreview {
            // Embedded in HUD — skip the window-level modifiers so the
            // HUD's appearance/disappearance doesn't trigger the
            // "window closed" handler.
            content
        } else {
            content
                .ignoresSafeArea()
                .background(
                    // Configure the hosting NSWindow for fullscreen use
                    // — SwiftUI's secondary `Window` scene on macOS 13
                    // doesn't reliably set `.fullScreenPrimary` in the
                    // collection behavior, which makes both F (our
                    // hotkey) and the View > Enter Full Screen menu
                    // item silently no-op. Forcing it on appearance
                    // ensures both routes work.
                    WindowConfigurator { window in
                        window.collectionBehavior.insert(.fullScreenPrimary)
                        window.styleMask.insert(.resizable)
                    }
                )
                .onDisappear {
                    // Window was closed (either via X or programmatic
                    // dismiss). Reflect in state so the next V press
                    // re-opens cleanly.
                    state.visualsOpen = false
                }
        }
    }

    // White overlay layer that fades from full opacity to zero over
    // ~1s after each audience "1" press during a song. Driven by
    // TimelineView so opacity decays continuously without us managing
    // an animation. Sits above the post-effect layer so the flash
    // itself isn't glitched/chroma'd — the audience needs an
    // unambiguous "yes, that registered" beat.
    @ViewBuilder
    private var audienceFlashOverlay: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(state.audienceFlashTriggeredAt)
            // Linear fade over a half-second window. Outside that
            // window the rectangle is fully transparent, so it costs
            // nothing visually — TimelineView still ticks but the GPU
            // draws an alpha-zero rect.
            let opacity = max(0, min(1, 1 - elapsed / 0.5))
            Rectangle()
                .fill(Color.white)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }

    // Render an interstitial (text / image / video) full-bleed in the
    // visuals window. Each kind uses an existing display primitive:
    //   - text  → LyricsBlockView (auto-fit large monospace, theme-tinted)
    //   - image → VisualView (CSS-cover image/GIF rendering)
    //   - video → VideoClipView (with audio + loop awareness)
    // Theme is sourced from the interstitial itself, not the song's,
    // since interstitials are between-song and have their own intent.
    @ViewBuilder
    private func interstitialContent(_ inter: Interstitial) -> some View {
        let interInk: NSColor = inter.theme == .dark ? .white : .black
        let interPaper: NSColor = inter.theme == .dark ? .black : .white
        switch inter.kind {
        case .text:
            LyricsBlockView(
                text: inter.text ?? "",
                ink: interInk,
                paper: interPaper
            )
        case .image:
            if let name = inter.image,
               let url = interstitialImageURL(filename: name) {
                VisualView(url: url)
            } else {
                // Image file missing — fall back to TV static so the
                // performer can see something's wrong without a crash.
                IdleStaticView(
                    ink: Color(nsColor: interInk),
                    paper: Color(nsColor: interPaper)
                )
            }
        case .video:
            if let name = inter.video,
               let url = VideoClipsLibrary.url(for: name) {
                // Loop=true → keep replaying until nav-away.
                // Loop=false → onFinish triggers nav-forward.
                // Volume is preview-suppressed like videoClip so the
                // HUD's small thumbnail mirrors the visuals without
                // doubling the audio.
                VideoClipView(
                    url: url,
                    volume: isPreview ? 0 : Float(inter.volume) / 100.0,
                    loop: inter.loop,
                    onFinish: {
                        if !isPreview && !inter.loop {
                            state.advanceLineupCursor?()
                        }
                    }
                )
            } else {
                IdleStaticView(
                    ink: Color(nsColor: interInk),
                    paper: Color(nsColor: interPaper)
                )
            }
        }
    }

    // Resolve an interstitial's image filename to a URL under the
    // existing Visuals/ directory (same convention as part-level
    // visuals — keeps file management simple).
    private func interstitialImageURL(filename: String) -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Visuals")
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Synth-layer content — geometric motifs render into a Canvas;
    // lyric motifs render typographically via SwiftUI / NSTextView.
    @ViewBuilder
    private var synthContent: some View {
        switch visualizer {
        case .constellation, .orbit, .ink, .squares, .dots, .lines, .ripple, .oscilloscope:
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
        case .oscilloscope:
            renderOscilloscope(ctx: ctx, size: size, minDim: minDim, time: time, now: now)
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
    // paths — inner orbits run faster. Bodies are always visible. On
    // each trigger they SLAM bigger (×2.8 peak) and punch toward the
    // center (radial throw), then both decay smoothly back to resting
    // size + radius — gives every beat a visible burst of motion. The
    // outermost ring doubles as a progress arc showing how far through
    // the current part we are.
    private func renderOrbit(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Outer progress ring. Thin outline of the whole circle plus
        // a thicker arc filled to the current playback fraction.
        drawProgressRing(ctx: ctx, center: center, radius: minDim * 0.56, minDim: minDim)

        // Per-voice pulse envelopes — smooth decay tails so each hit
        // creates a visible swell rather than a binary scale snap.
        let kickPulse  = pulseEnvelope(last: state.kickLastTrigger,  now: now, decay: kickVisualDecay)
        let snarePulse = pulseEnvelope(last: state.snareLastTrigger, now: now, decay: snareVisualDecay)
        let hhPulse    = pulseEnvelope(last: state.hhLastTrigger,    now: now, decay: hhVisualDecay)
        let bassPulse  = pulseEnvelope(last: state.bassLastTrigger,  now: now, decay: bassVisualDecay)
        let padPulse   = pulseEnvelope(last: state.padLastTrigger,   now: now, decay: padVisualDecay)

        // Single-body voices. (radius, body radius, period, seed, pulse).
        // Periods are ~40% faster than the original tuning so bodies
        // visibly travel between beats at typical 90-140 BPM rather
        // than crawling.
        let bodies: [(CGFloat, CGFloat, Double, Int, CGFloat)] = [
            (0.14, 0.055, 4.0, 11, kickPulse),
            (0.22, 0.040, 6.0, 23, snarePulse),
            (0.30, 0.028, 8.0, 61, hhPulse),
            (0.40, 0.045, 12.0, 41, bassPulse)
        ]
        // Throw amount: how far the body punches toward center on a hit.
        // Fraction of minDim, scaled by the pulse — so the body returns
        // to its orbit smoothly as the pulse decays.
        let throwFrac: CGFloat = 0.045
        for (rFrac, bodyFrac, period, seed, pulse) in bodies {
            // Radial throw — a kick visibly snaps the body inward and
            // it returns over the pulse decay.
            let orbitR = minDim * (rFrac - throwFrac * pulse)
            let pos = orbitPosition(time: time, center: center, radius: orbitR, period: period, phase: Double(seed) * 0.1)
            // Scale: 1.0 at rest → 2.8 at peak, smooth decay.
            let body = minDim * bodyFrac * (1.0 + 1.8 * pulse)
            let blob = chiseledBlob(center: pos, baseRadius: body, time: time, jitter: body * 0.08, seed: seed, points: 28)
            ctx.fill(blob, with: .color(ink))
        }

        // Pad — 1, 2, or 3 bodies depending on pad level, evenly
        // distributed around the outermost orbit (but inside the
        // progress ring). Period also sped up so the cluster moves
        // visibly across a song's lifetime.
        let padBodies = max(1, padCount() / 2)       // 4/6/8 → 2/3/4
        let padR = minDim * (0.48 - throwFrac * padPulse)
        let padBodySize = minDim * 0.033 * (1.0 + 1.8 * padPulse)
        for i in 0..<padBodies {
            let orbitPhase = Double(i) / Double(padBodies)
            let pos = orbitPosition(time: time, center: center, radius: padR, period: 16.0, phase: orbitPhase)
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

    // Same shape as inkForce but typed for the geometric styles
    // (orbit, dots) that scale CGFloat sizes / offsets. Returns 1.0
    // at the trigger frame and decays linearly to 0 over `decay`
    // seconds — gives the orbit bodies + dots a smooth visual tail
    // off each hit instead of binary on/off.
    private func pulseEnvelope(last: Date, now: Date, decay: Double) -> CGFloat {
        let elapsed = now.timeIntervalSince(last)
        if elapsed < 0 || elapsed >= decay { return 0 }
        return CGFloat(1.0 - (elapsed / decay))
    }

    // Visual-only decay windows — extended past the audio hold values
    // so the screen has a tail of motion off each beat. Keeping the
    // audio-side `kickHold` etc. unchanged because they're tuned for
    // distinct hit-counting (e.g. "is the kick still firing on this
    // tick?"); these visual decays are tuned for "how long should the
    // eye still see the trigger."
    private var kickVisualDecay: TimeInterval  { 0.45 }
    private var snareVisualDecay: TimeInterval { 0.35 }
    private var hhVisualDecay: TimeInterval    { 0.20 }
    private var bassVisualDecay: TimeInterval  { 0.55 }
    private var padVisualDecay: TimeInterval   { 1.00 }

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
    // dots at fixed angles for the pad. Dots snap on at full size on
    // each trigger and *shrink-decay* back to invisible over the
    // voice's visual decay window — gives the screen a visible tail
    // of motion off every beat instead of binary appear/disappear.
    private func renderDots(ctx: GraphicsContext, center: CGPoint, minDim: CGFloat, time: Double, now: Date) {
        // Per-voice pulse envelopes (1.0 at trigger, decays to 0).
        let kickPulse  = pulseEnvelope(last: state.kickLastTrigger,  now: now, decay: kickVisualDecay)
        let snarePulse = pulseEnvelope(last: state.snareLastTrigger, now: now, decay: snareVisualDecay)
        let hhPulse    = pulseEnvelope(last: state.hhLastTrigger,    now: now, decay: hhVisualDecay)
        let bassPulse  = pulseEnvelope(last: state.bassLastTrigger,  now: now, decay: bassVisualDecay)
        let padPulse   = pulseEnvelope(last: state.padLastTrigger,   now: now, decay: padVisualDecay)

        // Pad — scattered dots at golden-ratio angles around the orbit.
        // Dots inflate on trigger and shrink to nothing as pad decays.
        if padPulse > 0 {
            let count = padCount()
            let orbitR = minDim * 0.42
            let dotR = minDim * 0.022 * padPulse
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
        // Bass — ring of 12 small dots at ~38% radius. Each dot scales
        // with the bass pulse so the whole ring grows + shrinks.
        if bassPulse > 0 {
            dotRing(ctx: ctx, center: center, radius: minDim * 0.38, dotRadius: minDim * 0.014 * bassPulse, count: 12, time: time, seedBase: 700)
        }
        // HH — tight ring of 8 tiny dots at ~11% radius.
        if hhPulse > 0 {
            dotRing(ctx: ctx, center: center, radius: minDim * 0.11, dotRadius: minDim * 0.008 * hhPulse, count: 8, time: time, seedBase: 800)
        }
        // Kick — big filled dot in the center, scales 0 → full → 0.
        if kickPulse > 0 {
            let r = minDim * 0.22 * kickPulse
            let dot = chiseledBlob(center: center, baseRadius: r, time: time, jitter: r * 0.06, seed: 11, points: 56)
            ctx.fill(dot, with: .color(ink))
        }
        // Snare — smaller filled dot.
        if snarePulse > 0 {
            let r = minDim * 0.075 * snarePulse
            let dot = chiseledBlob(center: center, baseRadius: r, time: time, jitter: r * 0.07, seed: 23, points: 40)
            ctx.fill(dot, with: .color(ink))
        }
    }

    // Helper used by dots-style bass + hh: N small filled dots arranged
    // on a circle of the given radius. The caller scales `dotRadius`
    // by the voice's pulse envelope so the ring naturally fades.
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

    // MARK: - Style: oscilloscope

    // Full-bleed CRT-style scope. Each voice contributes a sine wave
    // at its own characteristic frequency, weighted by its current
    // pulse envelope; the trace is the running sum, drawn over a 4×6
    // grid like an actual instrument display.
    //
    // Why this design: a real oscilloscope monitoring a band's stem
    // bus would show the kick as a low-frequency thump, the bass as
    // a sustained mid wave, the snare as a sharper mid-high transient,
    // and the hh as fast jitter — all riding on whatever pad pitch
    // is currently sustained. We simulate that, summing per-voice
    // sines at proportionally chosen frequencies and amplitudes. The
    // result reads as "I can see the song breathing" rather than as
    // five separate light-up indicators.
    //
    // Theme-aware: trace + grid use the song's ink color, paper for
    // background, so the scope flips clean between dark phosphor-style
    // (white-on-black) and light schematic-style (black-on-white).
    private func renderOscilloscope(ctx: GraphicsContext, size: CGSize, minDim: CGFloat, time: Double, now: Date) {
        // Grid first so the trace renders over it.
        drawScopeGrid(ctx: ctx, size: size, minDim: minDim)

        // Per-voice pulse envelopes. Same decay windows the orbit /
        // dots styles use so the visual response timings line up.
        let kp = pulseEnvelope(last: state.kickLastTrigger,  now: now, decay: kickVisualDecay)
        let sp = pulseEnvelope(last: state.snareLastTrigger, now: now, decay: snareVisualDecay)
        let hp = pulseEnvelope(last: state.hhLastTrigger,    now: now, decay: hhVisualDecay)
        let bp = pulseEnvelope(last: state.bassLastTrigger,  now: now, decay: bassVisualDecay)
        let pp = pulseEnvelope(last: state.padLastTrigger,   now: now, decay: padVisualDecay)

        // Scrolling phase based on wall-clock so the trace never sits
        // perfectly still even at idle — like a CRT running unlocked.
        let scrollPhase = time * 0.8
        // Pad uses a slow secondary phase so its component drifts on
        // its own timeline relative to the percussive voices.
        let padPhase = time * 0.4

        let samples = 320  // ~screen-width density — small enough that
                           // pathing is cheap, big enough that high-freq
                           // hh component renders without aliasing.
        let amplitude = size.height * 0.32
        let centerY = size.height / 2
        // 6 cycles of the slowest (kick) component fit across screen.
        let baseCycles: Double = 6

        var path = Path()
        for i in 0..<samples {
            let frac = Double(i) / Double(samples - 1)
            let x = frac * Double(size.width)
            let phase = frac * 2 * .pi * baseCycles + scrollPhase

            // Sum each voice's sine at its frequency multiplier,
            // amplitude × current pulse envelope.
            var y = 0.0
            y += Double(kp) * sin(phase * 1.0) * 0.60      // kick: low + slow (×1)
            y += Double(bp) * sin(phase * 2.0) * 0.50      // bass: low-mid (×2)
            y += Double(pp) * sin(phase * 0.5 + padPhase) * 0.35  // pad: very slow (×0.5), drifts
            y += Double(sp) * sin(phase * 5.0) * 0.40      // snare: medium-fast (×5)
            y += Double(hp) * sin(phase * 22.0) * 0.25     // hh: high jitter (×22)

            // Tiny baseline hiss so the trace never reads dead-flat —
            // serves the same role as CRT phosphor noise floor.
            let noise = (sin(phase * 47 + time * 13) + cos(phase * 73 + time * 17)) * 0.015
            y += noise

            // Clamp into the drawable band so big simultaneous hits
            // don't draw past the grid — clipping reads better than
            // an off-screen trace.
            let clamped = max(-1.0, min(1.0, y))
            let yPos = centerY + CGFloat(clamped) * amplitude
            let pt = CGPoint(x: CGFloat(x), y: yPos)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }

        // Phosphor glow underlay — wider, dimmer pass beneath the
        // sharp trace gives the line a soft halo that reads as CRT
        // bloom in dark mode and as a heavier ink stroke in light.
        ctx.stroke(
            path,
            with: .color(ink.opacity(0.25)),
            style: StrokeStyle(lineWidth: minDim * 0.014, lineCap: .round, lineJoin: .round)
        )
        // Sharp main trace.
        ctx.stroke(
            path,
            with: .color(ink),
            style: StrokeStyle(lineWidth: minDim * 0.005, lineCap: .round, lineJoin: .round)
        )
    }

    // Draws the scope's reticle: a 4×6 grid of dim ink lines, with the
    // mid-horizontal "0V" line slightly stronger, plus a thin viewport
    // outline. Scaled off minDim so the line widths feel right at any
    // window size.
    private func drawScopeGrid(ctx: GraphicsContext, size: CGSize, minDim: CGFloat) {
        let dim = ink.opacity(0.18)
        let mid = ink.opacity(0.40)
        let lw = max(0.5, minDim * 0.001)

        // Horizontal divisions — 4 cells = 5 lines, edges drawn by
        // the outer rect below.
        let hDivs = 4
        for i in 1..<hDivs {
            let y = size.height * CGFloat(i) / CGFloat(hDivs)
            let isMid = i == hDivs / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(isMid ? mid : dim), lineWidth: lw)
        }
        // Vertical divisions — 6 cells.
        let vDivs = 6
        for i in 1..<vDivs {
            let x = size.width * CGFloat(i) / CGFloat(vDivs)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(dim), lineWidth: lw)
        }
        // Viewport outline so the "scope" reads as a contained instrument.
        let frame = Path(CGRect(origin: .zero, size: size))
        ctx.stroke(frame, with: .color(ink.opacity(0.30)), lineWidth: lw * 1.5)
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

// Bridges back to AppKit so we can configure the hosting NSWindow
// once it's available. SwiftUI doesn't expose collectionBehavior or
// styleMask on its Window scene, so this is the path for guaranteeing
// fullscreen capability is set on the visuals window.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // view.window is nil at makeNSView time — defer until SwiftUI
        // has parented this NSView into the window's content view.
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }
}
