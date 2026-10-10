import Foundation
import MapleCore
import MapleDesign
import MapleServices

/// Builds `ReminderPlan`'s input from the app's stores: the coming nights of the member's schedule, the reminder
/// switches, the leaves still waiting (with the moment each may first open) and whether wind-down mode has been
/// opened. `ReminderUpkeep` reschedules with it whenever one of those changes.
@MainActor
enum ReminderInputs {
    static func plan(
        collection: CollectionStore, schedule: ScheduleStore, settings: AppSettings, bedside: BedsideLog, now: Date,
        locale: Locale
    ) -> ReminderPlan {
        let calendar = collection.context.calendar
        let waiting = collection.waiting.map { unlock in
            WaitingLeaf(
                speciesID: unlock.speciesID,
                opensAt: RevealSchedule.releaseDate(for: unlock, schedule: collection.schedule, calendar: calendar)
            )
        }
        return ReminderPlan(.init(
            nights: upcomingNights(schedule: schedule, around: now, calendar: calendar), settings: settings.reminders,
            waiting: waiting, windDownOpenedAt: bedside.session.startedAt, now: now, calendar: calendar, locale: locale
        ))
    }

    /// The nights the reminders are planned over: the one whose morning began last, then the next 7.
    private static func upcomingNights(schedule: ScheduleStore, around now: Date, calendar: Calendar) -> [UpcomingNight] {
        // TODO(integrator): use WeeklySleepSchedule.upcoming(...) (weekday and weekend schedules) instead of
        // repeating the one `ScheduleStore.schedule` every night.
        UpcomingNight.nights(for: schedule.schedule, around: now, calendar: calendar)
    }
}
