import Foundation

package enum LineupBuilder {
    package struct Input {
        package let songs: [Song]
        package let countdowns: [Countdown]
        package let interstitials: [Interstitial]
        package let audienceInteractives: [AudienceInteractive]
        package let activeSetlist: Setlist?
        package let capabilities: PlatformCapabilities

        package init(
            songs: [Song],
            countdowns: [Countdown],
            interstitials: [Interstitial],
            audienceInteractives: [AudienceInteractive],
            activeSetlist: Setlist?,
            capabilities: PlatformCapabilities
        ) {
            self.songs = songs
            self.countdowns = countdowns
            self.interstitials = interstitials
            self.audienceInteractives = audienceInteractives
            self.activeSetlist = activeSetlist
            self.capabilities = capabilities
        }
    }

    package struct Output {
        package let lineup: [LineupItem]
        package let resolveIssues: [String]
    }

    package static func build(_ input: Input) -> Output {
        var resolveIssues: [String] = []
        let resolved: [LineupItem]

        if let active = input.activeSetlist {
            var items: [LineupItem] = []
            for ref in active.items {
                switch ref {
                case .song(let n):
                    if let s = input.songs.first(where: { $0.name == n }) {
                        items.append(.song(s))
                    } else {
                        resolveIssues.append(
                            "setlist '\(active.name)': song '\(n)' not found in Songs/"
                        )
                    }
                case .countdown(let n):
                    if input.capabilities == .performOnly { continue }
                    if let c = input.countdowns.first(where: { $0.name == n }) {
                        items.append(.countdown(c))
                    } else {
                        resolveIssues.append(
                            "setlist '\(active.name)': countdown '\(n)' not found in Countdowns/"
                        )
                    }
                case .interstitial(let n):
                    if input.capabilities == .performOnly { continue }
                    if let i = input.interstitials.first(where: { $0.name == n }) {
                        items.append(.interstitial(i))
                    } else {
                        resolveIssues.append(
                            "setlist '\(active.name)': interstitial '\(n)' not found in Interstitials/"
                        )
                    }
                case .audienceInteractive(let n):
                    if input.capabilities == .performOnly { continue }
                    if let a = input.audienceInteractives.first(where: { $0.name == n }) {
                        items.append(.audienceInteractive(a))
                    } else {
                        resolveIssues.append(
                            "setlist '\(active.name)': audience-interactive '\(n)' not found in AudienceInteractives/"
                        )
                    }
                }
            }
            resolved = items
        } else if input.capabilities == .performOnly {
            resolved = input.songs.map(LineupItem.song)
        } else {
            resolved = input.songs.map(LineupItem.song)
                + input.countdowns.map(LineupItem.countdown)
                + input.interstitials.map(LineupItem.interstitial)
                + input.audienceInteractives.map(LineupItem.audienceInteractive)
        }

        return Output(lineup: resolved, resolveIssues: resolveIssues)
    }

    package static func nextSongLineupIndex(in lineup: [LineupItem], after index: Int) -> Int? {
        guard index + 1 < lineup.count else { return nil }
        for i in (index + 1)..<lineup.count {
            if case .song = lineup[i] { return i }
        }
        return nil
    }

    package static func performOnlySetlistIsEmpty(_ input: Input) -> Bool {
        guard input.capabilities == .performOnly, input.activeSetlist != nil else { return false }
        return build(input).lineup.isEmpty
    }
}
