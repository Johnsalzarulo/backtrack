import Foundation

// Discovers and validates interstitials under ~/BackTrack/Interstitials/.
// Mirrors SongLoader / CountdownLoader so the Coordinator can drive
// all three through the same plumbing — file watcher, issues list, etc.
enum InterstitialLoader {
    struct Result {
        let interstitials: [Interstitial]
        let issues: [String]
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BackTrack")
            .appendingPathComponent("Interstitials")
    }

    static func loadAll() -> Result {
        loadAll(from: defaultDirectory())
    }

    static func loadAll(from dir: URL) -> Result {
        var interstitials: [Interstitial] = []
        var issues: [String] = []

        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return Result(interstitials: [], issues: [])
        }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "json" }
             .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            issues.append("failed to read Interstitials directory: \(error.localizedDescription)")
            return Result(interstitials: [], issues: issues)
        }

        for url in entries {
            do {
                let data = try Data(contentsOf: url)
                let raw = try JSONDecoder().decode(InterstitialJSON.self, from: data)
                let inter = try compile(raw, sourceURL: url)
                interstitials.append(inter)
            } catch let error as InterstitialValidationError {
                issues.append("\(url.lastPathComponent): \(error.description)")
            } catch {
                issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return Result(interstitials: interstitials, issues: issues)
    }

    private static func compile(_ raw: InterstitialJSON, sourceURL: URL) throws -> Interstitial {
        let kind: InterstitialKind
        switch raw.kind.lowercased() {
        case "text":  kind = .text
        case "image": kind = .image
        case "video": kind = .video
        default:
            throw InterstitialValidationError(
                "kind '\(raw.kind)' — expected one of: text, image, video"
            )
        }

        // Required content field per kind.
        switch kind {
        case .text:
            guard let txt = raw.text, !txt.isEmpty else {
                throw InterstitialValidationError("text interstitial must have non-empty 'text'")
            }
        case .image:
            guard let img = raw.image, !img.isEmpty else {
                throw InterstitialValidationError("image interstitial must have non-empty 'image'")
            }
        case .video:
            guard let vid = raw.video, !vid.isEmpty else {
                throw InterstitialValidationError("video interstitial must have non-empty 'video'")
            }
        }

        let volume = raw.volume ?? 100
        guard (0...200).contains(volume) else {
            throw InterstitialValidationError("volume \(volume) out of range (0-200)")
        }

        let theme: VisualTheme
        switch raw.theme?.lowercased() {
        case nil, "", "dark":
            theme = .dark
        case "light":
            theme = .light
        case let other?:
            throw InterstitialValidationError(
                "theme '\(other)' — expected 'dark' or 'light'"
            )
        }

        // For video kind, duration is ignored — the clip's actual
        // length determines auto-advance. For text/image, an optional
        // duration auto-advances after that many seconds.
        let duration: TimeInterval?
        if kind == .video {
            duration = nil
        } else if let d = raw.duration, d > 0 {
            duration = TimeInterval(d)
        } else {
            duration = nil
        }

        return Interstitial(
            sourceURL: sourceURL,
            name: raw.name,
            kind: kind,
            text: raw.text,
            image: raw.image,
            video: raw.video,
            volume: volume,
            loop: raw.loop ?? false,
            duration: duration,
            notes: raw.notes ?? "",
            theme: theme
        )
    }
}

struct InterstitialValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
