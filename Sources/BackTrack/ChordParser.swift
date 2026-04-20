import Foundation

// Minimal chord notation for indie rock / emo: major, minor, dominant 7,
// major 7, minor 7. Anything outside that set is a parse error.
//
//   C       → C major triad
//   Cm      → C minor triad
//   C7      → C dominant 7 (major triad + flat 7)
//   Cmaj7   → C major 7 (major triad + major 7)
//   Cm7     → C minor 7 (minor triad + flat 7)
//
// Accepted variants (case-insensitive, normalized at parse time):
//   Dmin = Dm   Dmaj = D   DMaj7 = Dmaj7   etc.
struct Chord: Equatable {
    enum Quality: Equatable {
        case major
        case minor
    }
    enum Extension: Equatable {
        case none
        case dom7      // +10 from root
        case maj7      // +11 from root
    }

    let rootPitchClass: Int   // 0 (C) .. 11 (B)
    let quality: Quality
    let ext: Extension

    // Semitone intervals (from root) that make up this chord.
    var intervals: [Int] {
        let third = (quality == .major) ? 4 : 3
        let fifth = 7
        switch ext {
        case .none:
            return [0, third, fifth]
        case .dom7:
            return [0, third, fifth, 10]
        case .maj7:
            return [0, third, fifth, 11]
        }
    }

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var display: String {
        let letter = Self.noteNames[rootPitchClass]
        let suffix: String
        switch (quality, ext) {
        case (.major, .none): suffix = ""
        case (.minor, .none): suffix = "m"
        case (.major, .dom7): suffix = "7"
        case (.minor, .dom7): suffix = "m7"
        case (.major, .maj7): suffix = "maj7"
        case (.minor, .maj7): suffix = "m(maj7)"  // rare; still valid
        }
        return letter + suffix
    }
}

enum ChordParseError: Error, CustomStringConvertible {
    case emptyInput
    case unknownRoot(String)
    case unknownSuffix(String)

    var description: String {
        switch self {
        case .emptyInput: return "empty chord symbol"
        case .unknownRoot(let r): return "unknown root '\(r)'"
        case .unknownSuffix(let s): return "unrecognized chord suffix '\(s)'"
        }
    }
}

enum ChordParser {
    static func parse(_ raw: String) throws -> Chord {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ChordParseError.emptyInput }

        // Pull off root letter + optional accidental.
        var i = trimmed.startIndex
        guard i < trimmed.endIndex else { throw ChordParseError.emptyInput }
        let first = trimmed[i]
        var pitchClass: Int
        switch first {
        case "C", "c": pitchClass = 0
        case "D", "d": pitchClass = 2
        case "E", "e": pitchClass = 4
        case "F", "f": pitchClass = 5
        case "G", "g": pitchClass = 7
        case "A", "a": pitchClass = 9
        case "B", "b": pitchClass = 11
        default: throw ChordParseError.unknownRoot(String(first))
        }
        i = trimmed.index(after: i)

        if i < trimmed.endIndex {
            switch trimmed[i] {
            case "#":
                pitchClass = (pitchClass + 1) % 12
                i = trimmed.index(after: i)
            case "b", "B":
                // Flat, but only if it's followed by a suffix-like char or end-of-string.
                // Otherwise "Bb" vs "B" ambiguity: we already consumed B (rootPitchClass=11),
                // so `b` here would flat it. We only treat as flat when the next char after
                // can't start a standard suffix. In practice, "Bb" is fine; "Bbm" → flatten.
                // Conservative: treat any following lowercase 'b' as flat.
                if trimmed[i] == "b" {
                    pitchClass = ((pitchClass - 1) % 12 + 12) % 12
                    i = trimmed.index(after: i)
                }
            default:
                break
            }
        }

        let suffix = String(trimmed[i...]).lowercased()
        let (quality, ext) = try parseSuffix(suffix)
        return Chord(rootPitchClass: pitchClass, quality: quality, ext: ext)
    }

    private static func parseSuffix(_ s: String) throws -> (Chord.Quality, Chord.Extension) {
        switch s {
        case "", "maj":
            return (.major, .none)
        case "m", "min":
            return (.minor, .none)
        case "7":
            return (.major, .dom7)
        case "maj7", "m7+":  // rare alias
            return (.major, .maj7)
        case "m7", "min7":
            return (.minor, .dom7)
        case "m(maj7)", "mmaj7":
            return (.minor, .maj7)
        default:
            throw ChordParseError.unknownSuffix(s)
        }
    }
}
