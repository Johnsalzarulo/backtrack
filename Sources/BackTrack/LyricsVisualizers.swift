import SwiftUI
import AppKit

// Typographic visualizer views — the alternative to the geometric
// motifs (sun / squares / dots / etc.). All three render the current
// part's `lyrics` field in monospace ink on paper, following the
// active theme.

// MARK: - Block: whole part as one justified paragraph

// Renders every line of lyrics in the current part as a single
// justified paragraph, with font size auto-fit (binary search) so
// the text fills the frame edge to edge. Re-measures whenever the
// text or the frame size changes.
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
// the text inside the view's current bounds. The text view's own
// layout manager does the line-wrapping.
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
        let padding: CGFloat = 40
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
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
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
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: currentInk,
            .paragraphStyle: paragraph
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: currentText, attributes: attrs)
        )
        textView.textContainerInset = CGSize(width: padding, height: padding)
    }
}

// MARK: - Line / Word: single chunk, centered, very large

// Used by both lyrics-line and lyrics-word modes. Renders a short
// piece of text centered and scaled as large as SwiftUI will allow
// within the frame (minimumScaleFactor handles overflow gracefully
// when a particularly long word or line would otherwise clip).
//
// `singleLine` matters for word mode: a long single word like
// "yourself" at baseSize=300 is wider than the screen, and without
// a line limit SwiftUI breaks it across two lines at a character
// boundary rather than shrinking the whole word. Forcing
// `lineLimit(1)` makes `minimumScaleFactor` actually kick in so the
// word stays on one line and scales down to fit.
struct LyricsCenteredView: View {
    let text: String
    let baseSize: CGFloat
    let singleLine: Bool
    let ink: Color
    let paper: Color

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            Text(text)
                .font(.system(size: baseSize, weight: .regular, design: .monospaced))
                .minimumScaleFactor(0.05)
                .multilineTextAlignment(.center)
                .lineLimit(singleLine ? 1 : nil)
                .foregroundColor(ink)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
