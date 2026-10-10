import Foundation
import MapleCore
import Observation

/// The last successful rarity fetch, cached on disk with its time.
nonisolated public struct LeafShareCache: Codable, Sendable, Equatable {
    public var providerID: String
    public var counts: LeafShareCounts
    public var fetchedAt: Date

    public init(providerID: String, counts: LeafShareCounts, fetchedAt: Date) {
        self.providerID = providerID
        self.counts = counts
        self.fetchedAt = fetchedAt
    }
}

/// How many members hold each leaf (spec §5.7). Screens read `share(for:)` and hand it to `MemberShareLabel`;
/// the app calls `refreshIfNeeded()` when it comes to the foreground.
///
/// States: `.loading` before the first answer, `.value` under 48 hours old, `.stale` after, `.notEnoughMembers`
/// under 1,000 members, `.neverFetched` offline with no cache, `.newSpecies` for leaves newer than the counts,
/// `.notEarnableYet` for unshipped categories. Opting out of the stats never changes what the member sees.
@Observable
public final class LeafShareStore {
    /// The provider is asked at most this often.
    public static let refetchInterval: TimeInterval = 24 * 3600

    public private(set) var cache: LeafShareCache?
    public private(set) var isFetching = false
    public private(set) var lastFetchFailed = false
    public var features: ShippedFeatures
    public var clock: MapleClock
    public var locale: Locale

    @ObservationIgnored private let provider: any LeafShareProvider
    @ObservationIgnored private let storage: JSONStorage<LeafShareCache>

    public init(
        provider: any LeafShareProvider, storage: JSONStorage<LeafShareCache>, features: ShippedFeatures = .current,
        clock: MapleClock = .live, locale: Locale = .current
    ) {
        self.provider = provider
        self.storage = storage
        self.features = features
        self.clock = clock
        self.locale = locale
        cache = storage.load().flatMap { $0.providerID == provider.identifier ? $0 : nil }
    }

    public var providerIdentifier: String { provider.identifier }

    /// The share for one species, in every state the UI must handle.
    public func share(for speciesID: String) -> MemberShare {
        resolver.share(for: speciesID, counts: cache?.counts, fetchedAt: cache?.fetchedAt, now: clock.now(),
                       isFetching: isFetching, lastFetchFailed: lastFetchFailed)
    }

    /// The numeric share behind a fresh value ("Rarest first", "Your rarest"). Nil in every other state.
    public func estimate(for speciesID: String) -> ShareEstimate? {
        guard case .value = share(for: speciesID) else { return nil }
        return resolver.estimate(for: speciesID, counts: cache?.counts)
    }

    /// Members counted, rounded down to the nearest 100, once there are enough to show percentages
    /// ("Out of 12,400 members…").
    public var memberCount: Int? {
        guard let members = cache?.counts.members, members >= LeafShareCounts.memberThreshold else { return nil }
        return members / 100 * 100
    }

    /// The week the counts describe.
    public var weekStart: Date? { cache?.counts.weekStart }

    /// Fetches unless a successful fetch is less than a day old (or `force`). Failures keep the cache.
    public func refreshIfNeeded(force: Bool = false) async {
        guard !isFetching else { return }
        if !force, let cache, clock.now().timeIntervalSince(cache.fetchedAt) < Self.refetchInterval { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let counts = try await provider.fetchCounts()
            let fresh = LeafShareCache(providerID: provider.identifier, counts: counts, fetchedAt: clock.now())
            cache = fresh
            storage.save(fresh)
            lastFetchFailed = false
        } catch {
            lastFetchFailed = true
        }
    }

    private var resolver: MemberShareResolver {
        MemberShareResolver(features: features, locale: locale)
    }
}
