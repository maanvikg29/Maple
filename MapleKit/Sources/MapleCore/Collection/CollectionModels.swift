import Foundation

/// A species the member has earned. Unlocks are keyed by species id, so the same leaf can never be awarded twice.
public struct LeafUnlock: Codable, Sendable, Hashable, Identifiable {
    public var id: String { speciesID }
    public let speciesID: String
    public let date: Date
    /// Season the leaf was earned in; fixes its pressed colourway forever.
    public let season: Season
    public let colourway: LeafColourway
    /// False while the leaf waits as a bud to be opened (the reveal).
    public var revealed: Bool
    /// False until the member has looked at it in the herbarium (drives the amber unseen dot).
    public var seen: Bool

    public init(speciesID: String, date: Date, season: Season, colourway: LeafColourway, revealed: Bool = false, seen: Bool = false) {
        self.speciesID = speciesID
        self.date = date
        self.season = season
        self.colourway = colourway
        self.revealed = revealed
        self.seen = seen
    }
}

/// Whether a leaf's category can currently be earned on this iPhone.
public enum LeafAvailability: Sendable, Equatable {
    case available
    case needsAppleHealth
    /// Needs asleep-stage data from an Apple Watch or a sleep tracker.
    case needsSleepTracker
    case needsScreenTime
    /// The category ships in a later release ("Not earnable yet").
    case dormant
}

/// Where a leaf stands for this member.
public enum LeafState: Sendable, Equatable {
    case earned(LeafUnlock)
    /// Unlocked but not yet opened.
    case waiting(LeafUnlock)
    case locked
}

/// Everything a view needs to show one leaf's progress. Views never compute unlocks themselves.
public struct LeafProgress: Sendable, Identifiable, Equatable {
    public var id: String { speciesID }
    public let speciesID: String
    public let category: RewardCategoryID
    public let threshold: Double
    public let tier: RewardTier
    /// The category's counter, clamped to the threshold.
    public let current: Double
    public let availability: LeafAvailability
    public let state: LeafState
    /// Days to reach the threshold at the member's pace (or the design pace); nil when unavailable or earned.
    public let estimatedDays: Double?

    public init(
        speciesID: String, category: RewardCategoryID, threshold: Double, tier: RewardTier, current: Double,
        availability: LeafAvailability, state: LeafState, estimatedDays: Double?
    ) {
        self.speciesID = speciesID
        self.category = category
        self.threshold = threshold
        self.tier = tier
        self.current = min(current, threshold)
        self.availability = availability
        self.state = state
        self.estimatedDays = estimatedDays
    }

    /// Progress toward the threshold, 0...1.
    public var fraction: Double {
        threshold > 0 ? min(1, max(0, current / threshold)) : 0
    }

    /// Whole units still needed, e.g. 3 (nights).
    public var remaining: Double {
        max(0, threshold - current)
    }
}

/// How many members hold a leaf, in every state the UI must handle honestly (design spec §5.7).
public enum MemberShare: Sendable, Equatable {
    case loading
    /// Fresh: last successful fetch under 48 hours ago. `display` is already formatted, e.g. "22%" or "Under 1%".
    case value(display: String, asOf: Date)
    /// A cached value older than 48 hours.
    case stale(display: String, asOf: Date)
    /// Fewer than 1,000 members take part. `soFar` is the published count, when known.
    case notEnoughMembers(soFar: Int?)
    /// Offline with nothing cached.
    case neverFetched
    /// Species added in a catalogue update; counts arrive next week.
    case newSpecies
    /// The leaf's category hasn't shipped.
    case notEarnableYet
}
