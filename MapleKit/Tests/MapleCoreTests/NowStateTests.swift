import Foundation
import Testing
@testable import MapleCore

@Suite("Now phase")
struct NowPhaseTests {
    private func phase(_ hour: Int, _ minute: Int = 0, _ schedule: SleepSchedule = .standard) -> NowPhase {
        NowPhase.resolve(date: at(2026, 10, 10, hour, minute), schedule: schedule, calendar: utc)
    }

    @Test("Standard schedule: wake 07:00, wind-down 22:15, bed 23:00")
    func standard() {
        #expect(phase(5, 59) == .night)
        #expect(phase(6) == .morning)
        #expect(phase(9, 59) == .morning)
        #expect(phase(10) == .day)
        #expect(phase(20, 14) == .day)
        #expect(phase(20, 15) == .evening)
        #expect(phase(22, 14) == .evening)
        #expect(phase(22, 15) == .windDown)
        #expect(phase(22, 59) == .windDown)
        #expect(phase(23) == .night)
        #expect(phase(2) == .night)
        #expect(phase(0) == .night)
    }

    @Test("Bedtime after midnight wraps every window")
    func midnightWrap() {
        let late = SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60)
        #expect(phase(7, 59, late) == .night)
        #expect(phase(8, 0, late) == .morning)
        #expect(phase(11, 59, late) == .morning)
        #expect(phase(12, 0, late) == .day)
        #expect(phase(21, 59, late) == .day)
        #expect(phase(22, 0, late) == .evening)
        #expect(phase(23, 59, late) == .evening)
        #expect(phase(0, 0, late) == .windDown)
        #expect(phase(0, 59, late) == .windDown)
        #expect(phase(1, 0, late) == .night)
    }

    @Test("When the day window would be negative it is empty, and morning ends at evening")
    func emptyDay() {
        // Wake 13:00, bed 19:00, 2h wind-down: evening starts 15:00, before W + 3h (16:00).
        let short = SleepSchedule(bedtime: ClockTime(hour: 19), wake: ClockTime(hour: 13), windDownMinutes: 120)
        #expect(phase(12, 0, short) == .morning)
        #expect(phase(14, 59, short) == .morning)
        #expect(phase(15, 0, short) == .evening)
        #expect(phase(16, 30, short) == .evening)
        #expect(phase(17, 0, short) == .windDown)
        #expect(phase(19, 0, short) == .night)
        for hour in 0..<24 { #expect(phase(hour, 0, short) != .day) }
    }

    @Test("A sample date lands inside each phase")
    func sampleDates() {
        for schedule in [SleepSchedule.standard, SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60)] {
            for phase in NowPhase.allCases {
                let date = PhaseWindows(schedule: schedule).sampleDate(in: phase, onDayOf: at(2026, 10, 10, 15), calendar: utc)
                #expect(NowPhase.resolve(date: date, schedule: schedule, calendar: utc) == phase)
                #expect(LocalDay(date, calendar: utc) == LocalDay(year: 2026, month: 10, day: 10))
            }
        }
        // Evening shows the wireframe's "1h 20m until wind-down".
        #expect(PhaseWindows(schedule: .standard).sampleDate(in: .evening, onDayOf: at(2026, 10, 10), calendar: utc) == at(2026, 10, 10, 20, 55))
    }
}

@Suite("Now state")
struct NowStateTests {
    private func state(
        _ hour: Int, _ minute: Int = 0, locale: Locale = enGB, pending: Int = 0,
        counters: [RewardCategoryID: Double] = [:], features: ShippedFeatures = .current,
        lastNight: LastNightSleep? = nil, goodnightAt: Date? = nil, focus: FocusStatus? = nil,
        windDownActive: Bool = false, checkInDue: Bool = false
    ) -> NowState {
        NowState.resolve(
            date: at(2026, 10, 10, hour, minute), schedule: .standard, calendar: utc, locale: locale,
            pending: pending, counters: counters, features: features, lastNight: lastNight, goodnightAt: goodnightAt,
            focus: focus, windDownActive: windDownActive, checkInDue: checkInDue
        )
    }

    @Test("Evening: countdown to wind-down, dimmed Start wind-down")
    func evening() {
        let now = state(20, 55)
        #expect(now.phase == .evening)
        #expect(now.content == .untilWindDown)
        #expect(now.numeral.parts == [.value("1"), .unit("h"), .value("20"), .unit("m")])
        #expect(now.numeral.text == "1h 20m")
        #expect(now.caption == "until wind-down · bed 23:00")
        #expect(now.action == .startWindDown)
        #expect(now.action?.title == "Start wind-down")
        #expect(now.actionIsDimmed)
        #expect(now.leafPreference == .night)
        #expect(now.waitingCount == 0)
        #expect(now.contentOpacity == 1)
        #expect(now.showsBelowTheFold)
        #expect(state(20, 55, windDownActive: true).action == .returnToWindDown)
    }

    @Test("Countdowns round up to the minute so they never read 0m inside the window")
    func rounding() {
        let now = NowState.resolve(date: at(2026, 10, 10, 22, 14, 30), schedule: .standard, calendar: utc, locale: enGB)
        #expect(now.numeral.text == "1m")
        let hours = state(20, 15)
        #expect(hours.numeral.parts == [.value("2"), .unit("h")])
    }

    @Test("Wind-down: countdown to bed")
    func windDown() {
        let now = state(22, 22)
        #expect(now.content == .untilBed)
        #expect(now.numeral.parts == [.value("38"), .unit("m")])
        #expect(now.caption == "until bed · phone down at 23:00")
        #expect(now.action == .startWindDown)
        #expect(now.actionIsDimmed)
        #expect(state(22, 22, windDownActive: true).action?.title == "Return to wind-down")
    }

    @Test("Night: wake time, no primary, text at 80%, nothing below the fold")
    func night() {
        let now = state(23, 30)
        #expect(now.content == .wake)
        #expect(now.numeral.parts == [.value("07:00")])
        #expect(now.caption == "wake-up · your maple is resting")
        #expect(now.action == nil)
        #expect(now.secondaryAction == nil)
        #expect(now.contentOpacity == 0.8)
        #expect(!now.showsBelowTheFold)
        #expect(state(2, 0, features: .all).secondaryAction == .sleepSounds)
    }

    @Test("Day before focus ships: countdown to wind-down, no action")
    func dayBeforeFocus() {
        let now = state(13, 40)
        #expect(now.content == .untilWindDown)
        #expect(now.numeral.text == "8h 35m")
        #expect(now.caption == "until wind-down · bed 23:00")
        #expect(now.action == nil)
        #expect(now.leafPreference == .day)
        #expect(!now.actionIsDimmed)
    }

    @Test("Day once focus ships: focus today and Start focus")
    func dayFocus() {
        let now = state(13, 40, counters: [.focusDays: 3, .focusHours: 4], features: .all,
                        focus: FocusStatus(todayMinutes: 85, weekMinutes: 250))
        #expect(now.content == .focusToday)
        #expect(now.numeral.text == "1h 25m")
        #expect(now.caption == "focused today · 4h 10m this week")
        #expect(now.action == .startFocus(minutes: 25, firstTime: false))
        #expect(now.action?.title == "Start focus · 25m")

        let first = state(13, 40, features: .all)
        #expect(first.numeral.text == "0m")
        #expect(first.action == .startFocus(minutes: 25, firstTime: true))
        #expect(first.action?.title == "Start a 25-minute focus")
    }

    @Test("Focus running: remaining mm:ss in any phase but night")
    func focusRunning() {
        let running = FocusStatus(todayMinutes: 10, weekMinutes: 10, remaining: 18 * 60 + 42)
        let now = state(20, 55, features: .all, focus: running)
        #expect(now.content == .focusRunning)
        #expect(now.numeral.parts == [.value("18:42")])
        #expect(now.caption == "left in this focus")
        #expect(now.action == .returnToFocus)
        #expect(now.refreshesEverySecond)
        #expect(state(23, 30, features: .all, focus: running).content == .wake)
        #expect(state(20, 55, features: .all, focus: running).action?.title == "Return to focus")
    }

    @Test("Morning with Apple Health: last night's sleep")
    func morningHealth() {
        let night = LastNightSleep(asleep: at(2026, 10, 9, 23, 8), awake: at(2026, 10, 10, 6, 20), duration: 7 * 3600 + 12 * 60)
        let now = state(7, 40, lastNight: night)
        #expect(now.content == .lastNightSleep)
        #expect(now.numeral.text == "7h 12m")
        #expect(now.caption == "asleep 23:08 · up 06:20")
        #expect(now.action == nil)
        #expect(now.leafPreference == .morning)
    }

    @Test("Morning without Apple Health: Goodnight time")
    func morningGoodnight() {
        let now = state(7, 40, goodnightAt: at(2026, 10, 9, 23, 4))
        #expect(now.content == .goodnight)
        #expect(now.numeral.parts == [.value("23:04")])
        #expect(now.caption == "in bed · bedtime 23:00")
    }

    @Test("Morning with no data for last night: tonight's wind-down start as a clock time, not a long countdown")
    func morningNoData() {
        let now = state(7, 40)
        #expect(now.phase == .morning)
        #expect(now.content == .windDownTonight)
        #expect(now.numeral.parts == [.value("22:15")])
        #expect(now.numeral.text == "22:15")
        #expect(now.caption == "wind-down tonight · bed 23:00")
        #expect(now.spoken == "Wind-down tonight at 22:15. Bed at 23:00.")
        #expect(now.action == nil)
        #expect(!now.actionIsDimmed)
        #expect(now.leafPreference == .morning)
        #expect(now.waitingCount == 0)

        let us = state(7, 40, locale: enUS)
        #expect(us.numeral.parts == [.value("10:15"), .unit(" PM")])
        #expect(us.numeral.text == "10:15 PM")
        #expect(us.caption == "wind-down tonight · bed 11:00 PM")

        // The same at the start and the end of the morning, and once focus ships (no "0m focused" at 6 AM).
        #expect(state(6, 0).content == .windDownTonight)
        #expect(state(9, 59).content == .windDownTonight)
        #expect(state(7, 40, features: .all).content == .windDownTonight)
        // Data for last night still wins.
        #expect(state(7, 40, goodnightAt: at(2026, 10, 9, 23, 4)).content == .goodnight)
        // Pending leaves keep the numeral and take the action.
        let pending = state(7, 40, pending: 1)
        #expect(pending.content == .windDownTonight)
        #expect(pending.action == .openReveals(count: 1))
    }

    @Test("Tonight's wind-down follows the member's schedule, past midnight too")
    func morningNoDataSchedule() {
        let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60)
        let now = NowState.resolve(date: at(2026, 10, 10, 8, 0), schedule: late, calendar: utc, locale: enGB)
        #expect(now.phase == .morning)
        #expect(now.numeral.text == "23:30")
        #expect(now.caption == "wind-down tonight · bed 00:30")
        let us = NowState.resolve(date: at(2026, 10, 10, 8, 0), schedule: late, calendar: utc, locale: enUS)
        #expect(us.numeral.text == "11:30 PM")
        #expect(us.caption == "wind-down tonight · bed 12:30 AM")
    }

    @Test("Check-in once mood check-ins ship")
    func checkIn() {
        #expect(state(7, 40, checkInDue: true).action == nil)
        #expect(state(7, 40, features: .all, checkInDue: true).action == .checkIn)
        #expect(state(7, 40, features: .all, checkInDue: true).action?.title == "Check in")
    }

    @Test("Pending reveals take over the action in morning, day and evening only")
    func pending() {
        let day = state(13, 40, pending: 2)
        #expect(day.action == .openReveals(count: 2))
        #expect(day.action?.title == "Open 2 new leaves")
        #expect(day.waitingCount == 2)
        #expect(day.waitingLine == "2 new leaves are waiting")
        let evening = state(20, 55, pending: 1)
        #expect(evening.action?.title == "Open your new leaf")
        #expect(evening.waitingLine == "A new leaf is waiting")
        #expect(evening.actionIsDimmed)
        let morning = state(7, 40, pending: 1, features: .all, checkInDue: true)
        #expect(morning.action == .openReveals(count: 1))
        for (hour, minute) in [(22, 22), (23, 30), (3, 0)] {
            let quiet = state(hour, minute, pending: 3)
            #expect(quiet.waitingCount == 0)
            #expect(quiet.waitingLine == nil)
            #expect(quiet.action != .openReveals(count: 3))
        }
        // A running focus keeps its own action.
        let focusing = state(13, 40, pending: 1, features: .all, focus: FocusStatus(todayMinutes: 0, weekMinutes: 0, remaining: 60))
        #expect(focusing.action == .returnToFocus)
        #expect(focusing.waitingCount == 1)
    }

    @Test("Every caption fits the Home copy rule: one line of 7 words or fewer")
    func captionLength() {
        let night = LastNightSleep(asleep: at(2026, 10, 9, 23, 8), awake: at(2026, 10, 10, 6, 20), duration: 26_000)
        for locale in [enGB, enUS] {
            let states = [
                state(7, 40, locale: locale, lastNight: night),
                state(7, 40, locale: locale, goodnightAt: at(2026, 10, 9, 23, 4)),
                state(7, 40, locale: locale),
                state(13, 40, locale: locale),
                state(13, 40, locale: locale, features: .all, focus: FocusStatus(todayMinutes: 85, weekMinutes: 250)),
                state(13, 40, locale: locale, features: .all, focus: FocusStatus(todayMinutes: 5, weekMinutes: 5, remaining: 300)),
                state(20, 55, locale: locale),
                state(22, 22, locale: locale),
                state(23, 30, locale: locale),
            ]
            for now in states {
                #expect(wordCount(now.caption) <= 7, "\(now.caption)")
                #expect(!now.caption.contains("\n"))
                #expect(!now.caption.contains("!"))
            }
        }
    }

    @Test("Clock times follow the locale")
    func locale() {
        let night = state(23, 30, locale: enUS)
        #expect(night.numeral.parts == [.value("7:00"), .unit(" AM")])
        #expect(state(20, 55, locale: enUS).caption == "until wind-down · bed 11:00 PM")
    }

    @Test("VoiceOver reads the numeral and caption as one sentence with full units")
    func spoken() {
        let evening = state(20, 55)
        #expect(evening.spoken.contains("hour"))
        #expect(evening.spoken.contains("20 minutes"))
        #expect(evening.spoken.contains("until wind-down"))
        #expect(!evening.spoken.contains("1h"))
    }
}

@Suite("Leaf remainder copy")
struct LeafRemainderTests {
    private func remainder(_ category: RewardCategoryID, _ threshold: Double, _ current: Double, _ phase: NowPhase = .day) -> String {
        LeafRemainder(progressRow("x", category, threshold: threshold, current: current, estimate: 1), phase: phase).text
    }

    @Test("Remainders by unit")
    func units() {
        #expect(remainder(.restedNights, 14, 11) == "3 nights")
        #expect(remainder(.bedtimeKept, 3, 2) == "1 night")
        #expect(remainder(.phoneFreeMornings, 10, 6) == "4 mornings")
        #expect(remainder(.focusStreak, 14, 9) == "5 days")
        #expect(remainder(.sessionsFinished, 10, 7) == "3 sessions")
        #expect(remainder(.hoursSaved, 8, 6 + 20.0 / 60) == "1h 40m")
        #expect(remainder(.hoursSaved, 4, 3.5) == "30m")
        #expect(remainder(.bedtimeKept, 7, 3.5) == "4 nights")
    }

    @Test("One to go reads Tonight in the evening, Today in the day")
    func tonightToday() {
        #expect(remainder(.restedNights, 3, 2, .evening) == "Tonight")
        #expect(remainder(.restedNights, 14, 13, .windDown) == "Tonight")
        #expect(remainder(.restedNights, 14, 13, .night) == "1 night")
        #expect(remainder(.restedNights, 14, 13, .day) == "1 night")
        #expect(remainder(.focusStreak, 3, 2, .day) == "Today")
        #expect(remainder(.focusStreak, 3, 2, .evening) == "1 day")
    }

    @Test("Amounts and the bar")
    func amounts() {
        let row = progressRow("x", .restedNights, threshold: 14, current: 11, estimate: 4)
        #expect(LeafRemainder(row, phase: .day).amount == "11 of 14")
        #expect(LeafRemainder(row, phase: .day).showsBar)
        let hours = progressRow("x", .hoursSaved, threshold: 8, current: 6, estimate: 4)
        #expect(LeafRemainder(hours, phase: .day).amount == "6h of 8h")
        let fresh = progressRow("x", .restedNights, threshold: 3, current: 0, estimate: 1)
        #expect(!LeafRemainder(fresh, phase: .evening).showsBar)
    }
}

@Suite("Vitality")
struct VitalityTests {
    private func night(_ day: Int, onTime: Bool? = nil, full: Bool? = nil, scrollFree: Bool? = nil) -> NightRecord {
        NightRecord(day: LocalDay(year: 2026, month: 10, day: day), onTime: onTime, fullNight: full, scrollFree: scrollFree)
    }

    @Test("No data is full vitality")
    func noData() {
        #expect(Vitality(last7Nights: []).value == 1)
        #expect(Vitality(last7Nights: [night(1), night(2)]).value == 1)
    }

    @Test("All three shares, weighted 0.5, 0.25, 0.25")
    func weights() {
        let perfect = (1...7).map { night($0, onTime: true, full: true, scrollFree: true) }
        #expect(Vitality(last7Nights: perfect).value == 1)
        let rough = (1...7).map { night($0, onTime: false, full: false, scrollFree: false) }
        #expect(abs(Vitality(last7Nights: rough).value - 0.4) < 1e-9)
        #expect(Vitality(last7Nights: rough).isQuiet)
        let mixed = (1...4).map { night($0, onTime: true, full: false, scrollFree: false) }
            + (5...8).map { night($0, onTime: false, full: true, scrollFree: true) }
        // The last 7 nights only: on time 3/7, full 4/7, scroll-free 4/7.
        let score = 0.5 * 3 / 7 + 0.25 * 4 / 7 + 0.25 * 4 / 7
        #expect(abs(Vitality(last7Nights: mixed).value - (0.4 + 0.6 * score)) < 1e-9)
    }

    @Test("Unavailable shares hand their weight to the others")
    func redistribution() {
        let onTimeOnly = (1...6).map { night($0, onTime: $0 <= 3) }
        #expect(abs(Vitality(last7Nights: onTimeOnly).value - 0.7) < 1e-9)
        let noScreenTime = (1...4).map { night($0, onTime: true, full: $0 <= 2) }
        // on time 1, full 0.5, weights 2/3 and 1/3.
        #expect(abs(Vitality(last7Nights: noScreenTime).value - (0.4 + 0.6 * (2.0 / 3 + 0.5 / 3))) < 1e-9)
    }

    @Test("Quiet below 0.55")
    func quiet() {
        #expect(!Vitality(value: 0.55).isQuiet)
        #expect(Vitality(value: 0.549).isQuiet)
    }
}

@Suite("Maple clock")
struct MapleClockTests {
    @Test("Fixed clocks never move; live clocks follow the timeline")
    func clocks() {
        let fixed = MapleClock.fixed(at(2026, 10, 10, 20, 55))
        #expect(fixed.now() == at(2026, 10, 10, 20, 55))
        #expect(fixed.date(forTimeline: at(2030, 1, 1)) == at(2026, 10, 10, 20, 55))
        #expect(fixed.isFixed)
        let live = MapleClock.live
        #expect(abs(live.now().timeIntervalSinceNow) < 1)
        #expect(live.date(forTimeline: at(2030, 1, 1)) == at(2030, 1, 1))
        #expect(!live.isFixed)
    }
}
