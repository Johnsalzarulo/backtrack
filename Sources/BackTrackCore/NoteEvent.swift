import Foundation

package struct NoteEvent {
    package enum Voice {
        case kick
        case snare
        case hihat
        case pad(pitchClass: Int)
        case bass(pitchClass: Int)
    }
    package let voice: Voice
    package let velocity: Float

    package init(voice: Voice, velocity: Float) {
        self.voice = voice
        self.velocity = velocity
    }
}
