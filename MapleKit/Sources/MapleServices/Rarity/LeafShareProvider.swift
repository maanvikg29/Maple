import Foundation
import MapleCore

/// Where "% of members have this leaf" comes from (spec §5.7 and override 1).
///
/// A provider returns the latest per-species holder counts and the member count. `LeafShareStore` caches the
/// result, refetches at most once a day and turns it into `MemberShare` states.
///
/// TODO(CloudKit): add `CloudKitLeafShareProvider` once Maple is on the paid Developer Program (CloudKit needs it).
/// The design is fixed by spec override 1:
/// - Maple's CloudKit **public** database holds one counter record per species (record name = species id,
///   field `count`) and one member counter record (`members`), plus the catalogue version.
/// - An opted-in install (`CollectionStore.rarityConsent == .included`) increments `members` once, and a species
///   counter when it unlocks that species; on opting in it backfills its existing leaves, and on opting out it
///   decrements, best effort. Writes retry on `serverRecordChanged` (optimistic locking).
/// - Nothing else is stored: no per-member record, no health data.
/// - `fetchCounts()` reads the counters (with `CKFetchRecordZoneChangesOperation` or a query) and returns them as
///   `LeafShareCounts`; `share = count / members` with a Wilson 95% interval happens in `MemberShareResolver`.
/// Until then every build ships `UnconfiguredLeafShareProvider`.
nonisolated public protocol LeafShareProvider: Sendable {
    /// Identifies the provider in the cache, so a cache written by another provider is ignored.
    var identifier: String { get }
    /// The latest counts. Throws when offline.
    func fetchCounts() async throws -> LeafShareCounts
}

/// The production provider until the rarity backend exists: always "Rarity appears once 1,000 members take part".
nonisolated public struct UnconfiguredLeafShareProvider: LeafShareProvider {
    public init() {}

    public var identifier: String { "unconfigured" }

    public func fetchCounts() async throws -> LeafShareCounts {
        .unconfigured
    }
}
