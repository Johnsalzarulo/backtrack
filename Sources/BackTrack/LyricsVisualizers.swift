import SwiftUI
import AppKit

// Typographic visualizer views — the alternative to the geometric
// motifs (sun / squares / dots / etc.). Both lyric motifs render the
// current part's `lyrics` field in light-weight monospace ink on
// paper, following the active theme.

// MARK: - Block / Line (both auto-fit justified paragraphs)

// Renders some chunk of lyric text — either the entire part (block
// mode) or a single line of it (line mode) — as a justified paragraph
// that auto-fits to the frame. Font size binary-searches so the text
// fills the frame edge to edge.
struct LyricsBlockView: NSViewRepresentable {
    let text: String
    let ink: NSColor
    let paper: NSColor

    func makeNSView(context: Context) -> AutoFitJustifiedTextView {
        let view = AutoFitJustifiedTextView()
        view.update(text: text, ink: ink, paper: paper)
        return view
    }

    func updateNSView(_ view: AutoFitJustifiedTextView, context: Context) {
        view.update(text: text, ink: ink, paper: paper)
    }
}

// NSView that hosts a non-editable NSTextView with justified alignment
// and binary-searches for the largest monospace font size that fits
// the text inside the view's current bounds. Font weight is `.light`
// — a thinner stroke than `.regular` that reads as retro CRT terminal
// text rather than modern UI copy.
final class AutoFitJustifiedTextView: NSView {
    private let textView = NSTextView()
    private var currentText: String = ""
    private var currentInk: NSColor = .white
    private var currentPaper: NSColor = .black

    // Keep searching within this range each time. 500 pt is a huge
    // upper bound that won't be hit in practice for any realistic
    // verse length; 10 pt is a sensible floor.
    private let fontLo: CGFloat = 10
    private let fontHi: CGFloat = 500

    // Font weight used for both measurement and rendering. Light
    // weight gives a more retro terminal feel than regular.
    private let fontWeight: NSFont.Weight = .light

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width, .height]
        addSubview(textView)
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
        relayoutForCurrentText()
    }

    func update(text: String, ink: NSColor, paper: NSColor) {
        currentText = text
        currentInk = ink
        currentPaper = paper
        layer?.backgroundColor = paper.cgColor
        relayoutForCurrentText()
    }

    // Binary search for the biggest font size that still fits.
    // Measuring is cheap here — it's just NSAttributedString
    // boundingRect — so a handful of iterations is fine.
    private func relayoutForCurrentText() {
        guard bounds.width > 20, bounds.height > 20 else { return }
        // Small internal buffer — the outer overscan margin (applied by
        // VisualsView) already handles CRT safety, so this is just a
        // bit of breathing room between the text and the safe edge.
        let padding: CGFloat = 8
        let availW = max(20, bounds.width - padding * 2)
        let availH = max(20, bounds.height - padding * 2)

        guard !currentText.isEmpty else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            return
        }

        var lo = fontLo
        var hi = fontHi
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            let height = measureHeight(fontSize: mid, width: availW)
            if height <= availH {
                lo = mid
            } else {
                hi = mid
            }
        }
        applyAttributedString(fontSize: lo, insetFor: padding)
    }

    private func measureHeight(fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight),
            .paragraphStyle: paragraph
        ]
        let s = NSAttributedString(string: currentText, attributes: attrs)
        let rect = s.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }

    private func applyAttributedString(fontSize: CGFloat, insetFor padding: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: fontWeight),
            .foregroundColor: currentInk,
            .paragraphStyle: paragraph
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: currentText, attributes: attrs)
        )
        textView.textContainerInset = CGSize(width: padding, height: padding)
    }
}
