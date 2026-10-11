import Foundation

/// Chooses Home's next leaf, the tree's buds and the Herbarium's "Almost there" rail (spec §3.5). Pure.
///
/// Candidates are each available category's lowest locked rung. Estimates come from `LeafProgress.estimatedDays`
/// (the 14-day rate, or the design pace when the rate is zero), so a new member is pointed at first rungs.
public struct NextLeafPicker: Sendable {
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

    /// What Home may pick from: every candidate, except that once any focus category has shipped, Rested nights is
    /// left out (focus spec §4.1, §4.5: sleep is never Home's automatic next leaf in a focus build).
    public var homeCandidates: [LeafProgress] {
        let focusShipped = progress.contains { $0.category != .restedNights && $0.category != .firstLeaf && $0.availability != .dormant }
        return focusShipped ? candidates.filter { $0.category != .restedNights } : candidates
    }

    /// Home's next leaf (focus spec §4.5): a pinned leaf while it is locked and available; otherwise the lowest
    /// hours-saved rung; otherwise the closest of Home's candidates.
    public func next(pinned: String?) -> LeafProgress? {
        if let pinned, let leaf = progress.first(where: { $0.speciesID == pinned }), leaf.state == .locked, leaf.availability == .available {
            return leaf
        }
        if let hours = homeCandidates.first(where: { $0.category == .hoursSaved }) { return hours }
        return Self.sorted(homeCandidates).first
    }

    /// The tree's buds: the 3 closest candidates, always including Home's next leaf, which comes first.
    public func buds(pinned: String?) -> [LeafProgress] {
        let closest = Array(Self.sorted(candidates).prefix(Self.budCount))
        guard let next = next(pinned: pinned) else { return closest }
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
    /// shows it as the next-leaf row's needs-permission variant ("Needs Screen Time", with "Turn on Screen Time")
    /// rather than leave the row empty. Nil while any leaf can be earned, and for what Maple can't turn on (a sleep
    /// tracker is hardware).
    public func permissionPrompt() -> LeafProgress? {
        guard homeCandidates.isEmpty else { return nil }
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

extension LeafProgress {
    /// The category's canonical position (§5.1).
    var categoryOrder: Int { RewardCategoryInfo(category).order }
}
