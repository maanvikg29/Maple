import Foundation
import Testing
@testable import MapleCore

@Suite("Awake window")
struct AwakeWindowTests {
    private let standard: (LocalDay) -> WeeklySleepSchedule = { _ in .standard }
    private let oct23 = LocalDay(year: 2026, month: 10, day: 23)

    @Test("A day's window runs from an hour before last night's wake to tonight's bedtime")
    func standardDay() {
        let window = AwakeWindow.window(for: oct23, schedule: standard, calendar: utc)
        #expect(window.start == at(2026, 10, 23, 6))
        #expect(window.end == at(2026, 10, 23, 23))
        #expect(window.windDown == at(2026, 10, 23, 22, 15))
    }

    @Test("A session belongs to the day whose window holds its start")
    func daytime() {
        let frozen = AwakeWindow.frozen(at: at(2026, 10, 23, 14), schedule: standard, calendar: utc)
        #expect(frozen.day == oct23)
    }

    @Test("A session that starts in the sleep window takes the next day's window, counting from wake − 60")
    func dawn() {
        let frozen = AwakeWindow.frozen(at: at(2026, 10, 23, 5, 30), schedule: standard, calendar: utc)
        #expect(frozen.day == oct23)
        #expect(frozen.window.start == at(2026, 10, 23, 6))
        let late = AwakeWindow.frozen(at: at(2026, 10, 23, 23, 30), schedule: standard, calendar: utc)
        #expect(late.day == LocalDay(year: 2026, month: 10, day: 24))
        #expect(late.window.start == at(2026, 10, 24, 6))
    }

    @Test("A 23:40 start with bed at 01:00 stays on its day, across midnight")
    func lateBed() {
        let late = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 45))
        let frozen = AwakeWindow.frozen(at: at(2026, 10, 23, 23, 40), schedule: { _ in late }, calendar: utc)
        #expect(frozen.day == oct23)
        #expect(frozen.window.end == at(2026, 10, 24, 1))
    }

    @Test("A sleep window under 6 hours is widened at the wake end")
    func shortNight() {
        let short = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 5), windDownMinutes: 30))
        let window = AwakeWindow.window(for: oct23, schedule: { _ in short }, calendar: utc)
        // Last night: bed 01:00, wake 05:00 (4 h) is widened to 07:00, so the day starts at 06:00.
        #expect(window.start == at(2026, 10, 23, 6))
    }

    @Test("Each night uses the schedule that judges it, so an edit after 18:00 leaves tonight alone")
    func pastSchedule() {
        let early = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 21), wake: ClockTime(hour: 6), windDownMinutes: 30))
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        snapshot.nights.pastSchedules = [NightLedger.PastSchedule(through: oct23, schedule: .standard)]
        let context = CollectionContext(schedule: early, calendar: utc, hemisphere: .northern)
        let tonight = snapshot.focusWindow(at: at(2026, 10, 23, 20, 30), context: context)
        #expect(tonight.window.end == at(2026, 10, 23, 23))
        let tomorrow = snapshot.focusWindow(at: at(2026, 10, 24, 12), context: context)
        #expect(tomorrow.window.end == at(2026, 10, 24, 21))
    }

    @Test("A weekend night uses the weekend bedtime")
    func weekend() {
        let weekly = WeeklySleepSchedule(weekday: .standard,
                                         weekend: SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60))
        // 23 October 2026 is a Friday: its night wakes into Saturday.
        let window = AwakeWindow.window(for: oct23, schedule: { _ in weekly }, calendar: utc)
        #expect(window.end == at(2026, 10, 24, 0, 30))
        #expect(window.start == at(2026, 10, 23, 6))
    }

    @Test("Daylight-saving days: windows keep their local times on 23- and 25-hour days")
    func daylightSaving() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let spring = AwakeWindow.window(for: LocalDay(year: 2026, month: 3, day: 29), schedule: standard, calendar: london)
        #expect(spring.start == at(2026, 3, 29, 6, in: london))
        #expect(spring.end == at(2026, 3, 29, 23, in: london))
        let autumn = AwakeWindow.window(for: LocalDay(year: 2026, month: 10, day: 25), schedule: standard, calendar: london)
        #expect(autumn.start == at(2026, 10, 25, 6, in: london))
        #expect(autumn.interval.duration == 17 * 3600)
    }

    @Test("Day labels and ordinals")
    func labels() {
        #expect(LocalDay(label: "2026-10-23") == oct23)
        #expect(LocalDay(label: "2026-13-01") == nil)
        #expect(LocalDay(label: "soon") == nil)
        #expect(LocalDay(year: 1970, month: 1, day: 1).ordinal == 0)
        #expect(LocalDay(year: 2026, month: 10, day: 24).ordinal - oct23.ordinal == 1)
        #expect(LocalDay(year: 2028, month: 3, day: 1).ordinal - LocalDay(year: 2028, month: 2, day: 28).ordinal == 2)
        #expect(FocusFixtures.plan().day == oct23)
    }
}
