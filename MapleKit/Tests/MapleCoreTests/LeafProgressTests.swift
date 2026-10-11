import Foundation
import Testing
@testable import MapleCore

@Suite("Local days")
struct LocalDayTests {
    @Test("A local day follows the calendar's time zone")
    func timeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let lateUTC = at(2026, 10, 10, 20)
        #expect(LocalDay(lateUTC, calendar: utc) == LocalDay(year: 2026, month: 10, day: 10))
        #expect(LocalDay(lateUTC, calendar: tokyo) == LocalDay(year: 2026, month: 10, day: 11))
    }

    @Test("Days add across month ends and compare in order")
    func arithmetic() {
        let day = LocalDay(year: 2026, month: 10, day: 30)
        #expect(day.adding(days: 3, calendar: utc) == LocalDay(year: 2026, month: 11, day: 2))
        #expect(day.adding(days: -30, calendar: utc) == LocalDay(year: 2026, month: 9, day: 30))
        #expect(LocalDay(year: 2026, month: 9, day: 30) < day)
        #expect(day.startDate(in: utc) == at(2026, 10, 30))
        #expect(LocalDay(year: 2026, month: 10, day: 1).days(until: day, calendar: utc) == 29)
    }

    @Test("Encodes as an ISO date string")
    func coding() throws {
        let data = try JSONEncoder().encode([LocalDay(year: 2026, month: 3, day: 7)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-03-07\"]")
        let decoded = try JSONDecoder().decode([LocalDay].self, from: data)
        #expect(decoded == [LocalDay(year: 2026, month: 3, day: 7)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([LocalDay].self, from: Data("[\"Oct 7\"]".utf8)) }
    }
}

@Suite("Shipped features and availability")
struct AvailabilityTests {
    @Test("Only M1 categories ship today")
    func shipped() {
        let shipped = RewardCategoryID.allCases.filter { ShippedFeatures.current.isShipped($0) }
        #expect(shipped == [.firstLeaf, .restedNights, .firstSteps, .nightsTracked, .onTimeBedtimes, .bedtimeRun, .steadyWeeks,
                            .seasonsInRhythm, .steadyMornings, .fullNights])
        #expect(!ShippedFeatures.current.focus)
        #expect(!ShippedFeatures.current.sleepSounds)
        #expect(!ShippedFeatures.current.checkIns)
        #expect(ShippedFeatures.all.focus && ShippedFeatures.all.sleepSounds && ShippedFeatures.all.checkIns)
        #expect(RewardCategoryID.allCases.allSatisfy { ShippedFeatures.all.isShipped($0) })
    }

    @Test("Availability is requirement × permissions × shipped releases")
    func availability() {
        let none = GrantedPermissions()
        let health: GrantedPermissions = [.appleHealth]
        let tracker: GrantedPermissions = [.appleHealth, .sleepTracker]
        let m1 = ShippedFeatures.current
        #expect(LeafAvailability(category: .firstLeaf, permissions: none, features: m1) == .available)
        #expect(LeafAvailability(category: .restedNights, permissions: none, features: m1) == .needsAppleHealth)
        #expect(LeafAvailability(category: .restedNights, permissions: health, features: m1) == .available)
        #expect(LeafAvailability(category: .restedNights, permissions: tracker, features: m1) == .available)
        // An unshipped category is dormant whatever the permissions.
        #expect(LeafAvailability(category: .hoursSaved, permissions: [.screenTime], features: m1) == .dormant)
        #expect(LeafAvailability(category: .bedtimeKept, permissions: tracker, features: m1) == .dormant)
        #expect(LeafAvailability(category: .hoursSaved, permissions: none, features: .all) == .needsScreenTime)
        #expect(LeafAvailability(category: .hoursSaved, permissions: [.screenTime], features: .all) == .available)
    }
}

@Suite("Pace")
struct PaceTests {
    private let today = LocalDay(year: 2026, month: 10, day: 10)

    @Test("Rate is units gained over the last 14 days, divided by 14")
    func rate() {
        let history = [
            DailyCounters(day: LocalDay(year: 2026, month: 9, day: 20), counters: [.restedNights: 1]),
            DailyCounters(day: LocalDay(year: 2026, month: 9, day: 26), counters: [.restedNights: 3]),
            DailyCounters(day: LocalDay(year: 2026, month: 10, day: 1), counters: [.restedNights: 6]),
        ]
        // The baseline is the counter at the end of 26 Sep (14 days before today).
        let rate = LeafPace.rate(for: .restedNights, current: 10, history: history, today: today, calendar: utc)
        #expect(abs(rate - 0.5) < 1e-9)
    }

    @Test("A member newer than the window counts from zero")
    func newMember() {
        let history = [DailyCounters(day: LocalDay(year: 2026, month: 10, day: 8), counters: [.restedNights: 1])]
        let rate = LeafPace.rate(for: .restedNights, current: 2, history: history, today: today, calendar: utc)
        #expect(abs(rate - 2.0 / 14) < 1e-9)
    }

    @Test("Estimate uses the rate, or the design pace when the rate is zero")
    func estimate() {
        #expect(LeafPace.estimatedDays(remaining: 4, rate: 0.5, category: .restedNights) == 8)
        let designPace = RewardCategoryInfo(.restedNights).designPace
        #expect(LeafPace.estimatedDays(remaining: 7, rate: 0, category: .restedNights) == 7 / designPace)
        #expect(LeafPace.estimatedDays(remaining: 0, rate: 0, category: .restedNights) == 0)
    }
}

@Suite("Leaf progress")
struct LeafProgressBuilderTests {
    private let today = LocalDay(year: 2026, month: 10, day: 10)
    private let morning = at(2026, 10, 10, 8)

    private func build(
        counters: [RewardCategoryID: Double], unlocks: [LeafUnlock] = [], history: [DailyCounters] = [],
        permissions: GrantedPermissions = [], features: ShippedFeatures = .current
    ) -> [LeafProgress] {
        LeafProgressBuilder(permissions: permissions, features: features)
            .progress(counters: counters, unlocks: unlocks, history: history, today: today, calendar: utc)
    }

    @Test("Every species once, in canonical category then rung order")
    func allSpecies() {
        let rows = build(counters: [:])
        #expect(rows.count == 155)
        #expect(Set(rows.map(\.speciesID)).count == 155)
        let expected = RewardCatalog.shared.categories.flatMap { RewardCatalog.shared.rungs(in: $0.id).map(\.speciesID) }
        #expect(rows.map(\.speciesID) == expected)
        #expect(rows.first?.speciesID == "saccharum")
    }

    @Test("States follow unlocks: earned once revealed, waiting before")
    func states() throws {
        let opened = LeafUnlock(speciesID: "saccharum", date: morning, season: .autumn, colourway: .autumn, revealed: true)
        let waiting = LeafUnlock(speciesID: "rubrum", date: morning, season: .autumn, colourway: .autumn)
        let rows = build(counters: [.firstLeaf: 1, .restedNights: 1], unlocks: [opened, waiting])
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.speciesID, $0) })
        #expect(byID["saccharum"]?.state == .earned(opened))
        #expect(byID["rubrum"]?.state == .waiting(waiting))
        #expect(byID["saccharinum"]?.state == .locked)
        #expect(byID["saccharum"]?.estimatedDays == nil)
        #expect(byID["rubrum"]?.estimatedDays == nil)
    }

    @Test("Current is the category counter, clamped to each threshold")
    func current() throws {
        let rows = build(counters: [.restedNights: 5])
        let ladder = rows.filter { $0.category == .restedNights }
        #expect(ladder.map(\.current).prefix(3) == [3, 5, 5])
        let second = try #require(ladder.first { $0.threshold == 14 })
        #expect(second.remaining == 9)
    }

    @Test("Estimates come from the 14-day rate, else the design pace; none when unavailable")
    func estimates() throws {
        let history = [DailyCounters(day: LocalDay(year: 2026, month: 9, day: 26), counters: [.restedNights: 3])]
        let rows = build(counters: [.restedNights: 10], history: history, permissions: [.appleHealth])
        let fourteen = try #require(rows.first { $0.category == .restedNights && $0.threshold == 14 })
        #expect(fourteen.estimatedDays == 8)                       // 4 to go at 0.5 a day
        let fresh = build(counters: [:], permissions: [.appleHealth])
        let first = try #require(fresh.first { $0.category == .restedNights && $0.threshold == 3 })
        #expect(first.estimatedDays == 3 / RewardCategoryInfo(.restedNights).designPace)
        // Without Apple Health no sleep leaf has an estimate (D9: left out of pacing).
        let without = build(counters: [.restedNights: 10], history: history)
        let nights = try #require(without.first { $0.category == .restedNights && $0.threshold == 14 })
        #expect(nights.availability == .needsAppleHealth)
        #expect(nights.estimatedDays == nil)
        #expect(nights.current == 10)
        let focus = try #require(rows.first { $0.category == .hoursSaved })
        #expect(focus.availability == .dormant)
        #expect(focus.estimatedDays == nil)
    }
}

@Suite("Collection snapshot")
struct CollectionSnapshotTests {
    @Test("Round-trips through JSON, with counters keyed by category id")
    func roundTrip() throws {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 9))
        snapshot.counters = [.firstLeaf: 1, .restedNights: 4.5]
        snapshot.unlocks = [LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 1, 9), season: .autumn, colourway: .autumn, revealed: true)]
        snapshot.revealedAt = ["saccharum": at(2026, 10, 1, 9, 5)]
        snapshot.history = [DailyCounters(day: LocalDay(year: 2026, month: 10, day: 1), counters: [.firstLeaf: 1])]
        snapshot.tendedDays = [LocalDay(year: 2026, month: 10, day: 2)]
        snapshot.recentNights = [NightRecord(day: LocalDay(year: 2026, month: 10, day: 2), onTime: true, fullNight: nil, scrollFree: nil)]
        snapshot.pinnedSpeciesID = "rubrum"
        snapshot.featuredSpeciesID = "saccharum"
        snapshot.rarityConsent = .included
        snapshot.revealsOpened = 1

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"rested_nights\":4.5"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(CollectionSnapshot.self, from: data) == snapshot)
    }

    @Test("Decodes older or newer files: missing fields default, unknown categories are skipped")
    func tolerant() throws {
        let json = """
        {"profileID":"7F3C1C9E-1C3B-4E5E-8E0B-2B0F6C2D4A11","createdAt":"2026-10-01T09:00:00Z",
         "counters":{"first_steps":1,"moon_walks":3}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CollectionSnapshot.self, from: Data(json.utf8))
        // "first_steps" is the old table's key for the first leaf.
        #expect(snapshot.counters == [.firstLeaf: 1])
        #expect(snapshot.unlocks.isEmpty)
        #expect(snapshot.rarityConsent == .notAsked)
        #expect(snapshot.revealsOpened == 0)
    }

    @Test("The tree seed comes from the profile id and never changes")
    func seed() {
        let id = UUID()
        let snapshot = CollectionSnapshot.empty(profileID: id, createdAt: .now)
        #expect(snapshot.treeSeed == SplitMix64.seed(for: id))
        #expect(CollectionSnapshot.empty(profileID: id, createdAt: .distantPast).treeSeed == snapshot.treeSeed)
    }
}
