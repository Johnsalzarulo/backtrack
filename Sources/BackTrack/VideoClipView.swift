import SwiftUI
import AppKit
import AVFoundation
import AVKit

// Unmuted, single-shot AVPlayer view for the videoClip feature. Plays
// the file from start to finish, scaled CSS-cover (resizeAspectFill)
// like the rest of the visuals window's media. Fires `onFinish` when
// playback hits the end so the visuals layer can fall back to the
// part's normal visuals (GIF / synth).
//
// Differences vs. VisualView (the existing visuals media path):
//   - Audio enabled (VisualView mutes; videoClip's whole point is its
//     soundtrack alongside the backing track)
//   - Single-shot (VisualView loops seamlessly; videoClip plays once)
//   - Per-instance volume control via `volume` parameter
//   - Reports completion via NotificationCenter observer
//
// SwiftUI re-creates this NSViewRepresentable when `url` changes, so
// pointing at a different file or restarting on the same file by
// nil → URL transition gives a fresh playback from the head.
struct VideoClipView: NSViewRepresentable {
    let url: URL
    let volume: Float
    let loop: Bool
    let onFinish: () -> Void

    init(url: URL, volume: Float, loop: Bool = false, onFinish: @escaping () -> Void) {
        self.url = url
        self.volume = volume
        self.loop = loop
        self.onFinish = onFinish
    }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer = CALayer()
        host.layer?.backgroundColor = NSColor.black.cgColor

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Pass volume through unclamped — values above 1.0 may
        // amplify on newer macOS versions (AVPlayer was historically
        // capped at 1.0; modern AVFoundation accepts higher values
        // with internal clamping behavior left to the system). Floor
        // is still 0 to avoid negative-volume nonsense.
        player.volume = max(0, volume)
        player.actionAtItemEnd = .pause

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = host.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        host.layer?.addSublayer(layer)

        context.coordinator.player = player
        context.coordinator.layer = layer
        context.coordinator.onFinish = onFinish
        context.coordinator.loop = loop
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            guard let coord = coordinator else { return }
            if coord.loop {
                // Seamless loop — seek back to start and resume.
                coord.player?.seek(to: .zero)
                coord.player?.play()
            } else {
                coord.onFinish?()
            }
        }

        player.play()
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Volume can change without the URL changing (e.g., user
        // cycled videoClipVolume in tweak mode mid-clip). Apply live.
        context.coordinator.player?.volume = max(0, volume)
        // Keep the latest closure + loop flag; the notification fires
        // whatever's currently stored when the clip reaches end.
        context.coordinator.onFinish = onFinish
        context.coordinator.loop = loop
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
        coordinator.player?.pause()
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var layer: AVPlayerLayer?
        var observer: NSObjectProtocol?
        var onFinish: (() -> Void)?
        var loop: Bool = false
    }
}
