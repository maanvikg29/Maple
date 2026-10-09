import Foundation

/// A time of day without a date, e.g. 23:00.
public struct ClockTime: Codable, Sendable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// The member's sleep schedule: when wind-down starts, bedtime, and wake time.
public struct SleepSchedule: Codable, Sendable, Hashable {
    public var bedtime: ClockTime
    public var wake: ClockTime
    /// Minutes of wind-down before bedtime.
    public var windDownMinutes: Int

    public init(bedtime: ClockTime, wake: ClockTime, windDownMinutes: Int) {
        self.bedtime = bedtime
        self.wake = wake
        self.windDownMinutes = windDownMinutes
    }

    /// Used until the member sets their own schedule.
    public static let standard = SleepSchedule(bedtime: ClockTime(hour: 23), wake: ClockTime(hour: 7), windDownMinutes: 45)

    /// Wind-down start as a clock time.
    public var windDownStart: ClockTime {
        let minutes = (bedtime.minutesSinceMidnight - windDownMinutes + 24 * 60) % (24 * 60)
        return ClockTime(hour: minutes / 60, minute: minutes % 60)
    }

    /// Time in bed, in minutes.
    public var minutesInBed: Int {
        (wake.minutesSinceMidnight - bedtime.minutesSinceMidnight + 24 * 60) % (24 * 60)
    }
}

/// The part of the member's day; Home's numeral, caption and action follow it (design spec §3.3).
public enum NowPhase: String, Sendable, CaseIterable {
    case morning, day, evening, windDown, night
}
