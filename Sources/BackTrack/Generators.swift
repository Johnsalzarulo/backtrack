import Foundation

// Tick positions in a 16-step bar:
//   0  = 1,    1 = 1e,   2 = 1+,   3 = 1a
//   4  = 2,    5 = 2e,   6 = 2+,   7 = 2a
//   8  = 3,    9 = 3e,  10 = 3+,  11 = 3a
//  12  = 4,   13 = 4e,  14 = 4+,  15 = 4a
enum Generators {
    static let ticksPerBar = 16

    // Patterns 1–10. Grouped in threes by "feel" (straight / rock / boom-bap /
    // sparse), each group ramping simple → busier. Pattern 10 (keyboard `0`)
    // is a sparse outlier that restarts the simplicity cycle.
    static func drums(state: AppState, tick: Int) -> [NoteEvent] {
        switch state.pattern {
        case 1:  return pattern1(tick: tick)
        case 2:  return pattern2(tick: tick)
        case 3:  return pattern3(tick: tick)
        case 4:  return pattern4(tick: tick)
        case 5:  return pattern5(tick: tick)
        case 6:  return pattern6(tick: tick)
        case 7:  return pattern7(tick: tick)
        case 8:  return pattern8(tick: tick)
        case 9:  return pattern9(tick: tick)
        case 10: return pattern10(tick: tick)
        default: return pattern2(tick: tick)
        }
    }

    // MARK: - Straight feel (1–3)

    // 1: kick 1 only, hi-hat quarters, no snare. Ultra sparse pulse.
    private static func pattern1(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick % 4 == 0 { e.append(.init(voice: .hihat, velocity: 0.6)) }
        return e
    }

    // 2: classic kick 1&3, snare 2&4, hi-hat quarters.
    private static func pattern2(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 8 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 4 || tick == 12 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick % 4 == 0 { e.append(.init(voice: .hihat, velocity: 0.6)) }
        return e
    }

    // 3: kick 1&3, snare 2&4 with a ghost on 4e, hi-hat 8ths.
    private static func pattern3(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 8 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 4 || tick == 12 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick == 13 { e.append(.init(voice: .snare, velocity: 0.35)) }
        if tick % 2 == 0 { e.append(.init(voice: .hihat, velocity: 0.6)) }
        return e
    }

    // MARK: - Rock / driving (4–6)

    // 4: kick 1, snare 3, hi-hat 8ths.
    private static func pattern4(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 8 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick % 2 == 0 { e.append(.init(voice: .hihat, velocity: 0.6)) }
        return e
    }

    // 5: kick 1 and 2+, snare 3, hi-hat 8ths.
    private static func pattern5(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 6 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 8 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick % 2 == 0 { e.append(.init(voice: .hihat, velocity: 0.6)) }
        return e
    }

    // 6: kick 1, 2+, 4+; snare 3; hi-hat 16ths.
    private static func pattern6(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 6 || tick == 14 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 8 { e.append(.init(voice: .snare, velocity: 1.0)) }
        e.append(.init(voice: .hihat, velocity: 0.55))
        return e
    }

    // MARK: - Boom-bap (7–9)

    // 7: kick 1, snare 3, hi-hat on 2 & 4 only. Very spacious.
    private static func pattern7(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 8 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick == 4 || tick == 12 { e.append(.init(voice: .hihat, velocity: 0.55)) }
        return e
    }

    // 8: kick 1 and 1e, snare 3 + ghost 4e, hi-hat 8ths.
    private static func pattern8(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 1 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 8 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick == 13 { e.append(.init(voice: .snare, velocity: 0.35)) }
        if tick % 2 == 0 { e.append(.init(voice: .hihat, velocity: 0.6)) }
        return e
    }

    // 9: kick 1, 1e, 3+; snare 3 + ghost 4e; hi-hat 16ths.
    private static func pattern9(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 1 || tick == 10 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 8 { e.append(.init(voice: .snare, velocity: 1.0)) }
        if tick == 13 { e.append(.init(voice: .snare, velocity: 0.35)) }
        e.append(.init(voice: .hihat, velocity: 0.55))
        return e
    }

    // MARK: - Sparse (10)

    // 10: kick 1&3, low-velocity cross-stick-feel snare on 4e only, hi-hat
    // on 1 & 3 only. Super spacious, cycles back to "very simple".
    private static func pattern10(tick: Int) -> [NoteEvent] {
        var e: [NoteEvent] = []
        if tick == 0 || tick == 8 { e.append(.init(voice: .kick, velocity: 1.0)) }
        if tick == 13 { e.append(.init(voice: .snare, velocity: 0.4)) }
        if tick == 0 || tick == 8 { e.append(.init(voice: .hihat, velocity: 0.55)) }
        return e
    }
}
