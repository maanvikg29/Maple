import Foundation
import MapleCore

/// Builds `ReminderPlan`'s input from the app's stores: the coming nights of the member's weekly schedule, the
/// reminder switches, whether wind-down mode has been opened, and the running session. `ReminderUpkeep` reschedules
/// with it whenever one of those changes.
public enum ReminderInputs {
    /// - Parameters:
    ///   - windDownOpenedAt: When wind-down mode was last opened (the bedside log's start); nil if never.
    ///   - runningSession: The session running now, for its end reminder.
    ///   - lastSessionStart: When the latest session started, so the study reminder skips that day.
    public static func plan(
        collection: CollectionStore, schedule: ScheduleStore, settings: AppSettings, windDownOpenedAt: Date?,
        runningSession: ReminderPlan.RunningSession?, lastSessionStart: Date?, now: Date, locale: Locale
    ) -> ReminderPlan {
        let calendar = collection.context.calendar
        return ReminderPlan(.init(
            nights: UpcomingNight.nights(for: schedule.weekly, around: now, calendar: calendar), settings: settings.reminders,
            windDownOpenedAt: windDownOpenedAt, now: now, calendar: calendar, locale: locale, schedule: schedule.weekly,
            runningSession: runningSession, lastSessionStart: lastSessionStart
        ))
    }
}
