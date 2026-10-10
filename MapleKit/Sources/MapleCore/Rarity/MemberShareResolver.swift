import Foundation

/// What the rarity service last reported: how many opted-in members hold each species
/// (spec override 1: one CloudKit counter per species plus a member counter).
public struct LeafShareCounts: Codable, Sendable, Hashable {
    /// The species catalogue the counts were collected against. Raise it whenever `species.json` gains species,
    /// so leaves added in an update read "New · rarity next week" until the counts catch up.
    public static let catalogueVersion = 1
    /// The member count below which no percentage is shown (D4).
    public static let memberThreshold = 1_000

    public var catalogueVersion: Int
    /// Opted-in members counted, or nil when the service hasn't published a count (no backend yet).
    public var members: Int?
    /// Members holding each species, keyed by species id.
    public var counts: [String: Int]
    /// The first day of the week the counts describe ("in the week of 29 Sep").
    public var weekStart: Date?

    public init(catalogueVersion: Int = LeafShareCounts.catalogueVersion, members: Int?, counts: [String: Int], weekStart: Date? = nil) {
        self.catalogueVersion = catalogueVersion
        self.members = members
        self.counts = counts
        self.weekStart = weekStart
    }

    /// What every build ships with until the rarity backend exists: no members, so "Rarity appears once…".
    public static let unconfigured = LeafShareCounts(members: nil, counts: [:])
}

/// Turns cached counts into the `MemberShare` state for one species (spec §5.7). Pure, so every state is tested.
public struct MemberShareResolver: Sendable {
    /// A successful fetch older than this reads as stale.
    public static let freshness: TimeInterval = 48 * 3600

    public var features: ShippedFeatures
    public var locale: Locale
    public var catalog: RewardCatalog

    public init(features: ShippedFeatures = .current, locale: Locale = .current, catalog: RewardCatalog = .shared) {
        self.features = features
        self.locale = locale
        self.catalog = catalog
    }

    /// - Parameters:
    ///   - counts: The last successful result, if any.
    ///   - fetchedAt: When `counts` arrived.
    ///   - isFetching: A request is in flight.
    ///   - lastFetchFailed: The most recent request failed (offline).
    public func share(
        for speciesID: String, counts: LeafShareCounts?, fetchedAt: Date?, now: Date, isFetching: Bool, lastFetchFailed: Bool
    ) -> MemberShare {
        guard let category = catalog.reward(forSpecies: speciesID)?.categoryID, features.isShipped(category) else {
            return .notEarnableYet
        }
        guard let counts else {
            return lastFetchFailed && !isFetching ? .neverFetched : .loading
        }
        guard let members = counts.members, members >= LeafShareCounts.memberThreshold else {
            return .notEnoughMembers(soFar: counts.members)
        }
        if counts.counts[speciesID] == nil, counts.catalogueVersion < LeafShareCounts.catalogueVersion {
            return .newSpecies
        }
        guard let estimate = ShareEstimate.wilson(count: counts.counts[speciesID] ?? 0, members: members) else {
            return .notEnoughMembers(soFar: members)
        }
        let display = MemberShareFormatter.format(estimate, locale: locale)
        let asOf = fetchedAt ?? now
        return now.timeIntervalSince(asOf) > Self.freshness ? .stale(display: display, asOf: asOf) : .value(display: display, asOf: asOf)
    }

    /// The numeric share behind a value, for "Rarest first" and "Your rarest". Nil when no percentage may be shown.
    public func estimate(for speciesID: String, counts: LeafShareCounts?) -> ShareEstimate? {
        guard let counts, let members = counts.members, members >= LeafShareCounts.memberThreshold,
              let category = catalog.reward(forSpecies: speciesID)?.categoryID, features.isShipped(category) else { return nil }
        if counts.counts[speciesID] == nil, counts.catalogueVersion < LeafShareCounts.catalogueVersion { return nil }
        return ShareEstimate.wilson(count: counts.counts[speciesID] ?? 0, members: members)
    }
}
