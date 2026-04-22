import SwiftUI
import AppKit
import AVKit
import AVFoundation

// File extensions that should dispatch to the video path (AVPlayer,
// looped). Anything else is treated as a still image or animated GIF —
// NSImage is tolerant enough to cover PNG, JPEG, GIF, TIFF, HEIC, BMP.
private let videoExtensions: Set<String> = [
    "mp4", "mov", "m4v", "mpg", "mpeg", "m2v", "webm", "avi"
]

// SwiftUI wrapper that displays a visual (still image, animated GIF, or
// video) filling the view with CSS-cover-style scaling: fills both axes,
// preserves aspect ratio, clips the overflow. Backed by either NSImageView
// or an AVPlayerLayer depending on the URL's file extension.
struct VisualView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> VisualContainerView {
        let c = VisualContainerView()
        c.load(url: url)
        return c
    }

    func updateNSView(_ nsView: VisualContainerView, context: Context) {
        nsView.load(url: url)
    }
}

final class VisualContainerView: NSView {
    private var currentURL: URL?

    // Image path — also handles animated GIFs via NSImageView's built-in
    // animation support.
    private let imageView = NSImageView()

    // Video path. AVQueuePlayer + AVPlayerLooper gives seamless looping
    // without the flicker of AVPlayer.actionAtItemEnd rewinding.
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

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
        // We do the aspect-preserving frame math ourselves because
        // NSImageView's built-in modes don't include "cover".
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.autoresizingMask = []
        imageView.isHidden = true
        addSubview(imageView)
    }

    override var isFlipped: Bool { true }

    // Switch to whatever media the new URL points at. No-op if the URL
    // is unchanged — avoids reloading decoders on every bar/beat tick
    // when the cycling index happens to land on the same filename.
    func load(url: URL) {
        if currentURL == url { return }
        currentURL = url

        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) {
            showVideo(url: url)
        } else {
            showImage(url: url)
        }
        needsLayout = true
    }

    private func showImage(url: URL) {
        teardownVideo()
        imageView.image = NSImage(contentsOf: url)
        imageView.animates = true
        imageView.isHidden = false
    }

    private func showVideo(url: URL) {
        imageView.isHidden = true
        imageView.image = nil
        teardownVideo()

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        let looper = AVPlayerLooper(player: queue, templateItem: item)

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill   // CSS-cover
        layer.frame = bounds
        self.layer?.addSublayer(layer)

        self.queuePlayer = queue
        self.looper = looper
        self.playerLayer = layer
        queue.play()
    }

    private func teardownVideo() {
        queuePlayer?.pause()
        playerLayer?.removeFromSuperlayer()
        queuePlayer = nil
        looper = nil
        playerLayer = nil
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
        layoutImageCover()
    }

    private func layoutImageCover() {
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
