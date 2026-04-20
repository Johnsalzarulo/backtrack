import SwiftUI
import AppKit

// SwiftUI wrapper that displays an animated GIF filling the view with
// CSS-cover-style scaling: the image fills both axes, preserves aspect
// ratio, and clips whatever overflows. Backed by NSImageView for GIF
// animation; layout is done manually because NSImageView's built-in
// scaling modes don't include "cover".
struct GifView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> CoverImageContainer {
        let c = CoverImageContainer()
        c.imageURL = url
        return c
    }

    func updateNSView(_ nsView: CoverImageContainer, context: Context) {
        nsView.imageURL = url
    }
}

final class CoverImageContainer: NSView {
    private let imageView = NSImageView()

    var imageURL: URL? {
        didSet {
            guard oldValue != imageURL else { return }
            if let url = imageURL {
                imageView.image = NSImage(contentsOf: url)
                imageView.animates = true
            } else {
                imageView.image = nil
            }
            needsLayout = true
        }
    }

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
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        // Have NSImageView stretch the image to fill whatever frame we
        // give it; we'll compute the frame to match the image's aspect
        // so "stretch" is actually aspect-preserving.
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.autoresizingMask = []
        addSubview(imageView)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        guard let image = imageView.image else {
            imageView.frame = bounds
            return
        }
        let vw = bounds.width
        let vh = bounds.height
        let iw = image.size.width
        let ih = image.size.height
        guard vw > 0, vh > 0, iw > 0, ih > 0 else {
            imageView.frame = bounds
            return
        }
        // CSS `background-size: cover`: scale by the larger of the two
        // width/height ratios so at least one axis fills exactly.
        let scale = max(vw / iw, vh / ih)
        let newW = iw * scale
        let newH = ih * scale
        imageView.frame = CGRect(
            x: (vw - newW) / 2,
            y: (vh - newH) / 2,
            width: newW,
            height: newH
        )
    }
}
