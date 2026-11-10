import Foundation
import Testing
@testable import MapleCore

@Suite("Member share states")
struct MemberShareResolverTests {
    private let now = at(2026, 10, 10, 9)
    private let en = Locale(identifier: "en_US")

    private func counts(members: Int?, version: Int = LeafShareCounts.catalogueVersion, _ counts: [String: Int] = [:]) -> LeafShareCounts {
        LeafShareCounts(catalogueVersion: version, members: members, counts: counts, weekStart: at(2026, 9, 28))
    }

    private func share(
        _ species: String = "saccharinum", counts: LeafShareCounts?, fetchedAt: Date? = nil, fetching: Bool = false,
        failed: Bool = false, features: ShippedFeatures = .current
    ) -> MemberShare {
        MemberShareResolver(features: features, locale: en).share(
            for: species, counts: counts, fetchedAt: fetchedAt ?? now, now: now, isFetching: fetching, lastFetchFailed: failed
        )
    }

    @Test("Unshipped categories are not earnable yet, whatever the data")
    func notEarnable() {
        #expect(share("buergerianum", counts: nil) == .notEarnableYet)
        #expect(share("buergerianum", counts: counts(members: 5_000, ["buergerianum": 40])) == .notEarnableYet)
        #expect(share("buergerianum", counts: counts(members: 5_000, ["buergerianum": 40]), features: .all) != .notEarnableYet)
        #expect(share("not-a-species", counts: nil) == .notEarnableYet)
    }

    @Test("Without a cache: loading while fetching, never fetched after a failure")
    func noCache() {
        #expect(share(counts: nil, fetching: true) == .loading)
        #expect(share(counts: nil) == .loading)
        #expect(share(counts: nil, failed: true) == .neverFetched)
    }

    @Test("Under 1,000 members: no percentage, with the count when published")
    func threshold() {
        #expect(share(counts: counts(members: nil)) == .notEnoughMembers(soFar: nil))
        #expect(share(counts: counts(members: 640, ["saccharinum": 300])) == .notEnoughMembers(soFar: 640))
        #expect(share(counts: counts(members: 999, ["saccharinum": 300])) == .notEnoughMembers(soFar: 999))
        #expect(share(counts: counts(members: 1_000, ["saccharinum": 300])) == .value(display: "30%", asOf: now))
    }

    @Test("Fresh under 48 hours, stale after")
    func freshness() {
        let data = counts(members: 12_400, ["saccharinum": 2_728])
        #expect(share(counts: data, fetchedAt: now.addingTimeInterval(-47 * 3600)) == .value(display: "22%", asOf: now.addingTimeInterval(-47 * 3600)))
        let old = now.addingTimeInterval(-49 * 3600)
        #expect(share(counts: data, fetchedAt: old) == .stale(display: "22%", asOf: old))
        // A failed refresh never hides a cached value.
        #expect(share(counts: data, fetchedAt: old, failed: true) == .stale(display: "22%", asOf: old))
    }

    @Test("A species missing from an older catalogue is new; from the same one it has no members yet")
    func newSpecies() {
        #expect(share(counts: counts(members: 12_400, version: LeafShareCounts.catalogueVersion - 1, ["saccharum": 11_000])) == .newSpecies)
        #expect(share(counts: counts(members: 12_400, ["saccharum": 11_000])) == .value(display: "Under 0.1%", asOf: now))
    }

    @Test("Values use the Wilson interval and the formatter")
    func values() {
        #expect(share(counts: counts(members: 1_200, ["saccharinum": 3])) == .value(display: "Under 1%", asOf: now))
        #expect(share(counts: counts(members: 12_400, ["saccharinum": 12_400])) == .value(display: "Over 99%", asOf: now))
        let estimate = MemberShareResolver(features: .current, locale: en)
            .estimate(for: "saccharinum", counts: counts(members: 12_400, ["saccharinum": 2_728]))
        #expect(estimate.map { abs($0.percent - 22) < 1e-9 } == true)
    }
}
