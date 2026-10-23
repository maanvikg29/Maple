import Foundation
import MapleFocusCore

extension AwakeWindow {
    /// The shortest sleep window credit allows (F1 design §3.3 step 6).
    public static let minimumSleep: TimeInterval = 6 * 3600

    /// One Maple day's awake window: from 60 minutes before last night's wake (moved later when that night was under
    /// 6 hours) to tonight's bedtime.
    /// - Parameter schedule: The weekly schedule that judges each night, named by its evening (the one in force at
    ///   18:00 that evening, `NightLedger.schedule(for:current:)`).
    public static func window(for day: LocalDay, schedule: (LocalDay) -> WeeklySleepSchedule, calendar: Calendar) -> AwakeWindow {
        let lastNight = day.adding(days: -1, calendar: calendar)
        let previous = schedule(lastNight).times(forNight: lastNight, calendar: calendar)
        let tonight = schedule(day).times(forNight: day, calendar: calendar)
        let wake = max(previous.wake, previous.bedtime.addingTimeInterval(minimumSleep))
        return AwakeWindow(start: wake.addingTimeInterval(-3600), end: tonight.bedtime, windDown: tonight.windDownStart)
    }

    /// The Maple day and window a session starting at `start` counts in, frozen into its plan: the latest day whose
    /// window holds the start, or, for a start inside a sleep window, the next day's (it counts from wake − 60).
    public static func frozen(at start: Date, schedule: (LocalDay) -> WeeklySleepSchedule, calendar: Calendar) -> (day: LocalDay, window: AwakeWindow) {
        let today = LocalDay(start, calendar: calendar)
        let candidates = (-1...2).map { offset -> (day: LocalDay, window: AwakeWindow) in
            let day = today.adding(days: offset, calendar: calendar)
            return (day, window(for: day, schedule: schedule, calendar: calendar))
        }
        if let holding = candidates.last(where: { $0.window.contains(start) }) { return holding }
        return candidates.first(where: { $0.window.start > start }) ?? candidates[candidates.count - 1]
    }
}

extension FocusPlan {
    /// The Maple day the session counts toward.
    public var day: LocalDay {
        LocalDay(label: mapleDay) ?? LocalDay(window.start, calendar: Calendar(identifier: .gregorian))
    }
}
