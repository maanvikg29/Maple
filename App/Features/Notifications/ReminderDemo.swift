#if DEBUG
import Foundation
import MapleCore
import MapleServices

/// DEBUG only: reminder states for simulator screenshots (docs/debug-launch-arguments.md).
///
/// - `-MapleDemoNotify windDown|sessionEnd` posts that reminder, with its real words, 5 seconds after launch (asking
///   iOS first if it hasn't been asked). `sessionEnd` is named by the demo's running or last session. Maple presents
///   none of its notifications while it is open (`NotificationDelegate`), so open another app (or lock the screen) to
///   see the banner.
/// - `-MapleDemoNotifyTap sessionEnd` acts, 2 seconds after launch, as if the last ended session's end notification had
///   been tapped: the Focus tab opens on its receipt (`NotificationRouter`).
/// - `-MapleDemoNotifyPrimer step` opens the first run's reminders step full screen; `sheet` opens the primer
///   from Settings (with `-MapleDemoPresent profile -MapleDemoProfile settings`).
/// - `-MapleDemoNotifyStatus allowed|denied|notDetermined` shows Settings as if iOS had answered that way
///   (`NotificationScheduler.launch()` reads it); nothing is scheduled on a demo launch.
@MainActor
enum ReminderDemo {
    static let delay: TimeInterval = 5
    /// How long after launch `-MapleDemoNotifyTap` taps: the tabs and the first replay are up by then.
    static let tapDelay: TimeInterval = 2

    private static var defaults: UserDefaults { .standard }

    static var requestedKind: ReminderKind? {
        switch defaults.string(forKey: "MapleDemoNotify")?.lowercased() {
        case "winddown": .windDown
        case "sessionend": .sessionEnd
        default: nil
        }
    }

    static var tapsSessionEnd: Bool { defaults.string(forKey: "MapleDemoNotifyTap")?.lowercased() == "sessionend" }
    static var showsPrimerStep: Bool { defaults.string(forKey: "MapleDemoNotifyPrimer")?.lowercased() == "step" }
    static var showsPrimerSheet: Bool { defaults.string(forKey: "MapleDemoNotifyPrimer")?.lowercased() == "sheet" }

    static func postIfRequested(
        reminders: NotificationScheduler, schedule: ScheduleStore, collection: CollectionStore, sessions: FocusSessionStore,
        locale: Locale
    ) async {
        guard let kind = requestedKind else { return }
        let calendar = collection.context.calendar
        let now = Date()
        let request: ReminderRequest
        switch kind {
        case .windDown:
            let night = UpcomingNight.nights(for: schedule.weekly, around: now, count: 1, calendar: calendar)
                .first { $0.bedtime > now }
            request = ReminderRequest(
                id: kind.identifierPrefix + "demo", kind: kind, fireDate: now.addingTimeInterval(delay), calendar: calendar,
                title: ReminderCopy.windDownTitle,
                body: ReminderCopy.windDownBody(bedtime: night?.bedtime ?? now, calendar: calendar, locale: locale),
                threadID: kind.threadID, interruption: .active, playsSound: true
            )
        case .sessionEnd:
            if !sessions.isLedgerReadable { await sessions.refresh() }
            // The demo's session, so a tap on the banner opens its receipt; Study, 50 minutes when there is none.
            let session = sessions.running ?? sessions.lastEnded ?? sessions.sessions.last
            let isPlainTimer = session?.plan.kind == .plainTimer
            request = ReminderRequest(
                id: session.map { ReminderKind.sessionEndIdentifier(for: $0.id) } ?? kind.identifierPrefix + "demo",
                kind: kind, fireDate: now.addingTimeInterval(delay), calendar: calendar,
                title: isPlainTimer ? ReminderCopy.timerDoneTitle : ReminderCopy.sessionDoneTitle,
                body: ReminderCopy.sessionEndBody(
                    presetName: session?.plan.presetName ?? "Study", minutes: session?.plan.plannedMinutes ?? 50,
                    isPlainTimer: isPlainTimer
                ),
                threadID: kind.threadID, interruption: .active, playsSound: true, isAbsolute: true
            )
        case .studyReminder:
            return                                  // `requestedKind` names wind-down and a session's end only
        }
        await reminders.postDemo(request, after: delay)
    }

    /// `-MapleDemoNotifyTap sessionEnd`: the last ended session's end notification, tapped.
    static func tapIfRequested(notifications: NotificationRouter, sessions: FocusSessionStore) async {
        guard tapsSessionEnd else { return }
        try? await Task.sleep(for: .seconds(tapDelay))
        if !sessions.isLedgerReadable { await sessions.refresh() }
        guard let session = sessions.lastEnded ?? sessions.sessions.last(where: { $0.end != nil }) else { return }
        notifications.opened(ReminderKind.sessionEndIdentifier(for: session.id))
    }
}
#endif
