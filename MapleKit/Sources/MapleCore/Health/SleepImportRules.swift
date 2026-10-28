import Foundation

/// Which nights M1's importer reads from Apple Health on each run. There is no backfill for leaves (rewards.md:
/// counting starts on the install night), so it never reads before the night before the install night; and it reads
/// at most the last 16 nights, which covers every night the ledger can still settle (it keeps 14 pending) and the
/// 72-hour window in which late Watch data upgrades a settled one. Every run sends all of them again, which the
/// ledger takes idempotently.
public enum SleepImportWindow {
    /// Nights read on every run, tonight's included.
    public static let nightsRead = 16

    /// The oldest night read: the night before the install night, or the 16th night back, whichever is later.
    public static func firstNight(installNight: LocalDay, now: Date, calendar: Calendar) -> LocalDay {
        let recent = SleepNightBuilder.night(containing: now, calendar: calendar).adding(days: -(nightsRead - 1), calendar: calendar)
        return max(installNight.adding(days: -1, calendar: calendar), recent)
    }

    /// When the window opens: 18:00 on the evening of `firstNight`.
    public static func start(installNight: LocalDay, now: Date, calendar: Calendar) -> Date {
        SleepNightBuilder.eveningStart(of: firstNight(installNight: installNight, now: now, calendar: calendar), calendar: calendar)
    }

    /// Home's last night (spec §3.4 "Morning, with sleep data"): the observation for the night `date` falls in, which
    /// in the morning is the night just ended. Nil when Apple Health has nothing for it, so an older night never
    /// shows as last night's sleep.
    public static func lastNight(in observations: [SleepNightObservation], at date: Date, calendar: Calendar) -> LastNightSleep? {
        let night = SleepNightBuilder.night(containing: date, calendar: calendar)
        return observations.last { $0.night == night }?.lastNightSleep
    }
}

extension SleepNightObservation {
    /// Home's morning numeral: time asleep, or for iPhone's in-bed estimate (no asleep time) the time in bed.
    public var lastNightSleep: LastNightSleep {
        LastNightSleep(asleep: onset, awake: finalWake, duration: asleepMinutes.map { $0 * 60 } ?? span)
    }
}

/// When Apple Health is connected but no sleep has come from it, Privacy and Home say how to get some: "No sleep from
/// Apple Health yet. Wear your Apple Watch to bed, or turn on Sleep in the Health app." It shows once two nights have
/// passed since connecting without a single sleep sample that counts.
public enum SleepDataHint {
    /// Nights without sleep before the hint shows.
    public static let nightsWithout = 2

    /// Nights that have passed since Apple Health was connected at `connectedAt`. A night has passed once noon the
    /// next day has come; the night connected in counts if it was connected before 06:00 the next morning.
    public static func nightsPassed(since connectedAt: Date, now: Date, calendar: Calendar) -> Int {
        let connectedNight = SleepNightBuilder.night(containing: connectedAt, calendar: calendar)
        let morning = connectedNight.adding(days: 1, calendar: calendar)
        let morningStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: morning.startDate(in: calendar))
            ?? morning.startDate(in: calendar)
        let first = connectedAt >= morningStart ? morning : connectedNight

        let today = LocalDay(now, calendar: calendar)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today.startDate(in: calendar))
            ?? today.startDate(in: calendar)
        let lastPassed = today.adding(days: now >= noon ? -1 : -2, calendar: calendar)
        return max(0, first.days(until: lastPassed, calendar: calendar) + 1)
    }

    /// Connected, two nights gone, and nothing from Apple Health yet.
    public static func isDue(connectedAt: Date?, hasReceivedSleep: Bool, now: Date, calendar: Calendar) -> Bool {
        guard let connectedAt, !hasReceivedSleep else { return false }
        return nightsPassed(since: connectedAt, now: now, calendar: calendar) >= nightsWithout
    }
}
