import Foundation
import MapleFocusCore

/// Builds `LeafProgress` for all 155 species from the member's counters and unlocks (spec §7.4). Views read the
/// result; they never compute unlocks or estimates themselves.
public struct LeafProgressBuilder: Sendable {
    public var catalog: RewardCatalog
    public var permissions: GrantedPermissions
    public var features: ShippedFeatures
    public var blocking: BlockingCapability

    public init(
        permissions: GrantedPermissions, features: ShippedFeatures, blocking: BlockingCapability = .screenTime,
        catalog: RewardCatalog = .shared
    ) {
        self.catalog = catalog
        self.permissions = permissions
        self.features = features
        self.blocking = blocking
    }

    /// One row per species, in canonical order: categories as in §5.1, then each ladder from its lowest rung.
    public func progress(
        counters: [RewardCategoryID: Double], unlocks: [LeafUnlock], history: [DailyCounters], today: LocalDay,
        calendar: Calendar
    ) -> [LeafProgress] {
        let unlocked = Dictionary(unlocks.map { ($0.speciesID, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [LeafProgress] = []
        rows.reserveCapacity(catalog.assignments.count)
        for category in catalog.categories {
            let availability = LeafAvailability(category: category.id, permissions: permissions, features: features, blocking: blocking)
            let current = counters[category.id] ?? 0
            let rate = availability == .available
                ? LeafPace.rate(for: category.id, current: current, history: history, today: today, calendar: calendar)
                : 0
            var floor = 0.0
            for rung in catalog.rungs(in: category.id) {
                defer { floor = rung.threshold }
                let state: LeafState
                if let unlock = unlocked[rung.speciesID] {
                    state = unlock.revealed ? .earned(unlock) : .waiting(unlock)
                } else {
                    state = .locked
                }
                let estimate: Double? = state == .locked && availability == .available
                    ? LeafPace.estimatedDays(remaining: max(0, rung.threshold - current), rate: rate, category: category.id)
                    : nil
                rows.append(LeafProgress(
                    speciesID: rung.speciesID, category: category.id, threshold: rung.threshold, tier: rung.tier,
                    current: current, availability: availability, state: state, estimatedDays: estimate,
                    floor: floor
                ))
            }
        }
        return rows
    }
}
