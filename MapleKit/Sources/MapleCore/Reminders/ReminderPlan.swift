import Foundation

/// The local reminders Maple can send (M1): one as wind-down starts, and an opt-in morning check-in.
public enum ReminderKind: String, Codable, Sendable, CaseIterable {
    case windDown
    case morning

    /// The notification request's identifier. One per kind, so scheduling again replaces the earlier request.
    public var identifier: String { "com.maanvikgupta.maple.reminder.\(rawValue)" }
}

/// One reminder, ready for the notification centre: the clock time it repeats at every day, in the device's time
/// zone, and what it says.
public struct Reminder: Sendable, Hashable {
    public let kind: ReminderKind
    public let time: ClockTime
    public let title: String
    public let body: String
    /// Delivered without sound and without lighting the screen, so it waits in Notification Center.
    public let isQuiet: Bool

    public init(kind: ReminderKind, time: ClockTime, title: String, body: String, isQuiet: Bool) {
        self.kind = kind
        self.time = time
        self.title = title
        self.body = body
        self.isQuiet = isQuiet
    }
}

/// What Maple schedules for a sleep schedule, and when (architecture M1, rewards.md).
///
/// - **Wind-down** fires at the wind-down start, with a sound. It never mentions leaves or progress (rewards.md:
///   "Wind-down notifications never mention leaves or progress").
/// - **Morning** fires 30 minutes after the wake time, when the morning reveal opens, so the phone-free first half
///   hour is left alone. It is quiet (no sound, no lit screen) and also never mentions leaves; rewards.md has no
///   morning push, so it is off unless the member turns it on.
public enum ReminderPlan {
    /// Minutes after wake that the morning check-in arrives (the reveal opens 30 minutes after waking).
    public static let morningDelayMinutes = 30

    /// The reminders for `schedule`, wind-down first, with times in `locale`'s clock style.
    public static func reminders(
        for schedule: SleepSchedule, windDown: Bool, morning: Bool, locale: Locale
    ) -> [Reminder] {
        var reminders: [Reminder] = []
        if windDown { reminders.append(windDownReminder(for: schedule, locale: locale)) }
        if morning { reminders.append(morningReminder(for: schedule)) }
        return reminders
    }

    /// "Time to wind down" / "Bed at 23:00. Let the evening slow down." at the wind-down start.
    public static func windDownReminder(for schedule: SleepSchedule, locale: Locale) -> Reminder {
        Reminder(
            kind: .windDown, time: schedule.windDownStart, title: "Time to wind down",
            body: "Bed at \(HomeFormat.clock(schedule.bedtime, locale: locale)). Let the evening slow down.",
            isQuiet: false
        )
    }

    /// "Morning check-in" / "See how last night went." half an hour after the wake time.
    public static func morningReminder(for schedule: SleepSchedule) -> Reminder {
        Reminder(
            kind: .morning, time: morningTime(for: schedule), title: "Morning check-in",
            body: "See how last night went.", isQuiet: true
        )
    }

    /// Wake plus `morningDelayMinutes`, wrapping midnight.
    public static func morningTime(for schedule: SleepSchedule) -> ClockTime {
        let minutes = (schedule.wake.minutesSinceMidnight + morningDelayMinutes) % (24 * 60)
        return ClockTime(hour: minutes / 60, minute: minutes % 60)
    }
}
