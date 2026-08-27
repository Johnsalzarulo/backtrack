import Foundation

package enum BackTrackPaths {
    package static var defaultRoot: URL {
        #if os(iOS)
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackTrack")
        #else
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("BackTrack")
        #endif
    }
}

package protocol ContentStore {
    var rootURL: URL { get }
    func songsDirectory() -> URL
    func setlistsDirectory() -> URL
    func samplesDirectory() -> URL
    func patternsURL() -> URL
}

package struct MacContentStore: ContentStore {
    package var rootURL: URL { BackTrackPaths.defaultRoot }
    package func songsDirectory() -> URL { rootURL.appendingPathComponent("Songs") }
    package func setlistsDirectory() -> URL { rootURL.appendingPathComponent("Setlists") }
    package func samplesDirectory() -> URL { rootURL.appendingPathComponent("Samples") }
    package func patternsURL() -> URL { samplesDirectory().appendingPathComponent("patterns.json") }
}

package struct SandboxContentStore: ContentStore {
    package let rootURL: URL
    package init(rootURL: URL) { self.rootURL = rootURL }
    package func songsDirectory() -> URL { rootURL.appendingPathComponent("Songs") }
    package func setlistsDirectory() -> URL { rootURL.appendingPathComponent("Setlists") }
    package func samplesDirectory() -> URL { rootURL.appendingPathComponent("Samples") }
    package func patternsURL() -> URL { samplesDirectory().appendingPathComponent("patterns.json") }
}

package enum LibraryImporter {
    package static func importLibrary(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for subdir in ["Songs", "Setlists", "Samples"] {
            let src = source.appendingPathComponent(subdir)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: destination.appendingPathComponent(subdir))
        }
    }

    package static func defaultSandboxRoot() -> URL {
        BackTrackPaths.defaultRoot
    }
}

package enum VisualsLibrary {
    package static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "heic", "bmp", "gif",
        "mp4", "mov", "m4v", "mpg", "mpeg", "m2v", "webm", "avi",
    ]

    package static func scanAll(store: ContentStore = MacContentStore()) -> [String] {
        let dir = store.rootURL.appendingPathComponent("Visuals")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
    }
}

package enum VideoClipsLibrary {
    package static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mpg", "mpeg", "m2v", "webm", "avi",
    ]

    package static func directory(store: ContentStore = MacContentStore()) -> URL {
        store.rootURL.appendingPathComponent("VideoClips")
    }

    package static func scanAll(store: ContentStore = MacContentStore()) -> [String] {
        let dir = directory(store: store)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
    }

    package static func url(for filename: String, store: ContentStore = MacContentStore()) -> URL? {
        let url = directory(store: store).appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
