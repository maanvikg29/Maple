#if DEBUG
import Foundation
import MapleCore
import MapleServices

/// DEBUG only: reminder states for simulator screenshots (docs/debug-launch-arguments.md).
///
/// - `-MapleDemoNotify windDown|morning` posts that reminder, with its real words, 5 seconds after launch (asking
///   iOS first if it hasn't been asked). Wind-down shows nothing while Maple is open, so open another app (or lock
///   the screen) to see its banner; the morning leaf shows as a banner over Maple too.
/// - `-MapleDemoNotifyPrimer step` opens the first run's reminders step full screen; `sheet` opens the primer
///   from Settings (with `-MapleDemoPresent profile -MapleDemoProfile settings`).
/// - `-MapleDemoNotifyStatus allowed|denied|notDetermined` shows Settings as if iOS had answered that way
///   (`NotificationScheduler.launch()` reads it); nothing is scheduled on a demo launch.
@MainActor
enum ReminderDemo {
    static let delay: TimeInterval = 5

    private static var defaults: UserDefaults { .standard }

    static var requestedKind: ReminderKind? {
        switch defaults.string(forKey: "MapleDemoNotify")?.lowercased() {
        case "winddown": .windDown
        case "morning", "morningleaf": .morningLeaf
        default: nil
        }
    }

    static var showsPrimerStep: Bool { defaults.string(forKey: "MapleDemoNotifyPrimer")?.lowercased() == "step" }
    static var showsPrimerSheet: Bool { defaults.string(forKey: "MapleDemoNotifyPrimer")?.lowercased() == "sheet" }

    static func postIfRequested(
        reminders: NotificationScheduler, schedule: ScheduleStore, collection: CollectionStore, locale: Locale
    ) async {
        guard let kind = requestedKind else { return }
        let calendar = collection.context.calendar
        let now = Date()
        let request: ReminderRequest
        switch kind {
        case .windDown:
            let night = UpcomingNight.nights(for: schedule.schedule, around: now, count: 1, calendar: calendar)
                .first { $0.bedtime > now }
            request = ReminderRequest(
                id: kind.identifierPrefix + "demo", kind: kind, fireDate: now.addingTimeInterval(delay), calendar: calendar,
                title: ReminderCopy.windDownTitle,
                body: ReminderCopy.windDownBody(bedtime: night?.bedtime ?? now, calendar: calendar, locale: locale),
                threadID: kind.threadID, interruption: .active, playsSound: true
            )
        case .morningLeaf:
            let count = max(1, collection.waiting.count)
            request = ReminderRequest(
                id: kind.identifierPrefix + "demo", kind: kind, fireDate: now.addingTimeInterval(delay), calendar: calendar,
                title: ReminderCopy.morningLeafTitle(count: count), body: ReminderCopy.morningLeafBody(count: count),
                threadID: kind.threadID, interruption: .passive, playsSound: false
            )
        }
        await reminders.postDemo(request, after: delay)
    }
}
#endif
