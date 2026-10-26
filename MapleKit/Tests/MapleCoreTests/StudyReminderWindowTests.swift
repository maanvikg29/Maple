import Foundation
import Testing
@testable import MapleCore

@Suite("Study reminder window")
struct StudyReminderWindowTests {
    /// Monday 2026-10-12, so the seven days run Monday to Sunday.
    private let monday = at(2026, 10, 12, 9)

    /// The phase at `hour:minute` on the day `offset` days after Monday.
    private func phase(_ hour: Int, _ minute: Int, dayOffset offset: Int, _ weekly: WeeklySleepSchedule) -> NowPhase {
        let day = LocalDay(monday, calendar: utc).adding(days: offset, calendar: utc).startDate(in: utc)
        let date = utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return NowPhase.resolve(date: date, weekly: weekly, calendar: utc)
    }

    @Test("The standard day runs 10:00 to 20:15, so 10:00 to 20:14 can be chosen; 16:00 is suggested")
    func standard() throws {
        let window = try #require(StudyReminderWindow(weekly: .standard, around: monday, calendar: utc))
        #expect(window.earliest == ClockTime(hour: 10))
        #expect(window.latest == ClockTime(hour: 20, minute: 14))
        #expect(window.contains(ClockTime(hour: 16)))
        #expect(window.contains(ClockTime(hour: 10)))
        #expect(window.contains(ClockTime(hour: 20, minute: 14)))
        #expect(!window.contains(ClockTime(hour: 9, minute: 59)))
        #expect(!window.contains(ClockTime(hour: 20, minute: 15)))
        #expect(!window.contains(ClockTime(hour: 21)))
        #expect(StudyReminderWindow.suggested == ClockTime(hour: 16))
        #expect(window.suggestion == ClockTime(hour: 16))
    }

    @Test("A later weekend: only the times in the Day phase on all seven days")
    func weekend() throws {
        let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)
        let weekly = WeeklySleepSchedule(weekday: .standard, weekend: late)
        let window = try #require(StudyReminderWindow(weekly: weekly, around: monday, calendar: utc))
        #expect(window.earliest == ClockTime(hour: 12))
        #expect(window.latest == ClockTime(hour: 20, minute: 14))
        // The phases agree, day by day: both ends are in the Day phase every day.
        for offset in 0..<7 {
            #expect(phase(12, 0, dayOffset: offset, weekly) == .day)
            #expect(phase(20, 14, dayOffset: offset, weekly) == .day)
        }
        // Just outside: 11:59 is still Saturday's morning, and 20:15 is Monday's evening.
        #expect(phase(11, 59, dayOffset: 5, weekly) == .morning)
        #expect(phase(20, 15, dayOffset: 0, weekly) == .evening)
        #expect(window.suggestion == ClockTime(hour: 16))
    }

    @Test("A schedule with no daytime has no window; a time outside one moves to its nearest edge")
    func edges() throws {
        // Wake 15:00, wind-down from 17:15: the Evening starts at 15:15, before the Day could.
        let short = SleepSchedule(bedtime: ClockTime(hour: 18), wake: ClockTime(hour: 15), windDownMinutes: 45)
        #expect(StudyReminderWindow(weekly: .everyNight(short), around: monday, calendar: utc) == nil)
        let window = try #require(StudyReminderWindow(weekly: .standard, around: monday, calendar: utc))
        #expect(window.nearest(to: ClockTime(hour: 8)) == ClockTime(hour: 10))
        #expect(window.nearest(to: ClockTime(hour: 22)) == ClockTime(hour: 20, minute: 14))
        #expect(window.nearest(to: ClockTime(hour: 13, minute: 5)) == ClockTime(hour: 13, minute: 5))
    }
}
