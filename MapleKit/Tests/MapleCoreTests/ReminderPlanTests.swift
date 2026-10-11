import Foundation
import Testing
@testable import MapleCore

/// A calendar in `zone`, for daylight-saving tests.
private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.locale = enGB
    return calendar
}

/// The hour and minute of `date` in `calendar`, e.g. "22:15".
private func clock(_ date: Date, _ calendar: Calendar = utc) -> String {
    HomeFormat.clock(HomeFormat.clockTime(of: date, calendar: calendar), locale: enGB)
}

/// A plan from one repeating schedule.
private func plan(
    _ schedule: SleepSchedule = .standard, now: Date, settings: ReminderSettings = .allOn,
    windDownOpenedAt: Date? = nil, calendar: Calendar = utc, locale: Locale = enGB
) -> ReminderPlan {
    ReminderPlan(.init(
        nights: UpcomingNight.nights(for: .everyNight(schedule), around: now, calendar: calendar), settings: settings,
        windDownOpenedAt: windDownOpenedAt, now: now, calendar: calendar, locale: locale
    ))
}

private extension ReminderPlan {
    func of(_ kind: ReminderKind) -> [ReminderRequest] { requests.filter { $0.kind == kind } }
}

@Suite("Upcoming nights")
struct UpcomingNightTests {
    @Test("One repeating schedule: the night whose morning has begun, then the next 7")
    func standard() throws {
        let nights = UpcomingNight.nights(for: .standard, around: at(2026, 10, 12, 12), calendar: utc)
        #expect(nights.count == 8)
        let first = try #require(nights.first)
        #expect(first.morningStart == at(2026, 10, 12, 6))
        #expect(first.bedtime == at(2026, 10, 11, 23))
        #expect(first.windDownStart == at(2026, 10, 11, 22, 15))
        #expect(first.wake == at(2026, 10, 12, 7))
        #expect(nights[1].windDownStart == at(2026, 10, 12, 22, 15))
        #expect(nights[1].morningStart == at(2026, 10, 13, 6))
        #expect(nights.last?.morningStart == at(2026, 10, 19, 6))
        for night in nights {
            #expect(night.windDownStart < night.bedtime && night.bedtime < night.morningStart && night.morningStart < night.wake)
        }
    }

    @Test("At night the night under way comes first: its morning hasn't started")
    func duringTheNight() throws {
        let nights = UpcomingNight.nights(for: .standard, around: at(2026, 10, 13, 2), calendar: utc)
        #expect(nights.first?.morningStart == at(2026, 10, 12, 6))
        #expect(nights[1].bedtime == at(2026, 10, 12, 23))
        #expect(nights[1].morningStart == at(2026, 10, 13, 6))
    }

    @Test("A bedtime after midnight belongs to the evening before")
    func midnightWrap() throws {
        let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60)
        let nights = UpcomingNight.nights(for: .everyNight(late), around: at(2026, 10, 12, 12), calendar: utc)
        let tonight = nights[1]
        #expect(tonight.windDownStart == at(2026, 10, 12, 23, 30))
        #expect(tonight.bedtime == at(2026, 10, 13, 0, 30))
        #expect(tonight.morningStart == at(2026, 10, 13, 7, 30))
        #expect(tonight.name(in: utc) == LocalDay(year: 2026, month: 10, day: 12))
    }

    @Test("Weekend nights use the weekend schedule")
    func weekendNights() throws {
        let weekend = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)
        let weekly = WeeklySleepSchedule(weekday: .standard, weekend: weekend)
        let nights = UpcomingNight.nights(for: weekly, around: at(2026, 10, 12, 12), calendar: utc)
        #expect(nights.count == 8)
        #expect(nights.contains { WeeklySleepSchedule.variant(forNight: $0.name(in: utc), calendar: utc) == .weekend })
        for night in nights {
            let expected = weekly.times(forNight: night.name(in: utc), calendar: utc)
            #expect(night.windDownStart == expected.windDownStart)
            #expect(night.bedtime == expected.bedtime)
            #expect(night.wake == expected.wake)
            #expect(night.morningStart == expected.morningStart)
        }
    }
}

@Suite("Reminder plan")
struct ReminderPlanTests {
    // 12 Oct 2026 is a Monday; the standard schedule winds down at 22:15, bed 23:00, morning from 06:00.
    private let noon = at(2026, 10, 12, 12)

    @Test("A wind-down reminder at each night's wind-down start, for the next 7 days")
    func windDownEachNight() throws {
        let reminders = plan(now: noon).of(.windDown)
        #expect(reminders.count == 7)
        #expect(reminders.map(\.fireDate) == (0..<7).map { at(2026, 10, 12 + $0, 22, 15) })
        let tonight = try #require(reminders.first)
        #expect(tonight.title == "Time to wind down")
        #expect(tonight.body == "Bed at 23:00.")
        #expect(tonight.id == "maple.reminder.windDown.2026-10-12")
        #expect(tonight.threadID == "maple.windDown")
        #expect(tonight.interruption == .active)
        #expect(tonight.playsSound)
        // Scheduled as a local wall-clock time.
        #expect(tonight.fireComponents == DateComponents(year: 2026, month: 10, day: 12, hour: 22, minute: 15, second: 0))
    }

    @Test("The bedtime follows the member's clock style")
    func localeAwareTime() {
        #expect(plan(now: noon, locale: enUS).of(.windDown).first?.body == "Bed at 11:00 PM.")
        let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 45)
        #expect(plan(late, now: noon).of(.windDown).first?.body == "Bed at 00:30.")
        #expect(plan(late, now: noon, locale: enUS).of(.windDown).first?.body == "Bed at 12:30 AM.")
    }

    @Test("Not once tonight's wind-down has started or passed")
    func windDownPassed() {
        for now in [at(2026, 10, 12, 22, 15), at(2026, 10, 12, 22, 40), at(2026, 10, 12, 23, 30), at(2026, 10, 13, 2)] {
            let reminders = plan(now: now).of(.windDown)
            #expect(reminders.first?.fireDate == at(2026, 10, 13, 22, 15))
            #expect(reminders.allSatisfy { $0.fireDate > now })
        }
        // A minute before, tonight's is still to come.
        #expect(plan(now: at(2026, 10, 12, 22, 14)).of(.windDown).first?.fireDate == at(2026, 10, 12, 22, 15))
    }

    @Test("Not on a night whose wind-down mode the member already opened")
    func windDownAlreadyOpened() {
        let evening = at(2026, 10, 12, 21)
        // Opened at 21:00, in the Evening: tonight's reminder goes, tomorrow's stays.
        let opened = plan(now: evening, windDownOpenedAt: evening).of(.windDown)
        #expect(opened.first?.fireDate == at(2026, 10, 13, 22, 15))
        #expect(opened.count == 6)
        // The Evening starts 2 hours before wind-down: an opening at 20:15 counts, one before doesn't.
        #expect(plan(now: evening, windDownOpenedAt: at(2026, 10, 12, 20, 15)).of(.windDown).first?.fireDate == at(2026, 10, 13, 22, 15))
        #expect(plan(now: evening, windDownOpenedAt: at(2026, 10, 12, 20, 14)).of(.windDown).first?.fireDate == at(2026, 10, 12, 22, 15))
        // Last night's wind-down says nothing about tonight.
        #expect(plan(now: evening, windDownOpenedAt: at(2026, 10, 11, 22, 30)).of(.windDown).first?.fireDate == at(2026, 10, 12, 22, 15))
    }

    @Test("A schedule with no wind-down gets no wind-down reminder")
    func noWindDownWindow() {
        let none = SleepSchedule(bedtime: ClockTime(hour: 23), wake: ClockTime(hour: 7), windDownMinutes: 0)
        #expect(plan(none, now: noon).of(.windDown).isEmpty)
    }

    @Test("Nothing between bedtime and the morning start, ever: every reminder falls in wind-down")
    func nothingAtNight() {
        let schedules = [
            SleepSchedule.standard,
            SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60),
            SleepSchedule(bedtime: ClockTime(hour: 21), wake: ClockTime(hour: 5), windDownMinutes: 30),
            SleepSchedule(bedtime: ClockTime(hour: 8), wake: ClockTime(hour: 16), windDownMinutes: 45),
        ]
        for schedule in schedules {
            for hour in stride(from: 0, to: 24, by: 3) {
                let now = at(2026, 10, 12, hour)
                for request in plan(schedule, now: now).requests {
                    let phase = NowPhase.resolve(date: request.fireDate, schedule: schedule, calendar: utc)
                    #expect(phase == .windDown, "\(request.id) at \(clock(request.fireDate))")
                }
            }
        }
    }

    @Test("Wind-down is the only reminder: nothing in the morning, ever")
    func onlyWindDown() {
        #expect(ReminderKind.allCases == [.windDown])
        for hour in stride(from: 0, to: 24, by: 2) {
            let result = plan(now: at(2026, 10, 12, hour))
            #expect(result.requests.allSatisfy { $0.kind == .windDown })
            #expect(result.requests.allSatisfy { clock($0.fireDate) == "22:15" })
        }
    }

    @Test("At most one wind-down reminder per night, even from overlapping nights")
    func onePerNight() {
        let now = at(2026, 10, 12, 21)
        let nights = UpcomingNight.nights(for: .standard, around: now, calendar: utc)
        let doubled = ReminderPlan(.init(nights: nights + nights, settings: .allOn, now: now, calendar: utc, locale: enGB))
        #expect(doubled.of(.windDown).count == 7)
        #expect(Set(doubled.requests.map(\.id)).count == doubled.requests.count)
        let days = doubled.of(.windDown).map { LocalDay($0.fireDate, calendar: utc) }
        #expect(Set(days).count == days.count)
    }

    @Test("Identifiers are deterministic, so rescheduling replaces instead of duplicating")
    func deterministic() {
        let first = plan(now: at(2026, 10, 12, 21))
        let again = plan(now: at(2026, 10, 12, 21))
        #expect(first == again)
        // An hour later the same nights keep the same identifiers.
        let later = plan(now: at(2026, 10, 12, 22))
        #expect(Set(later.requests.map(\.id)).isSubset(of: Set(first.requests.map(\.id))))
        #expect(first.requests.allSatisfy { $0.id.hasPrefix(ReminderKind.identifierPrefix) })
    }

    @Test("Only the next 7 days, well under iOS's 64 pending requests")
    func horizon() {
        let now = noon
        let nights = UpcomingNight.nights(for: .standard, around: now, count: 30, calendar: utc)
        #expect(nights.count == 31)
        let result = ReminderPlan(.init(nights: nights, settings: .allOn, now: now, calendar: utc, locale: enGB))
        #expect(result.requests.count == 7)
        #expect(result.requests.allSatisfy { $0.fireDate <= now.addingTimeInterval(7 * 24 * 3600) })
    }

    @Test("The switch turns the reminder off")
    func toggles() {
        let now = at(2026, 10, 12, 21)
        #expect(plan(now: now).of(.windDown).count == 7)
        #expect(plan(now: now, settings: ReminderSettings(windDown: false)).requests.isEmpty)
        #expect(plan(now: now, settings: .allOff).requests.isEmpty)
    }

    @Test("A bedtime after midnight: wind-down the evening before, named by that evening")
    func midnightWrap() throws {
        let late = SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 45)
        let windDown = try #require(plan(late, now: at(2026, 10, 12, 23)).of(.windDown).first)
        // Wind-down starts after midnight, at 00:15, and belongs to Monday night.
        #expect(windDown.fireDate == at(2026, 10, 13, 0, 15))
        #expect(windDown.id == "maple.reminder.windDown.2026-10-12")
        #expect(windDown.body == "Bed at 01:00.")
    }

    @Test("Across daylight-saving changes the reminders keep their local times")
    func daylightSaving() {
        let london = calendar("Europe/London")
        // Clocks go back on Sunday 25 October 2026 and forward on Sunday 29 March 2026.
        for start in [at(2026, 10, 22, 12, in: london), at(2026, 3, 26, 12, in: london)] {
            let windDowns = plan(now: start, calendar: london).of(.windDown)
            #expect(windDowns.count == 7)
            #expect(windDowns.allSatisfy { clock($0.fireDate, london) == "22:15" })
            #expect(windDowns.allSatisfy { $0.body == "Bed at 23:00." })
            #expect(Set(windDowns.map { LocalDay($0.fireDate, calendar: london) }).count == 7)
        }
    }

    @Test("A bedtime in the hour the clocks skip moves to the next real minute, still before the morning")
    func skippedHour() throws {
        let london = calendar("Europe/London")
        let late = SleepSchedule(bedtime: ClockTime(hour: 1, minute: 30), wake: ClockTime(hour: 9, minute: 30), windDownMinutes: 45)
        let now = at(2026, 3, 28, 12, in: london)
        let nights = UpcomingNight.nights(for: .everyNight(late), around: now, calendar: london)
        let skipped = try #require(nights.first { $0.name(in: london) == LocalDay(year: 2026, month: 3, day: 28) })
        #expect(skipped.windDownStart < skipped.bedtime && skipped.bedtime < skipped.morningStart)
        #expect(clock(skipped.morningStart, london) == "08:30")
        let result = plan(late, now: now, calendar: london)
        #expect(result.of(.windDown).count == 7)
        #expect(result.requests.allSatisfy { request in !nights.contains { request.fireDate > $0.bedtime && request.fireDate < $0.morningStart } })
    }

    @Test("A delivered wind-down reminder is cleared once it no longer holds")
    func staleDelivered() {
        // "Time to wind down" holds only during a wind-down the member hasn't started.
        #expect(!plan(now: at(2026, 10, 12, 22, 30)).staleDelivered.contains(.windDown))
        #expect(plan(now: at(2026, 10, 12, 22, 30), windDownOpenedAt: at(2026, 10, 12, 22, 20)).staleDelivered.contains(.windDown))
        #expect(plan(now: at(2026, 10, 12, 23, 30)).staleDelivered.contains(.windDown))
        #expect(plan(now: at(2026, 10, 12, 12)).staleDelivered.contains(.windDown))
    }

    @Test("Identifiers name their kind; anything else isn't Maple's")
    func kinds() {
        #expect(ReminderKind(identifier: "maple.reminder.windDown.2026-10-12") == .windDown)
        #expect(ReminderKind(identifier: "maple.reminder.morningLeaf.2026-10-12") == nil)
        #expect(ReminderKind(identifier: "maple.reminder.other") == nil)
        #expect(ReminderKind(identifier: "com.example.windDown") == nil)
    }

    @Test("Copy is calm: one short line each, no exclamation marks, no emoji")
    func copy() {
        let lines = [ReminderCopy.windDownTitle, ReminderCopy.windDownBody(bedtime: at(2026, 10, 12, 23), calendar: utc, locale: enGB)]
        for line in lines {
            #expect(!line.contains("!"))
            #expect(line.count <= 32)
            #expect(wordCount(line) <= 6)
            #expect(line.unicodeScalars.allSatisfy { !$0.properties.isEmojiPresentation })
            #expect(line.first?.isUppercase == true || line.first?.isNumber == true)
        }
    }
}
