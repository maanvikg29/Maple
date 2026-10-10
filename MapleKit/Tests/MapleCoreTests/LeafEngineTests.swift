import Foundation
import Testing
@testable import MapleCore

@Suite("Leaf engine")
struct LeafEngineTests {
    private let engine = LeafEngine()
    private let october = at(2026, 10, 10, 7, 30)

    @Test("No counters, no leaves")
    func empty() {
        #expect(engine.newUnlocks(counters: [:], existing: [], at: october, season: .autumn).isEmpty)
    }

    @Test("Setup awards the sugar maple")
    func firstSteps() throws {
        let unlocks = engine.newUnlocks(counters: [.firstSteps: 1], existing: [], at: october, season: .autumn)
        let first = try #require(unlocks.first)
        #expect(unlocks.count == 1)
        #expect(first.speciesID == "saccharum")
        #expect(first.date == october)
        #expect(first.season == .autumn)
        #expect(first.colourway == .autumn)
        #expect(!first.revealed)
        #expect(!first.seen)
    }

    @Test("Every met rung unlocks at once, in canonical order")
    func everyMetRung() {
        let unlocks = engine.newUnlocks(counters: [.nightsTracked: 7, .onTimeBedtimes: 3, .firstSteps: 1],
                                        existing: [], at: october, season: .autumn)
        #expect(unlocks.map(\.speciesID) == ["saccharum", "rubrum", "saccharinum", "nigrum"]
            + RewardCatalog.shared.rungs(in: .onTimeBedtimes).prefix(2).map(\.speciesID))
    }

    @Test("Thresholds are inclusive and fractional counters work")
    func thresholds() {
        let below = engine.newUnlocks(counters: [.focusHours: 3.99], existing: [], at: october, season: .autumn)
        #expect(below.isEmpty)
        let at4 = engine.newUnlocks(counters: [.focusHours: 4.0], existing: [], at: october, season: .autumn)
        #expect(at4.count == 1)
    }

    @Test("Running twice adds nothing")
    func idempotent() {
        let counters: [RewardCategoryID: Double] = [.firstSteps: 1, .nightsTracked: 30, .steadyWeeks: 6, .focusDays: 14]
        let first = engine.newUnlocks(counters: counters, existing: [], at: october, season: .autumn)
        #expect(!first.isEmpty)
        let second = engine.newUnlocks(counters: counters, existing: first, at: october.addingTimeInterval(3600), season: .winter)
        #expect(second.isEmpty)
        // Raising one counter adds only that category's new rungs.
        var raised = counters
        raised[.nightsTracked] = 60
        let third = engine.newUnlocks(counters: raised, existing: first, at: october, season: .autumn)
        #expect(third.count == 1)
        #expect(third.first?.speciesID == RewardCatalog.shared.rungs(in: .nightsTracked).first { $0.threshold == 60 }?.speciesID)
    }

    @Test("Every leaf can be earned exactly once")
    func everything() {
        var counters: [RewardCategoryID: Double] = [:]
        for category in RewardCatalog.shared.categories {
            counters[category.id] = category.ladder.last ?? 0
        }
        let all = engine.newUnlocks(counters: counters, existing: [], at: october, season: .autumn)
        #expect(all.count == 155)
        #expect(Set(all.map(\.speciesID)).count == 155)
        #expect(engine.newUnlocks(counters: counters, existing: all, at: october, season: .autumn).isEmpty)
    }

    @Test("Pressed colourway follows the season; evergreens stay green")
    func colourways() throws {
        let winter = at(2026, 1, 15, 8)
        let unlocks = engine.newUnlocks(counters: [.nightsTracked: 1, .steadyWeeks: 1], existing: [], at: winter,
                                        hemisphere: .northern, calendar: utc)
        let rubrum = try #require(unlocks.first { $0.speciesID == "rubrum" })
        #expect(rubrum.season == .winter)
        #expect(rubrum.colourway == .frost)
        let sempervirens = try #require(unlocks.first { $0.speciesID == "sempervirens" })
        #expect(sempervirens.colourway == .summer)
    }

    @Test("Season comes from the hemisphere")
    func hemisphere() throws {
        let unlocks = engine.newUnlocks(counters: [.nightsTracked: 1], existing: [], at: october, hemisphere: .southern, calendar: utc)
        let rubrum = try #require(unlocks.first)
        #expect(rubrum.season == .spring)
        #expect(rubrum.colourway == .spring)
    }
}

@Suite("Held and pending reveals")
struct RevealScheduleTests {
    // Standard schedule: wind-down 22:15, bed 23:00, wake 07:00 → Evening from 20:15, Morning from 06:00.
    private let schedule = WeeklySleepSchedule.standard

    private func unlock(_ id: String = "rubrum", at date: Date, revealed: Bool = false) -> LeafUnlock {
        LeafUnlock(speciesID: id, date: date, season: .autumn, colourway: .autumn, revealed: revealed)
    }

    private func release(_ date: Date, _ id: String = "rubrum") -> Date {
        RevealSchedule.releaseDate(for: unlock(id, at: date), schedule: schedule, calendar: utc)
    }

    @Test("Daytime unlocks are pending at once")
    func daytime() {
        #expect(release(at(2026, 10, 10, 14)) == at(2026, 10, 10, 14))
        #expect(release(at(2026, 10, 10, 6)) == at(2026, 10, 10, 6))
        #expect(release(at(2026, 10, 10, 20, 14)) == at(2026, 10, 10, 20, 14))
    }

    @Test("Unlocks from Evening start are held until the next Morning start")
    func evening() {
        #expect(release(at(2026, 10, 10, 20, 15)) == at(2026, 10, 11, 6))
        #expect(release(at(2026, 10, 10, 23, 30)) == at(2026, 10, 11, 6))
        #expect(release(at(2026, 10, 11, 2)) == at(2026, 10, 11, 6))
        #expect(release(at(2026, 10, 11, 5, 59)) == at(2026, 10, 11, 6))
    }

    @Test("The setup leaf is never held")
    func setupLeaf() {
        #expect(release(at(2026, 10, 10, 23, 30), "saccharum") == at(2026, 10, 10, 23, 30))
    }

    @Test("Windows that wrap midnight")
    func wrap() {
        // Bed 01:00, wake 09:00, 60m wind-down → wind-down 00:00, Evening from 22:00, Morning from 08:00.
        let late = SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60)
        func release(_ date: Date) -> Date {
            RevealSchedule.releaseDate(for: unlock(at: date), schedule: .everyNight(late), calendar: utc)
        }
        #expect(release(at(2026, 10, 10, 21, 59)) == at(2026, 10, 10, 21, 59))
        #expect(release(at(2026, 10, 10, 22)) == at(2026, 10, 11, 8))
        #expect(release(at(2026, 10, 11, 0, 30)) == at(2026, 10, 11, 8))
        #expect(release(at(2026, 10, 11, 8)) == at(2026, 10, 11, 8))
    }

    @Test("Pending and held partition the unrevealed leaves")
    func partition() {
        let day = unlock("rubrum", at: at(2026, 10, 10, 14))
        let night = unlock("nigrum", at: at(2026, 10, 10, 21))
        let opened = unlock("saccharinum", at: at(2026, 10, 10, 9), revealed: true)
        let all = [day, night, opened]
        let evening = at(2026, 10, 10, 21, 30)
        #expect(RevealSchedule.pending(all, at: evening, schedule: schedule, calendar: utc).map(\.speciesID) == ["rubrum"])
        #expect(RevealSchedule.held(all, at: evening, schedule: schedule, calendar: utc).map(\.speciesID) == ["nigrum"])
        let morning = at(2026, 10, 11, 6, 30)
        #expect(RevealSchedule.pending(all, at: morning, schedule: schedule, calendar: utc).map(\.speciesID) == ["rubrum", "nigrum"])
        #expect(RevealSchedule.held(all, at: morning, schedule: schedule, calendar: utc).isEmpty)
        #expect(RevealSchedule.isHeld(night, at: evening, schedule: schedule, calendar: utc))
        #expect(!RevealSchedule.isHeld(night, at: morning, schedule: schedule, calendar: utc))
    }
}
