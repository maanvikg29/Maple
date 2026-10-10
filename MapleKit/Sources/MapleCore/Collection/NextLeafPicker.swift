import Foundation

/// Chooses Home's next leaf, the tree's buds and the Herbarium's "Almost there" rail (spec §3.5). Pure.
///
/// Candidates are each available category's lowest locked rung. Estimates come from `LeafProgress.estimatedDays`
/// (the 14-day rate, or the design pace when the rate is zero), so a new member is pointed at first rungs.
public struct NextLeafPicker: Sendable {
    /// A phase's own leaves win only when they are this close.
    public static let preferenceWindowDays = 7.0
    /// "Almost there" shows leaves within this many days.
    public static let almostThereWindowDays = 60.0
    public static let almostThereLimit = 6
    public static let budCount = 3
    /// The Herbarium shows this many locked rungs of each available category as "Next".
    public static let nextRungsPerCategory = 3

    public let progress: [LeafProgress]
    /// Each available category's lowest locked rung, in canonical order.
    public let candidates: [LeafProgress]

    public init(progress: [LeafProgress]) {
        self.progress = progress
        var seen = Set<RewardCategoryID>()
        candidates = Self.lockedAvailable(progress).filter { seen.insert($0.category).inserted }
    }

    /// Home's next leaf: a pinned leaf while it is locked and available; otherwise the phase's own leaves when one is
    /// within a week; otherwise the closest leaf.
    public func next(phase: NowPhase, pinned: String?) -> LeafProgress? {
        if let pinned, let leaf = progress.first(where: { $0.speciesID == pinned }), leaf.state == .locked, leaf.availability == .available {
            return leaf
        }
        let preferred = candidates.filter { RewardCategoryInfo($0.category).timeOfDay == phase.leafPreference }
        if let best = Self.sorted(preferred).first, (best.estimatedDays ?? .infinity) <= Self.preferenceWindowDays {
            return best
        }
        return Self.sorted(candidates).first
    }

    /// The tree's buds: the 3 closest candidates, always including Home's next leaf, which comes first.
    public func buds(phase: NowPhase, pinned: String?) -> [LeafProgress] {
        let closest = Array(Self.sorted(candidates).prefix(Self.budCount))
        guard let next = next(phase: phase, pinned: pinned) else { return closest }
        let others = closest.filter { $0.speciesID != next.speciesID }
        return [next] + others.prefix(Self.budCount - 1)
    }

    /// "Almost there": the next rungs of available categories within 60 days, closest first, up to 6.
    public func almostThere() -> [LeafProgress] {
        let near = nextRungs.filter { ($0.estimatedDays ?? .infinity) <= Self.almostThereWindowDays }
        return Array(Self.sorted(near).prefix(Self.almostThereLimit))
    }

    /// When nothing can be earned because a permission is missing: the cheapest leaf turning it on would make
    /// earnable, by its category's design pace (the member has no pace there yet). Ties go to canonical order.
    ///
    /// D9 keeps these leaves out of the next leaf, buds, Almost there and pacing, so this is not a next leaf: Home
    /// shows it as the next-leaf row's needs-permission variant ("Needs Apple Health", with "Turn on Apple Health")
    /// rather than leave the row empty. Nil while any leaf can be earned, and for what Maple can't turn on (a sleep
    /// tracker is hardware).
    public func permissionPrompt() -> LeafProgress? {
        guard candidates.isEmpty else { return nil }
        var seen = Set<RewardCategoryID>()
        let blocked = progress
            .filter { $0.state == .locked && $0.availability.canBeTurnedOn }
            .sorted { ($0.categoryOrder, $0.threshold) < ($1.categoryOrder, $1.threshold) }
            .filter { seen.insert($0.category).inserted }
        func days(_ leaf: LeafProgress) -> Double {
            LeafPace.estimatedDays(remaining: leaf.remaining, rate: 0, category: leaf.category)
        }
        return blocked.min { a, b in
            let da = days(a), db = days(b)
            if da != db { return da < db }
            return (a.categoryOrder, a.threshold) < (b.categoryOrder, b.threshold)
        }
    }

    /// Species shown as "Next" in the Herbarium: the 3 lowest locked rungs of each available category.
    public var nextRungIDs: Set<String> {
        Set(nextRungs.map(\.speciesID))
    }

    private var nextRungs: [LeafProgress] {
        var taken: [RewardCategoryID: Int] = [:]
        return Self.lockedAvailable(progress).filter { leaf in
            let count = taken[leaf.category, default: 0]
            guard count < Self.nextRungsPerCategory else { return false }
            taken[leaf.category] = count + 1
            return true
        }
    }

    /// Locked, available rungs, each category's ladder from the bottom.
    private static func lockedAvailable(_ progress: [LeafProgress]) -> [LeafProgress] {
        progress
            .filter { $0.state == .locked && $0.availability == .available }
            .sorted { ($0.categoryOrder, $0.threshold) < ($1.categoryOrder, $1.threshold) }
    }

    /// Closest first. Ties: higher fraction complete, then canonical category order, then lower threshold.
    static func sorted(_ leaves: [LeafProgress]) -> [LeafProgress] {
        leaves.sorted { a, b in
            let ea = a.estimatedDays ?? .infinity, eb = b.estimatedDays ?? .infinity
            if ea != eb { return ea < eb }
            if a.fraction != b.fraction { return a.fraction > b.fraction }
            if a.categoryOrder != b.categoryOrder { return a.categoryOrder < b.categoryOrder }
            return a.threshold < b.threshold
        }
    }
}

extension NowPhase {
    /// Which leaves Home prefers in this phase (spec §3.5): evening, wind-down and night prefer night leaves.
    public var leafPreference: RewardTimeOfDay {
        switch self {
        case .morning: .morning
        case .day: .day
        case .evening, .windDown, .night: .night
        }
    }
}

extension LeafProgress {
    /// The category's canonical position (§5.1).
    var categoryOrder: Int { RewardCategoryInfo(category).order }
}
