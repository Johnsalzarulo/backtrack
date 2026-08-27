import Foundation

package final class ShowController {
    package let state: AppState
    package let clock: Clock

    package init(state: AppState, clock: Clock) {
        self.state = state
        self.clock = clock
    }

    package func toggleTransport() {
        state.isPlaying ? clock.stop() : clock.start()
    }

    package func nextLineupItem() { selectLineupItem(at: state.currentLineupIndex + 1) }
    package func previousLineupItem() { selectLineupItem(at: state.currentLineupIndex - 1) }
    package func nextPart() { clock.nextPart() }
    package func previousPart() { clock.previousPart() }
    package func toggleLoop() { state.loopCurrentPart.toggle() }

    package func cycleSetlist() {
        guard !state.setlists.isEmpty else { return }
        let nextIndex = (state.currentSetlistIndex + 1) % (state.setlists.count + 1)
        state.currentSetlistIndex = nextIndex == state.setlists.count ? -1 : nextIndex
        state.currentLineupIndex = 0
        state.currentPartIndex = 0
        state.rebuildLineup()
    }

    package func selectSetlist(named name: String?) {
        if let name, let idx = state.setlists.firstIndex(where: { $0.name == name }) {
            state.currentSetlistIndex = idx
        } else {
            state.currentSetlistIndex = -1
        }
        state.currentLineupIndex = 0
        state.currentPartIndex = 0
        state.rebuildLineup()
    }

    package func advanceAfterSongEnd() {
        if state.platformCapabilities == .performOnly {
            if let next = LineupBuilder.nextSongLineupIndex(in: state.lineup, after: state.currentLineupIndex) {
                selectLineupItem(at: next)
            } else {
                clock.stop()
            }
        } else {
            nextLineupItem()
        }
    }

    private func selectLineupItem(at index: Int) {
        guard !state.lineup.isEmpty else { return }
        let clamped = max(0, min(index, state.lineup.count - 1))
        clock.stop()
        state.currentLineupIndex = clamped
        state.currentPartIndex = 0
        state.currentBar = 0
        state.currentBeat = 0
        state.loopCurrentPart = false
    }
}
