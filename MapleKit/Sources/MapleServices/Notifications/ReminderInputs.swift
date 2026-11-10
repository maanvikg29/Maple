import Foundation
import MapleCore

/// Builds `ReminderPlan`'s input from the app's stores: the coming nights of the member's weekly schedule, the
/// reminder switches, whether wind-down mode has been opened, and the session store's running session and latest
/// start. `ReminderUpkeep` reschedules with `plan(…sessions:…)` whenever one of those changes.
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

    /// The plan from the session store, on its trusted time (F1 design §3.2, §6): its running session, for the end
    /// reminder, and its latest start, so the study reminder skips that day.
    /// - Returns: Nil until the store has read its ledger. Before that it can't say whether a session runs, and a plan
    ///   without one would remove the running session's end reminder.
    public static func plan(
        collection: CollectionStore, schedule: ScheduleStore, settings: AppSettings, windDownOpenedAt: Date?,
        sessions: FocusSessionStore, locale: Locale
    ) -> ReminderPlan? {
        guard sessions.isLedgerReadable else { return nil }
        return plan(
            collection: collection, schedule: schedule, settings: settings, windDownOpenedAt: windDownOpenedAt,
            runningSession: sessions.reminderSession, lastSessionStart: sessions.lastSessionStart, now: sessions.now,
            locale: locale
        )
    }
}
