import Foundation
import MapleCore
import MapleDesign
import MapleServices

/// Builds `ReminderPlan`'s input from the app's stores: the coming nights of the member's weekly schedule, the
/// reminder switch and whether wind-down mode has been opened. `ReminderUpkeep` reschedules with it whenever one of
/// those changes.
@MainActor
enum ReminderInputs {
    static func plan(
        collection: CollectionStore, schedule: ScheduleStore, settings: AppSettings, bedside: BedsideLog, now: Date,
        locale: Locale
    ) -> ReminderPlan {
        let calendar = collection.context.calendar
        return ReminderPlan(.init(
            nights: upcomingNights(schedule: schedule, around: now, calendar: calendar), settings: settings.reminders,
            windDownOpenedAt: bedside.session.startedAt, now: now, calendar: calendar, locale: locale
        ))
    }

    /// The nights the reminders are planned over: the one whose morning began last, then the next 7.
    private static func upcomingNights(schedule: ScheduleStore, around now: Date, calendar: Calendar) -> [UpcomingNight] {
        UpcomingNight.nights(for: schedule.weekly, around: now, calendar: calendar)
    }
}
