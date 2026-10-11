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
    /// The night whose morning started most recently (at or before `date`), then the next `count` nights, from the
    /// member's weekly schedule (`WeeklySleepSchedule.times(forNight:calendar:)`): weekend nights use the weekend
    /// schedule, and the times follow daylight-saving changes as the phases do.
    ///
    /// The first night gives `ReminderPlan` the last morning start; its own moments are in the past and schedule
    /// nothing.
    public static func nights(
        for weekly: WeeklySleepSchedule, around date: Date, count: Int = ReminderPlan.horizonDays, calendar: Calendar
    ) -> [UpcomingNight] {
        // Tonight is the night named by the day holding `date`; that day's morning was last night's morning start.
        let tonight = weekly.currentNight(at: date, calendar: calendar)
        return (-1..<max(0, count)).map { offset in
            let times = weekly.times(forNight: tonight.adding(days: offset, calendar: calendar), calendar: calendar)
            return UpcomingNight(
                windDownStart: times.windDownStart, bedtime: times.bedtime, wake: times.wake, morningStart: times.morningStart
            )
        }
    }
}
