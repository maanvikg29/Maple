import Foundation

/// One night of the member's schedule as real moments: when wind-down starts, bedtime, wake-up and the start of
/// the next morning (wake − 60 min, spec §3.3). `ReminderPlan` is built from a run of these, so it never needs to
/// know how a schedule is stored (one schedule today, weekday and weekend sets later).
public struct UpcomingNight: Sendable, Hashable {
    public var windDownStart: Date
    public var bedtime: Date
    public var wake: Date
    /// The start of the morning after this night, when held leaves become openable.
    public var morningStart: Date

    public init(windDownStart: Date, bedtime: Date, wake: Date, morningStart: Date) {
        self.windDownStart = windDownStart
        self.bedtime = bedtime
        self.wake = wake
        self.morningStart = morningStart
    }

    /// The night's name: the evening it begins on, as the night ledger names nights (18:00 to 18:00 local).
    public func name(in calendar: Calendar) -> LocalDay {
        NightLedger.night(containing: bedtime, calendar: calendar)
    }
}

extension UpcomingNight {
    /// The night whose morning started most recently (at or before `date`), then the next `count` nights, from one
    /// schedule that repeats every day. Times are read in `calendar`'s time zone; a time that a daylight-saving
    /// change skips falls to the next minute that exists, as `PhaseWindows` does.
    ///
    /// The first night gives `ReminderPlan` the last morning start, so a leaf already announced that morning isn't
    /// announced again; its own moments are in the past and schedule nothing.
    ///
    /// This is the single-schedule stand-in; its only caller is the app's reminder wiring (`ReminderInputs`).
    public static func nights(
        for schedule: SleepSchedule, around date: Date, count: Int = ReminderPlan.horizonDays, calendar: Calendar
    ) -> [UpcomingNight] {
        // TODO(integrator): use WeeklySleepSchedule.upcoming(...) once weekday and weekend schedules land.
        let morningMinute = PhaseWindows(schedule: schedule).startMinute(of: .morning)
        let morning = ClockTime(hour: morningMinute / 60, minute: morningMinute % 60)
        // The latest morning start at or before `date`.
        guard var morningStart = moments(of: morning, around: date, days: -1...1, calendar: calendar)
            .last(where: { $0 <= date })
        else { return [] }
        var nights: [UpcomingNight] = []
        for _ in 0...max(0, count) {
            if let night = night(endingAt: morningStart, schedule: schedule, calendar: calendar) {
                nights.append(night)
            }
            guard let next = moments(of: morning, around: morningStart, days: 0...2, calendar: calendar)
                .first(where: { $0 > morningStart }) else { break }
            morningStart = next
        }
        return nights
    }

    /// The night that ends at `morningStart`: its bedtime is the last one before that morning, its wind-down
    /// starts `windDownMinutes` before bed, and wake-up is the first wake time from that morning on.
    private static func night(endingAt morningStart: Date, schedule: SleepSchedule, calendar: Calendar) -> UpcomingNight? {
        guard let bedtime = moments(of: schedule.bedtime, around: morningStart, days: -1...0, calendar: calendar)
            .last(where: { $0 < morningStart }),
            let wake = moments(of: schedule.wake, around: morningStart, days: 0...1, calendar: calendar)
                .first(where: { $0 >= morningStart })
        else { return nil }
        let windDownStart = bedtime.addingTimeInterval(-TimeInterval(max(0, schedule.windDownMinutes) * 60))
        return UpcomingNight(windDownStart: windDownStart, bedtime: bedtime, wake: wake, morningStart: morningStart)
    }

    /// `time` on each local day from `days` before to after the day of `date`, in order. A time the clocks skip
    /// falls to the next minute that exists; a time they repeat is its first occurrence.
    private static func moments(of time: ClockTime, around date: Date, days: ClosedRange<Int>, calendar: Calendar) -> [Date] {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        return days.compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: noon) else { return nil }
            return calendar.date(
                bySettingHour: time.hour, minute: time.minute, second: 0, of: day, matchingPolicy: .nextTime,
                repeatedTimePolicy: .first, direction: .forward
            )
        }
        .sorted()
    }
}
