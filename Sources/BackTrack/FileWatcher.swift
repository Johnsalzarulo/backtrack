import Foundation

// Polls a set of file URLs for modification-time changes and fires a
// callback whenever anything changes, is added, or is removed. Plain
// 1 Hz polling is precise enough for song-JSON edits and avoids the
// FSEvents/kqueue complexity; the files are tiny so re-reading them
// costs nothing measurable.
final class FileWatcher {
    private let pathsProvider: () -> [URL]
    private let onChange: () -> Void
    private var lastModified: [URL: Date] = [:]
    private var timer: DispatchSourceTimer?

    init(paths: @escaping () -> [URL], onChange: @escaping () -> Void) {
        self.pathsProvider = paths
        self.onChange = onChange
    }

    func start(interval: TimeInterval = 1.0) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.check() }
        t.resume()
        timer = t
        // Seed so the first check doesn't fire for every file.
        for url in pathsProvider() {
            lastModified[url] = modificationDate(of: url)
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func check() {
        let current = Set(pathsProvider())
        var changed = false

        for url in current {
            let mtime = modificationDate(of: url)
            if lastModified[url] != mtime {
                lastModified[url] = mtime
                changed = true
            }
        }

        // Detect removals.
        let removed = Set(lastModified.keys).subtracting(current)
        if !removed.isEmpty {
            for url in removed { lastModified.removeValue(forKey: url) }
            changed = true
        }

        if changed { onChange() }
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
