import Foundation
import Testing
@testable import MapleCore

/// The Goodnight tap as the sleep categories' source (review finding "no-behaviour-data-source").
@Suite("Nights: Goodnight to counters")
struct NightLedgerTests {
    /// Bedtime 23:00, wake 07:00, 45 minutes of wind-down.
    private let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)

    private func day(_ month: Int, _ day: Int) -> LocalDay { LocalDay(year: 2026, month: month, day: day) }

    /// The schedule saved (and the Sugar maple opened) at `date`.
    private func planted(at date: Date = at(2026, 10, 1, 21)) -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: date)
        snapshot.raise(.firstSteps, to: 1, at: date, calendar: utc)
        snapshot.runEngine(at: date, context: context)
        snapshot.openReveals(nil, at: date, context: context)
        return snapshot
    }

    /// Taps Goodnight on the evening of `night` at `hour:minute` (after midnight for hours before 18), then settles
    /// the next morning at 07:00.
    private func night(
        _ snapshot: inout CollectionSnapshot, _ night: LocalDay, goodnight: (hour: Int, minute: Int)?
    ) {
        if let goodnight {
            let tapDay = goodnight.hour >= 18 ? night : night.adding(days: 1, calendar: utc)
            snapshot.recordGoodnight(at: at(tapDay.year, tapDay.month, tapDay.day, goodnight.hour, goodnight.minute), context: context)
        }
        let morning = night.adding(days: 1, calendar: utc)
        snapshot.settleNights(at: at(morning.year, morning.month, morning.day, 7), context: context)
    }

    @Test("A night runs 18:00 to 18:00, is judged against bedtime, and settles at the next morning's start")
    func rules() {
        #expect(NightLedger.night(containing: at(2026, 10, 1, 23, 30), calendar: utc) == day(10, 1))
        #expect(NightLedger.night(containing: at(2026, 10, 2, 1), calendar: utc) == day(10, 1))
        #expect(NightLedger.night(containing: at(2026, 10, 2, 17, 59), calendar: utc) == day(10, 1))
        #expect(NightLedger.night(containing: at(2026, 10, 2, 18), calendar: utc) == day(10, 2))
        #expect(NightLedger.settleDate(of: day(10, 1), schedule: .standard, calendar: utc) == at(2026, 10, 2, 6))
        #expect(NightLedger.date(ClockTime(hour: 0, minute: 30), on: day(10, 1), calendar: utc) == at(2026, 10, 2, 0, 30))

        let bedtime = at(2026, 10, 1, 23)
        #expect(NightLedger.outcome(goodnight: at(2026, 10, 1, 23, 30), bedtime: bedtime) == .onTime)
        #expect(NightLedger.outcome(goodnight: at(2026, 10, 1, 23, 31), bedtime: bedtime) == .late)
        #expect(NightLedger.outcome(goodnight: at(2026, 10, 1, 21), bedtime: bedtime) == .onTime)
        #expect(NightLedger.outcome(goodnight: at(2026, 10, 1, 20, 59), bedtime: bedtime) == .early)
        #expect(NightLedger.outcome(goodnight: nil, bedtime: bedtime) == .untracked)

        // The install night counts when the schedule was saved at least 30 minutes before its bedtime.
        #expect(NightLedger.firstNight(setUpAt: at(2026, 10, 1, 21), schedule: .standard, calendar: utc) == day(10, 1))
        #expect(NightLedger.firstNight(setUpAt: at(2026, 10, 1, 22, 31), schedule: .standard, calendar: utc) == day(10, 2))
        #expect(NightLedger.firstNight(setUpAt: at(2026, 10, 1, 14), schedule: .standard, calendar: utc) == day(10, 1))
        #expect(NightLedger.firstNight(setUpAt: at(2026, 10, 2, 1), schedule: .standard, calendar: utc) == day(10, 2))
    }

    @Test("An on-time Goodnight earns a tracked night and an on-time bedtime the next morning, once")
    func onTimeNight() {
        var snapshot = planted()
        let recorded = snapshot.recordGoodnight(at: at(2026, 10, 1, 22, 50), context: context)
        #expect(recorded)
        #expect(snapshot.settleNights(at: at(2026, 10, 2, 5, 59), context: context).isEmpty)
        #expect(snapshot.counters[.nightsTracked] == nil)

        let unlocked = snapshot.settleNights(at: at(2026, 10, 2, 6, 30), context: context)
        #expect(unlocked.map(\.speciesID) == [species(.nightsTracked, rung: 0), species(.onTimeBedtimes, rung: 0)])
        #expect(snapshot.counters[.nightsTracked] == 1 && snapshot.counters[.onTimeBedtimes] == 1)
        #expect(snapshot.currentBedtimeRun == 1 && snapshot.counters[.bedtimeRun] == 1)
        #expect(snapshot.tendedDays == [day(10, 2)])
        #expect(snapshot.recentNights == [NightRecord(day: day(10, 1), onTime: true, fullNight: nil, scrollFree: nil)])
        // Earned in the morning, so they open at once (the first morning reveal).
        #expect(snapshot.revealable(at: at(2026, 10, 2, 6, 30), context: context).count == 2)

        // Settled once: later calls and late taps for that night change nothing.
        let settled = snapshot
        #expect(snapshot.settleNights(at: at(2026, 10, 2, 12), context: context).isEmpty)
        let late = snapshot.recordGoodnight(at: at(2026, 10, 2, 2), context: context)
        #expect(!late)
        #expect(snapshot == settled)
    }

    @Test("Nothing is recorded before the maple is planted")
    func beforePlanting() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 9))
        let recorded = snapshot.recordGoodnight(at: at(2026, 10, 1, 22, 50), context: context)
        #expect(!recorded)
        #expect(snapshot.settleNights(at: at(2026, 10, 3, 7), context: context).isEmpty)
        #expect(snapshot.counters.isEmpty)
    }

    @Test("Untracked and early nights add nothing on time; a late night is tracked")
    func outcomes() {
        var snapshot = planted()
        night(&snapshot, day(10, 1), goodnight: nil)                      // untracked
        night(&snapshot, day(10, 2), goodnight: (20, 30))                 // early: more than 2 h before 23:00
        night(&snapshot, day(10, 3), goodnight: (23, 45))                 // late
        #expect(snapshot.counters[.nightsTracked] == 2)
        #expect(snapshot.counters[.onTimeBedtimes] == nil)
        #expect(snapshot.currentBedtimeRun == 0)
        // Vitality hears only on-time and late nights; early and untracked ones are neutral.
        #expect(snapshot.recentNights.map(\.day) == [day(10, 3)])
        #expect(snapshot.nights.recent.map(\.outcome) == [.untracked, .early, .late])
    }

    @Test("A run forgives 2 slips in any 7 nights; the third ends it, and early nights are neutral")
    func runForgiveness() {
        var snapshot = planted()
        let plan: [(hour: Int, minute: Int)?] = [(22, 50), (23, 0), (23, 20), (23, 50), nil, (22, 40), (20, 0), (23, 10)]
        var runs: [Int] = []
        for (offset, goodnight) in plan.enumerated() {
            night(&snapshot, day(10, 1 + offset), goodnight: goodnight)
            runs.append(snapshot.currentBedtimeRun)
        }
        // on, on, on, late (forgiven), untracked (forgiven), on, early (neutral), on.
        #expect(runs == [1, 2, 3, 3, 3, 4, 4, 5])
        night(&snapshot, day(10, 9), goodnight: (23, 59))                 // a third slip within 7 nights
        #expect(snapshot.currentBedtimeRun == 0)
        #expect(snapshot.counters[.bedtimeRun] == 5)                      // the best run is kept
        #expect(snapshot.unlocks.contains { $0.speciesID == species(.bedtimeRun, rung: 0) })
        night(&snapshot, day(10, 10), goodnight: (22, 30))
        #expect(snapshot.currentBedtimeRun == 1)
    }

    @Test("A week with 5 on-time nights is steady when its last night settles")
    func steadyWeek() throws {
        let week = try #require(utc.dateInterval(of: .weekOfYear, for: at(2026, 10, 14, 12)))
        let start = LocalDay(week.start, calendar: utc)
        let end = LocalDay(week.end.addingTimeInterval(-1), calendar: utc)
        let eve = start.adding(days: -1, calendar: utc)
        var snapshot = planted(at: at(eve.year, eve.month, eve.day, 12))
        var night = start
        var index = 0
        while night <= end {
            self.night(&snapshot, night, goodnight: index < 5 ? (22, 45) : nil)
            if night < end { #expect(snapshot.counters[.steadyWeeks] == nil) }
            night = night.adding(days: 1, calendar: utc)
            index += 1
        }
        #expect(snapshot.counters[.steadyWeeks] == 1)

        // The next week has only 4 on-time nights: not steady.
        var next = end.adding(days: 1, calendar: utc)
        for offset in 0..<7 {
            self.night(&snapshot, next, goodnight: offset < 4 ? (22, 45) : nil)
            next = next.adding(days: 1, calendar: utc)
        }
        #expect(snapshot.counters[.steadyWeeks] == 1)
    }

    @Test("A season counts once, when its eighth steady week closes")
    func seasonInRhythm() {
        var snapshot = planted(at: at(2026, 8, 31, 12))
        var night = day(8, 31)
        var countAtSevenWeeks: Double?
        while night <= day(11, 29) {
            self.night(&snapshot, night, goodnight: (22, 45))
            if snapshot.counters[.steadyWeeks] == 7, countAtSevenWeeks == nil {
                countAtSevenWeeks = snapshot.counters[.seasonsInRhythm] ?? 0
            }
            night = night.adding(days: 1, calendar: utc)
        }
        #expect(countAtSevenWeeks == 0)
        #expect((snapshot.counters[.steadyWeeks] ?? 0) >= 12)
        #expect(snapshot.counters[.seasonsInRhythm] == 1)
        #expect(snapshot.counters[.onTimeBedtimes] == 91)
    }

    @Test("After weeks away only the last two weeks settle, and any run has ended")
    func longAbsence() {
        var snapshot = planted()
        for offset in 0..<5 { night(&snapshot, day(10, 1 + offset), goodnight: (22, 50)) }
        #expect(snapshot.currentBedtimeRun == 5)
        snapshot.settleNights(at: at(2026, 11, 20, 8), context: context)
        #expect(snapshot.nights.settledThrough == day(11, 19))
        #expect(snapshot.nights.recent.count == 14)
        #expect(snapshot.currentBedtimeRun == 0)
        #expect(snapshot.counters[.nightsTracked] == 5)
    }

    @Test("The ledger survives a save and an older file without it decodes")
    func coding() throws {
        var snapshot = planted()
        snapshot.recordGoodnight(at: at(2026, 10, 1, 22, 50), context: context)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(CollectionSnapshot.self, from: data) == snapshot)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["nights"] = nil
        let older = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.nights == NightLedger())
    }
}

@Suite("Review fixes: runs, vitality and reveals")
struct ReviewFixTests {
    private let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)

    @Test("A locked run leaf counts from the live run, not the best one")
    func liveRun() throws {
        let builder = LeafProgressBuilder(permissions: [], features: .current)
        let threeNights = species(.bedtimeRun, rung: 0)
        func row(current run: Int) throws -> LeafProgress {
            let rows = builder.progress(counters: [.bedtimeRun: 2], unlocks: [], history: [], today: LocalDay(year: 2026, month: 10, day: 10),
                                        calendar: utc, currentBedtimeRun: run)
            return try #require(rows.first { $0.speciesID == threeNights })
        }
        let broken = try row(current: 0)
        #expect(broken.threshold == 3 && broken.current == 0 && broken.remaining == 3)
        #expect(LeafRemainder(broken, phase: .evening).text == "3 nights")
        #expect(LeafRemainder(broken, phase: .evening).amount == "0 of 3")
        #expect(!LeafRemainder(broken, phase: .evening).showsBar)
        let live = try row(current: 2)
        #expect(LeafRemainder(live, phase: .evening).text == "Tonight")
        #expect((live.estimatedDays ?? 99) < (broken.estimatedDays ?? 0))

        // Through the snapshot: the best run is 2, the live run 0.
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 9))
        snapshot.raise(.bedtimeRun, to: 2, at: at(2026, 10, 3, 7), calendar: utc)
        snapshot.currentBedtimeRun = 0
        let progress = try #require(snapshot.progress(at: at(2026, 10, 4, 21), context: context).first { $0.speciesID == threeNights })
        #expect(LeafRemainder(progress, phase: .evening).text == "3 nights")
    }

    @Test("Vitality only reads the week before today: a six-week gap is full vitality")
    func vitalityWindow() {
        let august = (1...7).map {
            NightRecord(day: LocalDay(year: 2026, month: 8, day: $0), onTime: false, fullNight: nil, scrollFree: nil)
        }
        let then = Vitality(nights: august, today: LocalDay(year: 2026, month: 8, day: 8), calendar: utc)
        #expect(abs(then.value - 0.4) < 1e-9 && then.isQuiet)
        let october = Vitality(nights: august, today: LocalDay(year: 2026, month: 10, day: 1), calendar: utc)
        #expect(october.value == 1 && !october.isQuiet)
        // Tonight counts once it is recorded; a week and a day ago doesn't.
        let edge = Vitality(nights: august, today: LocalDay(year: 2026, month: 8, day: 14), calendar: utc)
        #expect(abs(edge.value - 0.4) < 1e-9)
        #expect(Vitality(nights: august, today: LocalDay(year: 2026, month: 8, day: 15), calendar: utc).value == 1)
    }

    @Test("Leaves opened in Evening are placed after Wind-down begins; held leaves never open")
    func revealAcrossWindDown() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 21))
        snapshot.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 21), context: context)
        snapshot.openReveals(nil, at: at(2026, 10, 1, 21, 5), context: context)
        snapshot.record([.nightsTracked: 1], at: at(2026, 10, 2, 14), calendar: utc)    // pending at once
        snapshot.runEngine(at: at(2026, 10, 2, 14), context: context)
        snapshot.record([.onTimeBedtimes: 1], at: at(2026, 10, 2, 21), calendar: utc)   // evening: held
        snapshot.runEngine(at: at(2026, 10, 2, 21), context: context)

        let sessionStart = at(2026, 10, 2, 22, 14)                     // Evening; wind-down starts 22:15
        let place = at(2026, 10, 2, 22, 16)
        #expect(snapshot.phase(at: sessionStart, context: context) == .evening)
        #expect(snapshot.phase(at: place, context: context) == .windDown)
        #expect(snapshot.revealable(at: sessionStart, context: context).map(\.speciesID) == ["rubrum"])

        var unchanged = snapshot
        #expect(unchanged.openReveals(["rubrum"], at: place, context: context).isEmpty)

        let placed = snapshot.openReveals(["rubrum", "palmatum"], at: place, eligibleAt: sessionStart, context: context)
        #expect(placed.map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealedAt["rubrum"] == place)
        #expect(snapshot.revealsOpened == 2)
        #expect(snapshot.waiting.map(\.speciesID) == ["palmatum"])
    }
}
