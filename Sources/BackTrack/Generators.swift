import Foundation

enum Generators {
    static let ticksPerBar = 16

    // Beat positions in 16ths:
    //   Beat 1 = tick 0, Beat 2 = 4, Beat 3 = 8, Beat 4 = 12
    //   "e" = +1, "and" = +2, "a" = +3
    static func drums(state: AppState, tick: Int) -> [NoteEvent] {
        var events: [NoteEvent] = []

        switch state.complexity {
        case 1:
            if tick == 0 || tick == 8 {
                events.append(NoteEvent(voice: .kick, velocity: 1.0))
            }
            if tick == 4 || tick == 12 {
                events.append(NoteEvent(voice: .snare, velocity: 1.0))
            }
            if tick % 4 == 0 {
                events.append(NoteEvent(voice: .hihat, velocity: 0.6))
            }
        case 2:
            if tick == 0 || tick == 8 {
                events.append(NoteEvent(voice: .kick, velocity: 1.0))
            }
            if tick == 4 || tick == 12 {
                events.append(NoteEvent(voice: .snare, velocity: 1.0))
            }
            if tick % 2 == 0 {
                events.append(NoteEvent(voice: .hihat, velocity: 0.6))
            }
        case 3:
            if tick == 0 || tick == 8 || tick == 10 {
                events.append(NoteEvent(voice: .kick, velocity: 1.0))
            }
            if tick == 4 || tick == 12 {
                events.append(NoteEvent(voice: .snare, velocity: 1.0))
            }
            if tick == 13 {
                events.append(NoteEvent(voice: .snare, velocity: 0.35))
            }
            events.append(NoteEvent(voice: .hihat, velocity: 0.55))
        default:
            break
        }

        return events
    }
}
