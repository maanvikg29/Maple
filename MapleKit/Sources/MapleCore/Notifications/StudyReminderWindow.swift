import Foundation

/// The times the daily study reminder can be set to (F1 design §6: "it must fall in the Day phase"): the times in the
/// Day phase on every day of the member's week, so the reminder comes each day it is wanted. That is from the week's
/// latest Day start to the minute before its earliest Evening start, on the wall clock.
///
/// With the standard schedule (bed 23:00, wake 07:00, 45 minutes of wind-down) the Day phase runs 10:00–20:15, so
/// 10:00 to 20:14 can be chosen. 16:00 is suggested.
///
/// ```swift
/// let window = StudyReminderWindow(weekly: schedule.weekly, around: now, calendar: calendar)
/// window?.contains(ClockTime(hour: 21))    // false: "21:00 is outside your day now"
/// window?.suggestion                       // 16:00, or the nearest time that fits
/// ```
public struct StudyReminderWindow: Sendable, Hashable {
    /// The time offered when the reminder is first turned on (§6).
    public static let suggested = ClockTime(hour: 16)

    /// The earliest time that can be chosen.
    public let earliest: ClockTime
    /// The latest time that can be chosen.
    public let latest: ClockTime

    /// The window over the seven days from `date`'s day, which hold one of each weekday. Nil when the schedule leaves no
    /// time in the Day phase on all of them.
    public init?(weekly: WeeklySleepSchedule, around date: Date, calendar: Calendar) {
        let phases = PhaseWindows(weekly: weekly)
        let first = LocalDay(date, calendar: calendar)
        var earliest = 0
        var latest = 24 * 60 - 1
        for offset in 0..<7 {
            let day = first.adding(days: offset, calendar: calendar)
            let windows = phases.day(day, calendar: calendar)
            guard windows.dayStart < windows.evening else { return nil }
            earliest = max(earliest, Self.minute(of: windows.dayStart, on: day, calendar: calendar))
            // The Evening starts at `evening`: the last whole minute before it.
            latest = min(latest, Self.minute(of: windows.evening, on: day, calendar: calendar) - 1)
        }
        guard earliest <= latest else { return nil }
        self.earliest = ClockTime(hour: earliest / 60, minute: earliest % 60)
        self.latest = ClockTime(hour: latest / 60, minute: latest % 60)
    }

    public func contains(_ time: ClockTime) -> Bool {
        earliest <= time && time <= latest
    }

    /// `time`, or the window's nearest edge when it falls outside.
    public func nearest(to time: ClockTime) -> ClockTime {
        min(max(time, earliest), latest)
    }

    /// What the time sheet opens on when nothing is saved: 16:00, or the nearest time that fits.
    public var suggestion: ClockTime {
        nearest(to: Self.suggested)
    }

    /// `date` as wall-clock minutes from the start of `day`, rounded up to a whole minute. It is above 1,439 on the next
    /// calendar day, and below 0 on the one before.
    private static func minute(of date: Date, on day: LocalDay, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let days = LocalDay(date, calendar: calendar).ordinal - day.ordinal
        let whole = days * 24 * 60 + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return (parts.second ?? 0) > 0 || (parts.nanosecond ?? 0) > 0 ? whole + 1 : whole
    }
}
