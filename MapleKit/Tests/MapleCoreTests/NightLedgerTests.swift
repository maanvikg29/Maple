import Foundation
import Testing
@testable import MapleCore

/// Apple Health's nights as the sleep categories' only source (spec D9, rewards.json): the ledger takes
/// `SleepNightObservation`s, never a Goodnight tap.
@Suite("Nights: Apple Health to counters")
struct NightLedgerTests {
    /// Bedtime 23:00, wake 07:00, 45 minutes of wind-down; Apple Health connected; a 7-hour sleep need.
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)

    private func day(_ month: Int, _ day: Int) -> LocalDay { LocalDay(year: 2026, month: month, day: day) }

    private func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date {
        MapleCoreTests.at(day.year, day.month, day.day, hour, minute)
    }

    /// The schedule saved (and the Sugar maple opened) at `date`.
    private func planted(at date: Date = MapleCoreTests.at(2026, 10, 1, 21)) -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: date)
        snapshot.raise(.firstSteps, to: 1, at: date, calendar: utc)
        snapshot.runEngine(at: date, context: context)
        snapshot.openReveals(nil, at: date, context: context)
        return snapshot
    }

    /// Apple Health's main episode for the evening of `night`: onset at `onset` (after midnight for hours before
    /// 18), final wake at `wake` the next morning.
    private func sleep(
        _ night: LocalDay, onset: (hour: Int, minute: Int), wake: (hour: Int, minute: Int) = (7, 0), asleep: Double? = 450,
        source: SleepSource = .watchOrTracker
    ) -> SleepNightObservation {
        let onsetDay = onset.hour >= 18 ? night : night.adding(days: 1, calendar: utc)
        let morning = night.adding(days: 1, calendar: utc)
        return SleepNightObservation(night: night, onset: at(onsetDay, onset.hour, onset.minute),
                                     finalWake: at(morning, wake.hour, wake.minute), asleepMinutes: asleep, source: source)
    }

    /// Records the night's sleep (nil: nothing in Apple Health) at 07:00 the next morning, when it settles.
    @discardableResult
    private func night(
        _ snapshot: inout CollectionSnapshot, _ night: LocalDay, onset: (hour: Int, minute: Int)?,
        wake: (hour: Int, minute: Int) = (7, 0), asleep: Double? = 450, source: SleepSource = .watchOrTracker,
        context: CollectionContext? = nil
    ) -> [LeafUnlock] {
        let observations = onset.map { [sleep(night, onset: $0, wake: wake, asleep: asleep, source: source)] } ?? []
        return snapshot.recordSleep(observations, at: at(night.adding(days: 1, calendar: utc), 7), context: context ?? self.context)
    }

    @Test("A night runs 18:00 to 18:00, is judged by sleep onset against bedtime, and settles at the next morning's start")
    func rules() {
        #expect(NightLedger.night(containing: MapleCoreTests.at(2026, 10, 1, 23, 30), calendar: utc) == day(10, 1))
        #expect(NightLedger.night(containing: MapleCoreTests.at(2026, 10, 2, 1), calendar: utc) == day(10, 1))
        #expect(NightLedger.night(containing: MapleCoreTests.at(2026, 10, 2, 17, 59), calendar: utc) == day(10, 1))
        #expect(NightLedger.night(containing: MapleCoreTests.at(2026, 10, 2, 18), calendar: utc) == day(10, 2))
        #expect(NightLedger.settleDate(of: day(10, 1), schedule: .standard, calendar: utc) == MapleCoreTests.at(2026, 10, 2, 6))
        #expect(NightLedger.date(ClockTime(hour: 0, minute: 30), on: day(10, 1), calendar: utc) == MapleCoreTests.at(2026, 10, 2, 0, 30))

        let bedtime = MapleCoreTests.at(2026, 10, 1, 23)
        #expect(NightLedger.outcome(onset: MapleCoreTests.at(2026, 10, 1, 23, 30), bedtime: bedtime) == .onTime)
        #expect(NightLedger.outcome(onset: MapleCoreTests.at(2026, 10, 1, 23, 31), bedtime: bedtime) == .late)
        #expect(NightLedger.outcome(onset: MapleCoreTests.at(2026, 10, 1, 21), bedtime: bedtime) == .onTime)
        #expect(NightLedger.outcome(onset: MapleCoreTests.at(2026, 10, 1, 20, 59), bedtime: bedtime) == .early)

        // The install night is the night the schedule was first saved in.
        #expect(NightLedger.firstNight(setUpAt: MapleCoreTests.at(2026, 10, 1, 21), calendar: utc) == day(10, 1))
        #expect(NightLedger.firstNight(setUpAt: MapleCoreTests.at(2026, 10, 2, 1), calendar: utc) == day(10, 1))
        #expect(NightLedger.firstNight(setUpAt: MapleCoreTests.at(2026, 10, 1, 14), calendar: utc) == day(9, 30))

        // A main episode needs 3 hours from onset to final wake.
        #expect(sleep(day(10, 1), onset: (23, 0), wake: (2, 0)).isMainEpisode)
        #expect(!sleep(day(10, 1), onset: (23, 0), wake: (1, 59)).isMainEpisode)
        // iPhone's in-bed estimate carries no asleep time.
        #expect(sleep(day(10, 1), onset: (23, 0), asleep: 480, source: .iPhoneInBed).asleepMinutes == nil)
        #expect(SleepNightObservation(onset: MapleCoreTests.at(2026, 10, 2, 0, 40), finalWake: MapleCoreTests.at(2026, 10, 2, 7),
                                      asleepMinutes: 360, source: .otherApp, calendar: utc).night == day(10, 1))
    }

    @Test("An on-time night from Apple Health earns its leaves the next morning, once")
    func onTimeNight() {
        var snapshot = planted()
        let observation = sleep(day(10, 1), onset: (22, 50), wake: (7, 5), asleep: 470)
        // Before the morning starts the night waits.
        #expect(snapshot.recordSleep([observation], at: MapleCoreTests.at(2026, 10, 2, 5, 59), context: context).isEmpty)
        #expect(snapshot.counters[.nightsTracked] == nil)
        // Kept with the zone it was recorded in, so it is judged there whenever it settles.
        var stamped = observation
        stamped.timeZoneIdentifier = utc.timeZone.identifier
        #expect(snapshot.nights.pending == [stamped])

        let unlocked = snapshot.recordSleep([], at: MapleCoreTests.at(2026, 10, 2, 6, 30), context: context)
        #expect(unlocked.map(\.speciesID) == [species(.nightsTracked, rung: 0), species(.onTimeBedtimes, rung: 0)])
        #expect(snapshot.counters[.nightsTracked] == 1 && snapshot.counters[.onTimeBedtimes] == 1)
        #expect(snapshot.counters[.steadyMornings] == 1 && snapshot.counters[.fullNights] == 1)
        #expect(snapshot.currentBedtimeRun == 1 && snapshot.counters[.bedtimeRun] == 1)
        #expect(snapshot.tendedDays == [day(10, 2)])
        #expect(snapshot.recentNights == [NightRecord(day: day(10, 1), onTime: true, fullNight: true, scrollFree: nil)])
        #expect(snapshot.nights.pending.isEmpty)
        // Earned in the morning, so they open at once (the first morning reveal).
        #expect(snapshot.revealable(at: MapleCoreTests.at(2026, 10, 2, 6, 30), context: context).count == 2)

        // Recording the same night again (the importer sends the last few nights every time) changes nothing.
        let settled = snapshot
        #expect(snapshot.recordSleep([observation], at: MapleCoreTests.at(2026, 10, 2, 12), context: context).isEmpty)
        #expect(snapshot == settled)
    }

    @Test("Nothing is recorded before the maple is planted")
    func beforePlanting() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: MapleCoreTests.at(2026, 10, 1, 9))
        #expect(snapshot.recordSleep([sleep(day(10, 1), onset: (22, 50))], at: MapleCoreTests.at(2026, 10, 3, 7), context: context).isEmpty)
        #expect(snapshot.counters.isEmpty)
        #expect(snapshot.nights == NightLedger())
    }

    @Test("Untracked, early, late, short and in-bed nights each count only for what they are")
    func outcomes() {
        var snapshot = planted()
        night(&snapshot, day(10, 1), onset: nil)                                      // nothing in Apple Health
        night(&snapshot, day(10, 2), onset: (20, 30), asleep: 600)                    // early: more than 2 h before 23:00
        night(&snapshot, day(10, 3), onset: (23, 45), wake: (7, 40), asleep: 380)     // late, not steady, not full
        night(&snapshot, day(10, 4), onset: (23, 0), wake: (1, 30))                   // a 2.5 h episode: untracked
        night(&snapshot, day(10, 5), onset: (22, 30), wake: (6, 45), source: .iPhoneInBed)
        #expect(snapshot.nights.recent.map(\.outcome) == [.untracked, .early, .late, .untracked, .onTime])
        #expect(snapshot.counters[.nightsTracked] == 3)
        #expect(snapshot.counters[.onTimeBedtimes] == 1)
        #expect(snapshot.counters[.steadyMornings] == 2)
        // Full nights need asleep time: iPhone's in-bed estimate never earns one.
        #expect(snapshot.counters[.fullNights] == 1)
        #expect(snapshot.currentBedtimeRun == 1)
        // Vitality hears on-time and late nights and full nights; untracked ones are neutral.
        #expect(snapshot.recentNights == [
            NightRecord(day: day(10, 2), onTime: nil, fullNight: true, scrollFree: nil),
            NightRecord(day: day(10, 3), onTime: false, fullNight: false, scrollFree: nil),
            NightRecord(day: day(10, 5), onTime: true, fullNight: nil, scrollFree: nil),
        ])
    }

    @Test("Counting starts on the install night, when setup finished before sleep began")
    func installNight() {
        // Saved 15 minutes before bedtime: the night is tracked, but no schedule judges it yet.
        var late = planted(at: MapleCoreTests.at(2026, 10, 1, 22, 45))
        night(&late, day(10, 1), onset: (23, 5))
        #expect(late.nights.recent.map(\.outcome) == [.unscheduled])
        #expect(late.counters[.nightsTracked] == 1 && late.counters[.onTimeBedtimes] == nil)
        #expect(late.currentBedtimeRun == 0)
        night(&late, day(10, 2), onset: (23, 5))
        #expect(late.counters[.onTimeBedtimes] == 1 && late.currentBedtimeRun == 1)

        // Asleep before setup finished: the install night doesn't count.
        var after = planted(at: MapleCoreTests.at(2026, 10, 1, 23, 30))
        night(&after, day(10, 1), onset: (23, 10))
        #expect(after.counters[.nightsTracked] == nil)

        // Set up the next morning: that night and every night before it are history, not leaves (rewards.md).
        var morning = planted(at: MapleCoreTests.at(2026, 10, 2, 10))
        let unlocked = morning.recordSleep([sleep(day(9, 30), onset: (23, 0)), sleep(day(10, 1), onset: (23, 0))],
                                           at: MapleCoreTests.at(2026, 10, 2, 11), context: context)
        #expect(unlocked.isEmpty)
        #expect(morning.counters[.nightsTracked] == nil)
        #expect(morning.nights.recent.map(\.night) == [day(10, 1)])
    }

    @Test("Steady mornings are within 30 minutes of wake time; full nights reach the sleep need less 30 minutes")
    func morningsAndFullNights() {
        var need = context
        need.sleepNeedMinutes = 480
        var snapshot = planted()
        night(&snapshot, day(10, 1), onset: (23, 0), wake: (7, 30), asleep: 450, context: need)
        night(&snapshot, day(10, 2), onset: (23, 0), wake: (6, 29), asleep: 449, context: need)
        night(&snapshot, day(10, 3), onset: (23, 0), asleep: 460, source: .otherApp, context: need)
        night(&snapshot, day(10, 4), onset: (23, 0), source: .iPhoneInBed, context: need)
        #expect(snapshot.nights.recent.map(\.steadyMorning) == [true, false, true, true])
        #expect(snapshot.nights.recent.map(\.fullNight) == [true, false, true, nil])
        #expect(snapshot.counters[.steadyMornings] == 3)
        #expect(snapshot.counters[.fullNights] == 2)
        #expect(snapshot.counters[.nightsTracked] == 4 && snapshot.counters[.onTimeBedtimes] == 4)
    }

    @Test("A run forgives 2 slips in any 7 nights; the third ends it, and early nights are neutral")
    func runForgiveness() {
        var snapshot = planted()
        let plan: [(hour: Int, minute: Int)?] = [(22, 50), (23, 0), (23, 20), (23, 50), nil, (22, 40), (20, 0), (23, 10)]
        var runs: [Int] = []
        for (offset, onset) in plan.enumerated() {
            night(&snapshot, day(10, 1 + offset), onset: onset)
            runs.append(snapshot.currentBedtimeRun)
        }
        // on, on, on, late (forgiven), untracked (forgiven), on, early (neutral), on.
        #expect(runs == [1, 2, 3, 3, 3, 4, 4, 5])
        night(&snapshot, day(10, 9), onset: (23, 59))                     // a third slip within 7 nights
        #expect(snapshot.currentBedtimeRun == 0)
        #expect(snapshot.counters[.bedtimeRun] == 5)                      // the best run is kept
        #expect(snapshot.unlocks.contains { $0.speciesID == species(.bedtimeRun, rung: 0) })
        night(&snapshot, day(10, 10), onset: (22, 30))
        #expect(snapshot.currentBedtimeRun == 1)
    }

    @Test("A week with 5 on-time nights is steady when its last night settles")
    func steadyWeek() throws {
        let week = try #require(utc.dateInterval(of: .weekOfYear, for: MapleCoreTests.at(2026, 10, 14, 12)))
        let start = LocalDay(week.start, calendar: utc)
        let end = LocalDay(week.end.addingTimeInterval(-1), calendar: utc)
        let eve = start.adding(days: -1, calendar: utc)
        var snapshot = planted(at: at(eve, 12))
        var night = start
        var index = 0
        while night <= end {
            self.night(&snapshot, night, onset: index < 5 ? (22, 45) : nil)
            if night < end { #expect(snapshot.counters[.steadyWeeks] == nil) }
            night = night.adding(days: 1, calendar: utc)
            index += 1
        }
        #expect(snapshot.counters[.steadyWeeks] == 1)

        // The next week has only 4 on-time nights: not steady.
        var next = end.adding(days: 1, calendar: utc)
        for offset in 0..<7 {
            self.night(&snapshot, next, onset: offset < 4 ? (22, 45) : nil)
            next = next.adding(days: 1, calendar: utc)
        }
        #expect(snapshot.counters[.steadyWeeks] == 1)
    }

    @Test("A week belongs to the season of its Thursday")
    func weekSeason() {
        var mondayFirst = utc
        mondayFirst.firstWeekday = 2
        // Monday 23 February to Sunday 1 March 2026: its Thursday is in February, so it is a winter week.
        let thursday = NightLedger.thursday(start: day(2, 23), end: day(3, 1), calendar: mondayFirst)
        #expect(thursday == day(2, 26))
        #expect(NightLedger.seasonBlock(of: thursday) == NightLedger.seasonBlock(of: LocalDay(year: 2025, month: 12, day: 15)))
        #expect(NightLedger.seasonBlock(of: thursday) != NightLedger.seasonBlock(of: day(3, 1)))
        // Monday 31 August to Sunday 6 September: an autumn week.
        #expect(NightLedger.thursday(start: day(8, 31), end: day(9, 6), calendar: mondayFirst) == day(9, 3))
        #expect(NightLedger.seasonBlock(of: day(9, 3)) == NightLedger.seasonBlock(of: day(11, 30)))
    }

    @Test("A season counts once, when its eighth steady week closes")
    func seasonInRhythm() {
        var snapshot = planted(at: MapleCoreTests.at(2026, 8, 31, 12))
        var night = day(8, 31)
        var countAtSevenWeeks: Double?
        while night <= day(11, 29) {
            self.night(&snapshot, night, onset: (22, 45))
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

    @Test("Late data upgrades a settled night for 72 hours, replays the run, and never downgrades")
    func lateData() {
        var snapshot = planted()
        night(&snapshot, day(10, 1), onset: (22, 50))
        night(&snapshot, day(10, 2), onset: nil)                          // the Watch hasn't synced yet
        night(&snapshot, day(10, 3), onset: (22, 50))
        #expect(snapshot.currentBedtimeRun == 2)
        #expect(snapshot.counters[.nightsTracked] == 2)

        // The Watch syncs the next day: the night is upgraded, and the run counts it.
        let unlocked = snapshot.recordSleep([sleep(day(10, 2), onset: (22, 55))], at: MapleCoreTests.at(2026, 10, 4, 9), context: context)
        #expect(snapshot.nights.recent.map(\.outcome) == [.onTime, .onTime, .onTime])
        #expect(snapshot.counters[.nightsTracked] == 3 && snapshot.counters[.onTimeBedtimes] == 3)
        #expect(snapshot.currentBedtimeRun == 3 && snapshot.counters[.bedtimeRun] == 3)
        #expect(unlocked.contains { $0.speciesID == species(.bedtimeRun, rung: 0) })
        #expect(snapshot.recentNights.map(\.day) == [day(10, 1), day(10, 2), day(10, 3)])

        // A worse reading never downgrades a night.
        let upgraded = snapshot
        #expect(snapshot.recordSleep([sleep(day(10, 3), onset: (23, 50), wake: (9, 0), source: .iPhoneInBed)],
                                     at: MapleCoreTests.at(2026, 10, 4, 10), context: context).isEmpty)
        #expect(snapshot == upgraded)

        // After 72 hours a night is final.
        night(&snapshot, day(10, 4), onset: nil)
        snapshot.recordSleep([sleep(day(10, 4), onset: (22, 50))], at: MapleCoreTests.at(2026, 10, 8, 7), context: context)
        #expect(snapshot.nights.recent.first { $0.night == day(10, 4) }?.outcome == .untracked)
        #expect(snapshot.counters[.nightsTracked] == 3)
    }

    @Test("A late upgrade can complete a steady week that has already closed")
    func lateSteadyWeek() throws {
        let week = try #require(utc.dateInterval(of: .weekOfYear, for: MapleCoreTests.at(2026, 10, 14, 12)))
        let start = LocalDay(week.start, calendar: utc)
        let end = LocalDay(week.end.addingTimeInterval(-1), calendar: utc)
        var snapshot = planted(at: at(start.adding(days: -1, calendar: utc), 12))
        var night = start
        var index = 0
        while night <= end {
            self.night(&snapshot, night, onset: index < 4 ? (22, 45) : nil)
            night = night.adding(days: 1, calendar: utc)
            index += 1
        }
        // Four on-time nights, then three slips: not steady, and the run has ended.
        #expect(snapshot.counters[.steadyWeeks] == nil)
        #expect(snapshot.currentBedtimeRun == 0)

        // The last night arrives later that morning.
        snapshot.recordSleep([sleep(end, onset: (22, 40))], at: at(end.adding(days: 1, calendar: utc), 12), context: context)
        #expect(snapshot.counters[.steadyWeeks] == 1)
        #expect(snapshot.currentBedtimeRun == 5)
        #expect(snapshot.counters[.bedtimeRun] == 5)
    }

    @Test("A schedule change applies from the next night (18:00 cut-off)")
    func scheduleChange() {
        var snapshot = planted(at: MapleCoreTests.at(2026, 10, 1, 12))
        var current = context
        night(&snapshot, day(10, 1), onset: (23, 10), context: current)                     // vs 23:00: on time

        // At 20:00 on the 2nd, bedtime moves to 22:00: that night has begun under 23:00.
        let earlier = SleepSchedule(bedtime: ClockTime(hour: 22), wake: ClockTime(hour: 7), windDownMinutes: 45)
        snapshot.scheduleChanged(from: .standard, to: earlier, at: MapleCoreTests.at(2026, 10, 2, 20), calendar: utc)
        current.schedule = earlier
        night(&snapshot, day(10, 2), onset: (23, 10), context: current)                     // still 23:00: on time
        night(&snapshot, day(10, 3), onset: (23, 10), context: current)                     // 22:00: late

        // At 10:00 on the 4th, bedtime moves to 23:30: from that evening on.
        let later = SleepSchedule(bedtime: ClockTime(hour: 23, minute: 30), wake: ClockTime(hour: 7), windDownMinutes: 45)
        snapshot.scheduleChanged(from: earlier, to: later, at: MapleCoreTests.at(2026, 10, 4, 10), calendar: utc)
        current.schedule = later
        night(&snapshot, day(10, 4), onset: (23, 50), context: current)                     // vs 23:30: on time

        #expect(snapshot.nights.recent.map(\.outcome) == [.untracked, .onTime, .onTime, .late, .onTime])
        #expect(snapshot.counters[.onTimeBedtimes] == 3)
        // The first schedule ever saved replaces nothing.
        var fresh = CollectionSnapshot.empty(profileID: UUID(), createdAt: MapleCoreTests.at(2026, 10, 1, 9))
        fresh.scheduleChanged(from: .standard, to: earlier, at: MapleCoreTests.at(2026, 10, 1, 9), calendar: utc)
        #expect(fresh.nights.pastSchedules.isEmpty)
    }

    @Test("Full nights become earnable once Apple Health has delivered asleep time")
    func sleepTracker() {
        var snapshot = planted()
        #expect(snapshot.permissions(in: context) == [.appleHealth])
        #expect(snapshot.availability(of: .fullNights, context: context) == .needsSleepTracker)
        night(&snapshot, day(10, 1), onset: (22, 50), source: .iPhoneInBed)
        #expect(snapshot.permissions(in: context) == [.appleHealth])
        night(&snapshot, day(10, 2), onset: (22, 50))
        #expect(snapshot.permissions(in: context) == [.appleHealth, .sleepTracker])
        #expect(snapshot.availability(of: .fullNights, context: context) == .available)

        // Without Apple Health granted, nothing is implied.
        var none = context
        none.permissions = []
        #expect(snapshot.permissions(in: none).isEmpty)
        #expect(snapshot.availability(of: .nightsTracked, context: none) == .needsAppleHealth)
    }

    @Test("After weeks away the nights settle as untracked, and any run has ended")
    func longAbsence() {
        var snapshot = planted()
        for offset in 0..<5 { night(&snapshot, day(10, 1 + offset), onset: (22, 50)) }
        #expect(snapshot.currentBedtimeRun == 5)
        snapshot.recordSleep([], at: MapleCoreTests.at(2026, 11, 20, 8), context: context)
        #expect(snapshot.nights.settledThrough == day(11, 19))
        #expect(snapshot.nights.recent.count == 14)
        #expect(snapshot.currentBedtimeRun == 0)
        #expect(snapshot.counters[.nightsTracked] == 5)
        #expect(snapshot.counters[.bedtimeRun] == 5)
    }

    /// Review finding "catchup-drops-tapped-night", on the Apple Health ledger.
    @Test("A night Apple Health has data for settles after any absence, even one of years")
    func absenceAfterRecordedNight() {
        func recordedBeforeAbsence() -> CollectionSnapshot {
            var snapshot = planted()
            night(&snapshot, day(10, 1), onset: (22, 50))
            // The 2nd's night arrives before its morning; then the app isn't opened for a while.
            snapshot.recordSleep([sleep(day(10, 2), onset: (22, 50))], at: MapleCoreTests.at(2026, 10, 3, 5), context: context)
            #expect(snapshot.nights.pending.count == 1)
            return snapshot
        }
        for absence in [14, 20] {
            var snapshot = recordedBeforeAbsence()
            snapshot.recordSleep([], at: at(day(10, 3).adding(days: absence, calendar: utc), 8), context: context)
            #expect(snapshot.counters[.nightsTracked] == 2)
            #expect(snapshot.counters[.onTimeBedtimes] == 2)
            #expect(snapshot.counters[.bedtimeRun] == 2)
            #expect(snapshot.currentBedtimeRun == 0)
        }
        // More than two years away: the night is still settled before the untracked years are skipped.
        var snapshot = recordedBeforeAbsence()
        snapshot.recordSleep([], at: MapleCoreTests.at(2028, 11, 1, 8), context: context)
        #expect(snapshot.counters[.nightsTracked] == 2)
        #expect(snapshot.counters[.onTimeBedtimes] == 2)
        #expect(snapshot.nights.settledThrough == LocalDay(year: 2028, month: 10, day: 31))
        #expect(snapshot.nights.pending.isEmpty)
        #expect(snapshot.currentBedtimeRun == 0)
        // With nothing waiting, years away still skip straight to the last two.
        var away = planted()
        night(&away, day(10, 1), onset: (22, 50))
        away.recordSleep([], at: MapleCoreTests.at(2030, 1, 1, 8), context: context)
        #expect(away.nights.settledThrough == LocalDay(year: 2029, month: 12, day: 31))
        #expect(away.nights.recent.count == 14)
        #expect(away.currentBedtimeRun == 0)
    }

    /// Review finding "ledger-outcome-settle-timezone", on the Apple Health ledger.
    @Test("A night is judged in the zone it was spent in, even when it settles after a flight")
    func timeZones() {
        func calendar(_ identifier: String) -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            calendar.locale = enGB
            return calendar
        }
        let newYork = calendar("America/New_York"), london = calendar("Europe/London")
        let losAngeles = calendar("America/Los_Angeles")
        let setup = MapleCoreTests.at(2026, 10, 1, 12, in: newYork)
        func rules(_ calendar: Calendar) -> NightLedger.Rules {
            NightLedger.Rules(setup: setup, schedule: .standard, sleepNeedMinutes: 420, calendar: calendar)
        }
        func settledThroughFourth() -> NightLedger {
            var ledger = NightLedger()
            _ = ledger.settle(at: MapleCoreTests.at(2026, 10, 5, 12, in: newYork), rules: rules(newYork))
            #expect(ledger.settledThrough == day(10, 4))
            return ledger
        }
        // Asleep at 23:05 in New York on the 5th: five minutes after bedtime.
        let observation = SleepNightObservation(
            night: day(10, 5), onset: MapleCoreTests.at(2026, 10, 5, 23, 5, in: newYork),
            finalWake: MapleCoreTests.at(2026, 10, 6, 7, in: newYork), asleepMinutes: 470, source: .watchOrTracker
        )
        for settledIn in [newYork, london, losAngeles] {
            var ledger = settledThroughFourth()
            // Recorded in New York before the morning; settled the next evening wherever the member is by then.
            _ = ledger.record([observation], at: MapleCoreTests.at(2026, 10, 6, 5, in: newYork), rules: rules(newYork))
            let changes = ledger.settle(at: MapleCoreTests.at(2026, 10, 6, 18, in: settledIn), rules: rules(settledIn))
            #expect(changes.settled == [day(10, 5)])
            #expect(ledger.recent.last?.outcome == .onTime)
            #expect(ledger.recent.last?.steadyMorning == true)
            #expect(changes.increases[.onTimeBedtimes] == 1)
        }
        // Apple Health's own zone wins over the one in force when the night is recorded.
        var ledger = settledThroughFourth()
        var tagged = observation
        tagged.timeZoneIdentifier = "America/New_York"
        _ = ledger.record([tagged], at: MapleCoreTests.at(2026, 10, 6, 18, in: london), rules: rules(london))
        #expect(ledger.recent.last?.night == day(10, 5))
        #expect(ledger.recent.last?.outcome == .onTime)
    }

    @Test("The ledger survives a save; older files, with or without it, decode")
    func coding() throws {
        var snapshot = planted()
        night(&snapshot, day(10, 1), onset: (22, 50))
        snapshot.recordSleep([sleep(day(10, 2), onset: (22, 50))], at: MapleCoreTests.at(2026, 10, 3, 5), context: context)
        #expect(snapshot.nights.pending.count == 1)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(CollectionSnapshot.self, from: data) == snapshot)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["nights"] = nil
        let older = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.nights == NightLedger())

        // The Goodnight build's ledger: its taps are dropped, its settled nights kept.
        object["nights"] = [
            "goodnights": [["night": "2026-10-01", "at": 0, "bedtime": ["hour": 23, "minute": 0]]],
            "settledThrough": "2026-09-30", "recent": [["night": "2026-09-30", "outcome": "onTime"]],
            "runStart": "2026-09-30", "steadyWeeks": [String](),
        ] as [String: Any]
        let goodnightBuild = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(goodnightBuild.nights.pending.isEmpty)
        #expect(goodnightBuild.nights.settledThrough == day(9, 30))
        #expect(goodnightBuild.nights.recent == [NightLedger.Night(night: day(9, 30), outcome: .onTime)])
        #expect(goodnightBuild.profileID == snapshot.profileID)
    }
}

@Suite("Review fixes: runs, vitality and reveals")
struct ReviewFixTests {
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)

    @Test("A locked run leaf counts from the live run, not the best one")
    func liveRun() throws {
        let builder = LeafProgressBuilder(permissions: [.appleHealth], features: .current)
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
