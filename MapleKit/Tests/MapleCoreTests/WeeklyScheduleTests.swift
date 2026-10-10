import Foundation
import Testing
@testable import MapleCore

/// Weekday and weekend schedules: which nights are weekend nights, their times as dates, the phases they drive, and
/// how they are saved.
@Suite("Weekly schedule")
struct WeeklyScheduleTests {
    /// Bed 23:00, up 07:00 on weekdays; bed 00:30, up 09:00 on weekends, with an hour of wind-down.
    private let week = WeeklySleepSchedule(
        weekday: .standard,
        weekend: SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)
    )

    private func day(_ month: Int, _ day: Int) -> LocalDay { LocalDay(year: 2026, month: month, day: day) }

    private func calendar(_ zone: String = "UTC", locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    @Test("A night is a weekend night when the morning it wakes into is a weekend day: Friday and Saturday nights")
    func weekendNights() {
        // 8 October 2026 is a Thursday.
        #expect(WeeklySleepSchedule.variant(forNight: day(10, 8), calendar: utc) == .weekday)    // Thursday → Friday
        #expect(WeeklySleepSchedule.variant(forNight: day(10, 9), calendar: utc) == .weekend)    // Friday → Saturday
        #expect(WeeklySleepSchedule.variant(forNight: day(10, 10), calendar: utc) == .weekend)   // Saturday → Sunday
        #expect(WeeklySleepSchedule.variant(forNight: day(10, 11), calendar: utc) == .weekday)   // Sunday → Monday
        #expect(WeeklySleepSchedule.weekendEvenings(calendar: utc) == [6, 7])

        #expect(week.schedule(forNight: day(10, 8), calendar: utc) == .standard)
        #expect(week.schedule(forNight: day(10, 9), calendar: utc) == week.weekend)
        #expect(week.schedule(forNight: day(10, 11), calendar: utc) == .standard)
        // Without a weekend schedule every night is the same.
        #expect(WeeklySleepSchedule.standard.schedule(forNight: day(10, 9), calendar: utc) == .standard)
    }

    @Test("Where the weekend is Friday and Saturday, Thursday and Friday nights are weekend nights")
    func fridaySaturdayWeekends() {
        for locale in ["he_IL", "ar_SA"] {
            let calendar = calendar("Asia/Jerusalem", locale: locale)
            #expect(WeeklySleepSchedule.weekendEvenings(calendar: calendar) == [5, 6], "\(locale)")
            #expect(WeeklySleepSchedule.variant(forNight: day(10, 8), calendar: calendar) == .weekend)   // Thursday → Friday
            #expect(WeeklySleepSchedule.variant(forNight: day(10, 10), calendar: calendar) == .weekday)  // Saturday → Sunday
        }
    }

    @Test("Each night's times are dates; bedtimes after midnight fall on the next day, per variant")
    func nightTimes() {
        let thursday = week.times(forNight: day(10, 8), calendar: utc)
        #expect(thursday.variant == .weekday)
        #expect(thursday.windDownStart == at(2026, 10, 8, 22, 15))
        #expect(thursday.bedtime == at(2026, 10, 8, 23))
        #expect(thursday.wake == at(2026, 10, 9, 7))
        #expect(thursday.morningStart == at(2026, 10, 9, 6))

        let friday = week.times(forNight: day(10, 9), calendar: utc)
        #expect(friday.variant == .weekend)
        #expect(friday.windDownStart == at(2026, 10, 9, 23, 30))
        #expect(friday.bedtime == at(2026, 10, 10, 0, 30))
        #expect(friday.wake == at(2026, 10, 10, 9))
        #expect(friday.morningStart == at(2026, 10, 10, 8))

        // A weekday bedtime after midnight too.
        let late = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60))
        let tuesday = late.times(forNight: day(10, 6), calendar: utc)
        #expect(tuesday.windDownStart == at(2026, 10, 7, 0))
        #expect(tuesday.bedtime == at(2026, 10, 7, 1))
        #expect(tuesday.wake == at(2026, 10, 7, 9))
    }

    @Test("A day's morning follows last night's wake; its evening, wind-down and night follow tonight's schedule")
    func phasesAcrossTheWeek() {
        func phase(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> NowPhase {
            NowPhase.resolve(date: at(2026, month, day, hour, minute), weekly: week, calendar: utc)
        }
        // Friday: up at 07:00 after a weekday night; tonight is a weekend night (wind-down 23:30, bed 00:30).
        #expect(phase(10, 9, 6) == .morning)
        #expect(phase(10, 9, 10) == .day)
        #expect(phase(10, 9, 21, 29) == .day)
        #expect(phase(10, 9, 21, 30) == .evening)
        #expect(phase(10, 9, 23, 29) == .evening)
        #expect(phase(10, 9, 23, 30) == .windDown)
        #expect(phase(10, 10, 0, 29) == .windDown)
        #expect(phase(10, 10, 0, 30) == .night)
        // Saturday: the weekend morning starts at 08:00.
        #expect(phase(10, 10, 7, 59) == .night)
        #expect(phase(10, 10, 8) == .morning)
        #expect(phase(10, 10, 11, 59) == .morning)
        #expect(phase(10, 10, 12) == .day)
        // Sunday: a weekend morning, then a weekday evening (Sunday night wakes into Monday).
        #expect(phase(10, 11, 7, 30) == .night)
        #expect(phase(10, 11, 8) == .morning)
        #expect(phase(10, 11, 20, 15) == .evening)
        #expect(phase(10, 11, 22, 15) == .windDown)
        #expect(phase(10, 11, 23) == .night)
        // Monday: back to 06:00.
        #expect(phase(10, 12, 5, 59) == .night)
        #expect(phase(10, 12, 6) == .morning)

        // Next starts cross the variants.
        let windows = PhaseWindows(weekly: week)
        #expect(windows.nextStart(of: .morning, after: at(2026, 10, 9, 23), calendar: utc) == at(2026, 10, 10, 8))
        #expect(windows.nextStart(of: .windDown, after: at(2026, 10, 9, 12), calendar: utc) == at(2026, 10, 9, 23, 30))
        #expect(windows.nextStart(of: .night, after: at(2026, 10, 11, 12), calendar: utc) == at(2026, 10, 11, 23))
    }

    @Test("Tonight is the night named by today's evening, until the next morning starts")
    func tonight() {
        #expect(week.currentNight(at: at(2026, 10, 9, 15), calendar: utc) == day(10, 9))
        #expect(week.tonight(at: at(2026, 10, 9, 15), calendar: utc) == week.weekend)
        // At 02:00 on Saturday it is still Friday night.
        #expect(week.currentNight(at: at(2026, 10, 10, 2), calendar: utc) == day(10, 9))
        #expect(week.tonight(at: at(2026, 10, 10, 2), calendar: utc) == week.weekend)
        // Sunday morning: tonight is a weekday night; last night (which set this morning's wake) was a weekend one.
        #expect(week.tonight(at: at(2026, 10, 11, 8, 30), calendar: utc) == .standard)
        #expect(week.lastNight(at: at(2026, 10, 11, 8, 30), calendar: utc) == week.weekend)
        #expect(week.tonight(at: at(2026, 10, 12, 5), calendar: utc) == .standard)
    }

    @Test("Upcoming nights start with tonight and give each night's wind-down, bedtime, wake and morning")
    func upcoming() {
        let nights = week.upcoming(from: at(2026, 10, 8, 12), days: 4, calendar: utc)
        #expect(nights.map(\.night) == [day(10, 8), day(10, 9), day(10, 10), day(10, 11)])
        #expect(nights.map(\.variant) == [.weekday, .weekend, .weekend, .weekday])
        #expect(nights.map(\.bedtime) == [at(2026, 10, 8, 23), at(2026, 10, 10, 0, 30), at(2026, 10, 11, 0, 30), at(2026, 10, 11, 23)])
        #expect(nights.map(\.morningStart) == [at(2026, 10, 9, 6), at(2026, 10, 10, 8), at(2026, 10, 11, 8), at(2026, 10, 12, 6)])
        #expect(nights[1].windDownStart == at(2026, 10, 9, 23, 30))
        // In the small hours tonight is still the night under way.
        #expect(week.upcoming(from: at(2026, 10, 10, 2), days: 1, calendar: utc).map(\.night) == [day(10, 9)])
        #expect(week.upcoming(from: at(2026, 10, 10, 2), days: 0, calendar: utc).isEmpty)
    }

    @Test("Daylight-saving nights keep their wall-clock times, and every sample lands in its phase")
    func daylightSaving() {
        let london = calendar("Europe/London", locale: "en_GB")
        // Clocks go back at 02:00 on Sunday 25 October 2026: Saturday night is an hour longer.
        let saturday = week.times(forNight: day(10, 24), calendar: london)
        #expect(saturday.variant == .weekend)
        #expect(saturday.bedtime == at(2026, 10, 25, 0, 30, in: london))
        #expect(saturday.wake == at(2026, 10, 25, 9, in: london))
        #expect(saturday.wake.timeIntervalSince(saturday.bedtime) == 9.5 * 3600)
        #expect(NowPhase.resolve(date: at(2026, 10, 25, 8, 30, in: london), weekly: week, calendar: london) == .morning)
        #expect(NowPhase.resolve(date: at(2026, 10, 25, 7, 59, in: london), weekly: week, calendar: london) == .night)

        // Clocks go forward at 01:00 on Sunday 29 March 2026; a bedtime in the missing hour still comes before wake.
        let gap = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 1, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 45))
        let spring = gap.times(forNight: day(3, 28), calendar: london)
        #expect(spring.windDownStart < spring.bedtime)
        #expect(spring.bedtime < spring.wake)
        #expect(spring.wake == at(2026, 3, 29, 9, in: london))

        for (weekly, dayOfChange) in [(week, at(2026, 10, 25, 12, in: london)), (week, at(2026, 3, 29, 12, in: london)),
                                      (gap, at(2026, 3, 29, 12, in: london))] {
            for phase in NowPhase.allCases {
                let date = PhaseWindows(weekly: weekly).sampleDate(in: phase, onDayOf: dayOfChange, calendar: london)
                #expect(NowPhase.resolve(date: date, weekly: weekly, calendar: london) == phase)
                #expect(LocalDay(date, calendar: london) == LocalDay(dayOfChange, calendar: london))
            }
        }
    }

    @Test("A weekend equal to the weekday schedule is the same every night")
    func normalised() {
        #expect(WeeklySleepSchedule(weekday: .standard, weekend: .standard) == .standard)
        var weekly = week
        #expect(weekly.differsOnWeekends)
        weekly.weekend = .standard
        #expect(weekly.weekend == nil)
        #expect(!weekly.differsOnWeekends)
        weekly = week
        weekly.weekday = week.weekend!
        #expect(weekly == .everyNight(week.weekend!))
    }

    @Test("Saved as the weekday schedule's own fields plus a weekend: older files read as every night, losslessly")
    func coding() throws {
        // A schedule saved before weekend schedules existed.
        let old = Data(#"{"bedtime":{"hour":22,"minute":30},"wake":{"hour":6,"minute":30},"windDownMinutes":30}"#.utf8)
        let migrated = try JSONDecoder().decode(WeeklySleepSchedule.self, from: old)
        #expect(migrated == .everyNight(SleepSchedule(bedtime: ClockTime(hour: 22, minute: 30), wake: ClockTime(hour: 6, minute: 30), windDownMinutes: 30)))
        #expect(migrated.weekend == nil)
        // Re-encoded unchanged, it is the same JSON object.
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? NSDictionary
        #expect(reencoded == (try JSONSerialization.jsonObject(with: old) as? NSDictionary))

        // A week round-trips, and an older build still reads its weekday schedule.
        let data = try JSONEncoder().encode(week)
        #expect(try JSONDecoder().decode(WeeklySleepSchedule.self, from: data) == week)
        #expect(try JSONDecoder().decode(SleepSchedule.self, from: data) == .standard)

        // A weekend that can't be read is dropped rather than failing the file.
        let damaged = Data(#"{"bedtime":{"hour":23,"minute":0},"wake":{"hour":7,"minute":0},"windDownMinutes":45,"weekend":"soon"}"#.utf8)
        #expect(try JSONDecoder().decode(WeeklySleepSchedule.self, from: damaged) == .standard)
        // A file without the weekday schedule still fails, as before.
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WeeklySleepSchedule.self, from: Data("{}".utf8)) }
    }
}

@Suite("Weekly schedule: Home and the night ledger")
struct WeeklyScheduleRulesTests {
    private let weekend = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)
    private var week: WeeklySleepSchedule { WeeklySleepSchedule(weekday: .standard, weekend: weekend) }

    private func day(_ month: Int, _ day: Int) -> LocalDay { LocalDay(year: 2026, month: month, day: day) }

    @Test("Home's captions name tonight's times: a Friday evening counts down to the weekend bedtime")
    func homeCaptions() {
        func state(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, goodnightAt: Date? = nil) -> NowState {
            NowState.resolve(date: at(2026, month, day, hour, minute), weekly: week, calendar: utc, locale: enGB, goodnightAt: goodnightAt)
        }
        // Thursday evening (a weekday night).
        let thursday = state(10, 8, 20, 55)
        #expect(thursday.phase == .evening)
        #expect(thursday.numeral.text == "1h 20m")
        #expect(thursday.caption == "until wind-down · bed 23:00")
        // Friday evening (a weekend night): wind-down at 23:30, bed at 00:30.
        let friday = state(10, 9, 22, 10)
        #expect(friday.phase == .evening)
        #expect(friday.numeral.text == "1h 20m")
        #expect(friday.caption == "until wind-down · bed 00:30")
        let windDown = state(10, 10, 0, 0)
        #expect(windDown.phase == .windDown)
        #expect(windDown.caption == "until bed · phone down at 00:30")
        #expect(windDown.numeral.text == "30m")
        #expect(state(10, 10, 3).caption == "wake-up · your maple is resting")
        #expect(state(10, 10, 3).numeral.text == "09:00")
        // Sunday night wakes into Monday: the weekday wake.
        #expect(state(10, 11, 23, 30).numeral.text == "07:00")
        // Sunday morning without data: tonight's (weekday) wind-down; with a Goodnight, last night's (weekend) bedtime.
        #expect(state(10, 11, 9).caption == "wind-down tonight · bed 23:00")
        #expect(state(10, 11, 9).numeral.text == "22:15")
        #expect(state(10, 11, 9, goodnightAt: at(2026, 10, 11, 0, 40)).caption == "in bed · bedtime 00:30")
    }

    @Test("Leaves earned on a Friday evening are held until the weekend morning")
    func heldUntilTheWeekendMorning() {
        let leaf = LeafUnlock(speciesID: "rubrum", date: at(2026, 10, 9, 22), season: .autumn, colourway: .autumn)
        #expect(RevealSchedule.releaseDate(for: leaf, schedule: week, calendar: utc) == at(2026, 10, 10, 8))
        #expect(RevealSchedule.isHeld(leaf, at: at(2026, 10, 10, 7, 59), schedule: week, calendar: utc))
        #expect(!RevealSchedule.isHeld(leaf, at: at(2026, 10, 10, 8), schedule: week, calendar: utc))
    }

    /// The schedule saved (and the Sugar maple opened) at `date`.
    private func planted(at date: Date, context: CollectionContext) -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: date)
        snapshot.raise(.firstSteps, to: 1, at: date, calendar: utc)
        snapshot.runEngine(at: date, context: context)
        snapshot.openReveals(nil, at: date, context: context)
        return snapshot
    }

    private func sleep(_ night: LocalDay, onset: Date, wake: Date) -> SleepNightObservation {
        SleepNightObservation(night: night, onset: onset, finalWake: wake, asleepMinutes: 480, source: .watchOrTracker)
    }

    @Test("A Friday night is judged by the weekend schedule: its bedtime, its wake and its later settling")
    func fridayNight() {
        let context = CollectionContext(schedule: week, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)
        var snapshot = planted(at: at(2026, 10, 8, 20), context: context)
        // Thursday night: bed 23:00, asleep 23:10, up 07:05.
        let thursday = sleep(day(10, 8), onset: at(2026, 10, 8, 23, 10), wake: at(2026, 10, 9, 7, 5))
        snapshot.recordSleep([thursday], at: at(2026, 10, 9, 6, 30), context: context)
        // Friday night: asleep 00:20 (late against 23:00, on time against 00:30), up 09:10 (steady against 09:00).
        let friday = sleep(day(10, 9), onset: at(2026, 10, 10, 0, 20), wake: at(2026, 10, 10, 9, 10))
        // At 07:00 on Saturday the weekend morning hasn't started: the night waits.
        #expect(snapshot.recordSleep([friday], at: at(2026, 10, 10, 7), context: context).isEmpty)
        #expect(snapshot.nights.settledThrough == day(10, 8))
        snapshot.recordSleep([], at: at(2026, 10, 10, 8), context: context)
        #expect(snapshot.nights.settledThrough == day(10, 9))
        // Sunday night wakes into Monday: weekday again, so 00:20 is late.
        snapshot.recordSleep([sleep(day(10, 10), onset: at(2026, 10, 11, 0, 20), wake: at(2026, 10, 11, 9))], at: at(2026, 10, 11, 8), context: context)
        snapshot.recordSleep([sleep(day(10, 11), onset: at(2026, 10, 12, 0, 20), wake: at(2026, 10, 12, 7))], at: at(2026, 10, 12, 6), context: context)

        #expect(snapshot.nights.recent.map(\.outcome) == [.onTime, .onTime, .onTime, .late])
        #expect(snapshot.nights.recent.map(\.steadyMorning) == [true, true, true, true])
        #expect(snapshot.counters[.onTimeBedtimes] == 3)
        #expect(snapshot.counters[.steadyMornings] == 4)
    }

    @Test("A weekend schedule added on a Friday evening applies from the next night (18:00 cut-off)")
    func weekendAddedOnFriday() {
        var context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)
        var snapshot = planted(at: at(2026, 10, 8, 20), context: context)
        // At 20:00 on Friday the member adds the weekend schedule: Friday night has begun under 23:00 every night.
        snapshot.scheduleChanged(from: .standard, to: week, at: at(2026, 10, 9, 20), calendar: utc)
        context.schedule = week
        #expect(snapshot.nights.pastSchedules == [NightLedger.PastSchedule(through: day(10, 9), schedule: .standard)])

        snapshot.recordSleep([], at: at(2026, 10, 9, 12), context: context)                                  // Thursday: untracked
        let friday = sleep(day(10, 9), onset: at(2026, 10, 10, 0, 20), wake: at(2026, 10, 10, 9, 10))
        // Friday is judged by the old schedule: it settles at 06:00 and 00:20 is late; 09:10 isn't a steady morning.
        snapshot.recordSleep([friday], at: at(2026, 10, 10, 6, 30), context: context)
        #expect(snapshot.nights.settledThrough == day(10, 9))
        // Saturday night uses the new weekend schedule.
        let saturday = sleep(day(10, 10), onset: at(2026, 10, 11, 0, 20), wake: at(2026, 10, 11, 9, 10))
        snapshot.recordSleep([saturday], at: at(2026, 10, 11, 8), context: context)

        #expect(snapshot.nights.recent.map(\.outcome) == [.untracked, .late, .onTime])
        #expect(snapshot.nights.recent.map(\.steadyMorning) == [false, false, true])
    }

    @Test("A past schedule saved before weekend schedules decodes as the same schedule every night")
    func pastScheduleMigration() throws {
        let old = Data(#"{"through":"2026-10-02","schedule":{"bedtime":{"hour":22,"minute":0},"wake":{"hour":7,"minute":0},"windDownMinutes":45}}"#.utf8)
        let past = try JSONDecoder().decode(NightLedger.PastSchedule.self, from: old)
        #expect(past.through == day(10, 2))
        #expect(past.schedule == .everyNight(SleepSchedule(bedtime: ClockTime(hour: 22), wake: ClockTime(hour: 7), windDownMinutes: 45)))
    }
}
