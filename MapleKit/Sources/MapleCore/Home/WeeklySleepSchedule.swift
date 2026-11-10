import Foundation

/// The member's week of nights: one `SleepSchedule` for weekday nights and, optionally, another for weekend nights
/// (spec §3.3 "weekday and weekend sets"; rewards.json "weekday and weekend schedules respected").
///
/// A night is named by its evening (`LocalDay`, as in `NightLedger`) and takes its variant from the morning it wakes
/// into: when that morning is a weekend day in the member's calendar (`Calendar.isDateInWeekend`, so the region's own
/// weekend), the night is a weekend night. With a Saturday–Sunday weekend, Friday and Saturday nights are weekend
/// nights; with a Friday–Saturday weekend, Thursday and Friday nights are.
///
/// ```swift
/// let weekly = schedule.weekly                                         // ScheduleStore
/// weekly.tonight(at: now, calendar: calendar).bedtime                  // "bed 23:00" on Home and Rest
/// weekly.schedule(forNight: LocalDay(…), calendar: calendar)           // one night's variant
/// weekly.upcoming(from: now, days: 7, calendar: calendar)              // [NightTimes] for reminders
/// ```
///
/// `weekend == nil` means the same schedule every night. Setting a weekend equal to the weekday schedule stores nil,
/// so two weeks that behave the same always compare equal.
public struct WeeklySleepSchedule: Sendable, Hashable {
    /// Which of the two schedules a night uses.
    public enum Variant: String, Codable, Sendable, CaseIterable {
        case weekday, weekend
    }

    /// Weekday nights, and every night while `weekend` is nil.
    public var weekday: SleepSchedule {
        didSet { if weekend == weekday { weekend = nil } }
    }
    /// Weekend nights; nil when they are the same as weekday nights.
    public var weekend: SleepSchedule? {
        didSet { if weekend == weekday { weekend = nil } }
    }

    public init(weekday: SleepSchedule, weekend: SleepSchedule? = nil) {
        self.weekday = weekday
        self.weekend = weekend == weekday ? nil : weekend
    }

    /// The same schedule every night.
    public static func everyNight(_ schedule: SleepSchedule) -> WeeklySleepSchedule {
        WeeklySleepSchedule(weekday: schedule)
    }

    /// Used until the member sets their own: `SleepSchedule.standard` every night.
    public static let standard = WeeklySleepSchedule.everyNight(.standard)

    /// Weekend nights have their own schedule.
    public var differsOnWeekends: Bool { weekend != nil }

    /// The schedule a variant uses (weekend nights fall back to the weekday schedule).
    public func schedule(for variant: Variant) -> SleepSchedule {
        switch variant {
        case .weekday: weekday
        case .weekend: weekend ?? weekday
        }
    }

    // MARK: Nights

    /// Whether `night` (named by its evening) is a weekend night: the morning it wakes into is a weekend day in
    /// `calendar` (its locale decides which days those are).
    public static func variant(forNight night: LocalDay, calendar: Calendar) -> Variant {
        let morning = night.adding(days: 1, calendar: calendar)
        let noon = calendar.date(byAdding: .hour, value: 12, to: morning.startDate(in: calendar)) ?? morning.startDate(in: calendar)
        return calendar.isDateInWeekend(noon) ? .weekend : .weekday
    }

    /// The schedule `night` (named by its evening) is planned with.
    public func schedule(forNight night: LocalDay, calendar: Calendar) -> SleepSchedule {
        schedule(for: Self.variant(forNight: night, calendar: calendar))
    }

    /// `night`'s wind-down, bedtime, wake and next-morning start as dates in `calendar`'s time zone.
    public func times(forNight night: LocalDay, calendar: Calendar) -> NightTimes {
        let variant = Self.variant(forNight: night, calendar: calendar)
        return NightTimes(night: night, variant: variant, schedule: schedule(for: variant), calendar: calendar)
    }

    /// The night Home and Rest call "tonight" at `date`: from this morning's start (an hour before today's wake) to
    /// the next morning's start, the night named by today's evening. At 02:00 it is still the night that began
    /// yesterday evening.
    public func currentNight(at date: Date, calendar: Calendar) -> LocalDay {
        PhaseWindows(weekly: self).day(containing: date, calendar: calendar).day
    }

    /// Tonight's schedule at `date` (see `currentNight(at:calendar:)`): its wind-down, bedtime and wake drive the
    /// evening, wind-down and night phases and every "bed 23:00" caption.
    public func tonight(at date: Date, calendar: Calendar) -> SleepSchedule {
        schedule(forNight: currentNight(at: date, calendar: calendar), calendar: calendar)
    }

    /// Last night's schedule at `date`: its wake time is this morning's, which drives the morning and day phases.
    public func lastNight(at date: Date, calendar: Calendar) -> SleepSchedule {
        schedule(forNight: currentNight(at: date, calendar: calendar).adding(days: -1, calendar: calendar), calendar: calendar)
    }

    /// The times of `days` nights, starting with tonight at `date` (`currentNight(at:calendar:)`), in order. Tonight
    /// is included even when some of its times have passed, so a caller scheduling reminders keeps those after
    /// `date` (`NightTimes.windDownStart > now`, …). Uses this schedule for every night: edits made later apply when
    /// they are made.
    public func upcoming(from date: Date, days: Int, calendar: Calendar) -> [NightTimes] {
        guard days > 0 else { return [] }
        let first = currentNight(at: date, calendar: calendar)
        return (0..<days).map { times(forNight: first.adding(days: $0, calendar: calendar), calendar: calendar) }
    }

    /// The evenings whose nights are weekend nights, as `Calendar` weekday numbers (1 is Sunday), in week order from
    /// Sunday: [6, 7] (Friday and Saturday) where the weekend is Saturday and Sunday.
    public static func weekendEvenings(calendar: Calendar) -> [Int] {
        // Any full week will do; this one starts on a Sunday.
        let sunday = LocalDay(year: 2026, month: 10, day: 4)
        return (0..<7).compactMap { offset in
            let evening = sunday.adding(days: offset, calendar: calendar)
            return variant(forNight: evening, calendar: calendar) == .weekend ? offset + 1 : nil
        }
    }
}

/// One night's times as dates: when wind-down starts, bedtime, wake, and the next morning's start. The phases (§3.3),
/// the night ledger and reminders all read these, so they always agree.
///
/// - Bedtime is that evening, or the next morning for a time before 18:00 (`NightLedger.date(_:on:calendar:)`).
/// - Wake is the first wake-up time after bedtime.
/// - Wind-down starts `windDownMinutes` before bedtime; the next morning starts an hour before wake.
public struct NightTimes: Sendable, Hashable {
    /// The night, named by its evening.
    public let night: LocalDay
    public let variant: WeeklySleepSchedule.Variant
    /// The schedule the night is planned with.
    public let schedule: SleepSchedule
    public let windDownStart: Date
    public let bedtime: Date
    public let wake: Date
    /// The next morning's start, an hour before wake: the morning phase begins, held leaves open and the night
    /// settles.
    public let morningStart: Date

    public init(night: LocalDay, variant: WeeklySleepSchedule.Variant, schedule: SleepSchedule, calendar: Calendar) {
        self.night = night
        self.variant = variant
        self.schedule = schedule
        let bedtime = NightLedger.date(schedule.bedtime, on: night, calendar: calendar)
        let parts = DateComponents(hour: schedule.wake.hour, minute: schedule.wake.minute, second: 0)
        let wake = calendar.nextDate(after: bedtime, matching: parts, matchingPolicy: .nextTime)
            ?? bedtime.addingTimeInterval(TimeInterval(schedule.minutesInBed * 60))
        self.bedtime = bedtime
        self.wake = wake
        windDownStart = bedtime.addingTimeInterval(-TimeInterval(max(0, schedule.windDownMinutes) * 60))
        morningStart = wake.addingTimeInterval(-3600)
    }
}

// MARK: - Codable

/// Saved as the weekday schedule's own fields plus an optional `weekend`, so a file written by a build before
/// weekend schedules decodes as the same schedule every night, and such a build still reads the weekday schedule
/// from a newer file. A `weekend` that can't be read is dropped rather than failing the file.
extension WeeklySleepSchedule: Codable {
    private enum CodingKeys: String, CodingKey {
        case bedtime, wake, windDownMinutes, weekend
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let weekday = SleepSchedule(
            bedtime: try c.decode(ClockTime.self, forKey: .bedtime),
            wake: try c.decode(ClockTime.self, forKey: .wake),
            windDownMinutes: try c.decode(Int.self, forKey: .windDownMinutes)
        )
        let weekend = (try? c.decodeIfPresent(SleepSchedule.self, forKey: .weekend)) ?? nil
        self.init(weekday: weekday, weekend: weekend)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekday.bedtime, forKey: .bedtime)
        try c.encode(weekday.wake, forKey: .wake)
        try c.encode(weekday.windDownMinutes, forKey: .windDownMinutes)
        try c.encodeIfPresent(weekend, forKey: .weekend)
    }
}
